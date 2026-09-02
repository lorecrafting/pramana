defmodule Mix.Tasks.Pramana.Verify do
  @shortdoc "Re-resolves baked segments and byte-compares them against raw/"

  @moduledoc """
  Data-integrity check for the phase gates (`docs/CHECKS.md`, section 3).

      mix pramana.verify                 # sample 1000 segments PER TEXT
      mix pramana.verify --all           # check every segment; ~2m30s for the full Taisho
      mix pramana.verify --sample 50     # 50 per text
      mix pramana.verify --sample 50 --seed 0.42   # ...and the same 50 next run
      mix pramana.verify --source derge  # one source, while iterating on its pipeline
      mix pramana.verify --source derge-tengyur

  `--sample N` is **per text**, not a corpus-wide total, so `--sample 1000` over 2,471
  texts checks about 1.2M segments rather than 1,000. Use `--all` at a phase gate.

  The whole-text checks (1 and 2 below) always run for EVERY text regardless of the
  sample; only the per-segment checks are sampled.

  Silent normalization corruption is the highest-consequence bug class in this
  project: a text that loads without error but has lost a `<lb/>`, mangled a gaiji, or
  had its CJK codepoints rewritten produces citations that look right and are wrong.
  Tests catch it for fixtures; this catches it for the actual bake.

  **This proves reproducibility, not fidelity.** It re-runs the same pipeline and
  compares, so content the pipeline drops deterministically is absent from both sides
  and the check still passes. `mix pramana.integrity` counts against the raw XML and is
  the one that catches loss. Run both at a gate.

  Checks, per text:

  1. `texts.body` still hashes to `body_sha256`
  2. re-normalizing from `raw/` reproduces the stored body **byte for byte**
  3. sampled segments' byte offsets slice their exact stored content out of the body
  4. sampled segments' `content_sha256` matches their content
  5. every sampled URN parses and is unique
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.CBETA
  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Local.Manifest, as: LocalManifest
  alias Pramana.Local.Normalizer, as: LocalNormalizer
  alias Pramana.Normalize
  alias Pramana.Normalize.Bilara
  alias Pramana.Normalize.Derge
  alias Pramana.Normalize.Derge.Edition, as: DergeEdition
  alias Pramana.Normalize.DergeTengyur
  alias Pramana.Normalize.IR
  alias Pramana.Repo
  alias Pramana.Sampling
  alias Pramana.Sources
  alias Pramana.URN

  # RE-NORMALISING A TEXT IS INDEPENDENT OF EVERY OTHER TEXT, and this was a sequential
  # `Enum.map` over 17,281 of them on eight cores — the single largest step in the gate.
  # `editions/1` is computed once before the loop and read-only inside it, so the Degé walk
  # that threads works across volumes in printed order still happens exactly once.
  #
  # FOUR, not eight, and the reason is memory rather than cores: `scope/1` selects whole
  # `Text` rows, so all 17,281 bodies — ~548M characters — are already resident before this
  # line, and each task then builds an IR of its own on a 16 GB machine. Raising this
  # without first making the text load streaming is how a verify run starts swapping.
  @concurrency 4

  # A CHUNK AT A TIME — bounded memory AND bulk queries, which the first two versions traded
  # against each other. Loading every body up front cost ~548M characters resident and got
  # `--all` SIGTERMed twice; loading one body per text fixed that and replaced a single query
  # with **17,281 primary-key round-trips**, taking `--all` from a recorded ~26 min to
  # **46m56s**. Both were measured, which is the only reason either was known.
  #
  # 200 per chunk: 87 queries instead of 17,281, and at most 200 bodies resident.
  @chunk 200

  @switches [sample: :integer, all: :boolean, source: :string, seed: :float]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    sample = if opts[:all], do: :all, else: Keyword.get(opts, :sample, 1000)

    sources = sources_for(opts[:source])

    started = System.monotonic_time(:millisecond)
    results = Enum.flat_map(sources, &verify_source(&1, sample, opts[:seed]))
    elapsed = System.monotonic_time(:millisecond) - started

    if results == [] do
      Mix.raise("nothing baked yet — run `mix pramana.bake` first")
    end

    failures = Enum.flat_map(results, & &1.failures)

    report(results, failures, elapsed, opts[:source])
  end

  # ONE SOURCE AT A TIME, EVEN FOR `--all` — and this is a measurement, not a preference.
  #
  # Verifying every source in a single pass took **46m48s** on 2026-08-29 while the same work
  # done per source summed to **6.2 minutes**: cbeta 1m09s, sc 4.5s, derge 3m52s, tengyur
  # 1m02s. Forty minutes unaccounted for, and two explanations were eliminated — it is not
  # the per-text round-trips (chunking restored bulk queries and the time did not move) and
  # reverting the Postgres tuning did not recover it either.
  #
  # What per-source changes structurally is residency: `editions/1` derives the full IR of
  # every Degé work in its edition, and a single pass holds **both** Kangyur and Tengyur maps
  # — 4,575 works — for the whole run, where this releases each before the next source
  # begins. The pathology is still not fully explained; this ships the path that was measured
  # rather than the one that needs a theory.
  #
  # Coverage is unchanged: sources are enumerated from the DATABASE, never a list. A
  # hand-written loop over four of them silently skipped `local-huang-nianzu-jie` and checked
  # 17,280 of 17,281 texts.
  defp verify_source(source, sample, seed) do
    from(t in ids_scope(source), select: t.id, order_by: t.id)
    |> Repo.all()
    |> Stream.chunk_every(@chunk)
    |> Stream.flat_map(fn chunk ->
      chunk
      |> load_texts()
      |> Task.async_stream(&verify_text(&1, sample, seed),
        max_concurrency: @concurrency,
        ordered: true,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)
    end)
    |> Enum.to_list()
  end

  defp sources_for(nil) do
    Repo.all(from t in Text, select: t.source_id, distinct: true, order_by: t.source_id)
  end

  defp sources_for(source), do: [source]

  # Loads one chunk's bodies in a single query. See `@chunk`.
  defp load_texts(ids) do
    Repo.all(from t in Text, where: t.id in ^ids, order_by: t.id, preload: [:work])
  end

  # Counted through the SAME scope the run used, so the denominator cannot drift from the
  # numerator when `--source` narrows it.
  defp available_segments(source) do
    query =
      from s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        select: count(s.id)

    query
    |> then(fn q -> if source, do: where(q, [_s, t], t.source_id == ^source), else: q end)
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp coverage(_checked, 0), do: "no segments"
  defp coverage(checked, available) when checked >= available, do: "every segment"
  defp coverage(checked, available), do: "#{Float.round(checked / available * 100, 1)}% — SAMPLED"

  # WITHOUT THE PRELOAD, because Ecto refuses `preload` alongside a narrowed `select` —
  # "the binding used in `from` must be selected in `select`". `scope/1` carries
  # `preload: [:work]` for the full-row load, so the id pass needs its own query rather than
  # a reuse of that one. Compiled clean and passed 1,435 tests before failing on the first
  # line of the real run: nothing in the suite exercises this task's `run/1`.
  # `--source` is for iterating on one pipeline; a gate runs the whole corpus.
  defp ids_scope(nil), do: from(t in Text)
  defp ids_scope(source), do: from(t in Text, where: t.source_id == ^source)

  # THERE IS NO PRECOMPUTED EDITION, AND THAT IS A MEASURED DECISION — 2026-09-01.
  #
  # There used to be one: every Degé work derived once by walking each volume a single
  # time, because verifying work-by-work re-parses each volume about sixteen times and had
  # been measured at ~90 minutes for the Tengyur, "97% of the whole gate". That was true
  # when it was written. It stopped being true when audit item #10 took `texts.body` out
  # of the load path and made loading chunked, and nobody re-measured the optimisation
  # those changes had made obsolete — rule 47.
  #
  # Measured on this machine, both sources, both ways, all green and byte-identical:
  #
  #     source          precomputed walk        per-work fallback
  #     derge           3m16s   6.1 texts/s     13s     87.6 texts/s
  #     derge-tengyur   20m30s  2.7 texts/s     1m01s   55.3 texts/s
  #
  # FIFTEEN TO TWENTY TIMES SLOWER, and the mechanism is memory rather than parsing. The
  # walk materialises every IR in the edition — 891,169 Tengyur lines — and holds them for
  # the whole run: 3.7 GB resident against 830 MB, and achieved parallelism halves (181%
  # CPU against 373%) because garbage collection dominates. The fallback re-parses each
  # volume sixteen times, but inside `Task.async_stream` workers whose garbage is
  # short-lived and collected per task. Sixteen times less parsing is not worth a
  # multi-gigabyte retained heap on a box that is also running Postgres.
  #
  # It was also the sixth instance of audit #10's own pattern: materialise everything to
  # avoid recomputing it, and pay in memory.
  #
  # `Pramana.Normalize.Derge.Edition.reduce/4` is untouched and still the ingest's walk,
  # where threading works across volumes in printed order is the whole mechanism and there
  # is no per-work alternative.

  defp verify_text(text, sample, seed) do
    checks = [
      body_hash_check(text),
      renormalize_check(text)
    ]

    segments = load_segments(text, sample, seed)
    checks = checks ++ segment_checks(text, segments)

    %{
      text: text,
      segment_count: length(segments),
      failures: Enum.reject(checks, &(&1 == :ok))
    }
  end

  defp body_hash_check(text) do
    actual = :crypto.hash(:sha256, text.body) |> Base.encode16(case: :lower)

    if actual == text.body_sha256,
      do: :ok,
      else: {:body_hash_mismatch, text.urn_prefix, expected: text.body_sha256, actual: actual}
  end

  # The strongest check available: go back to the untouched upstream bytes, run the
  # normalizer again, and require an identical body. This is what makes the bake
  # reproducible rather than merely persisted.
  defp renormalize_check(text) do
    case reproduce(text) do
      {:ok, ir} -> compare_body(text, IR.body(ir))
      {:error, reason} -> {:renormalize_failed, text.urn_prefix, reason}
    end
  end

  defp compare_body(text, rebuilt) do
    if rebuilt == text.body do
      :ok
    else
      {:renormalize_mismatch, text.urn_prefix,
       stored_chars: String.length(text.body), rebuilt_chars: String.length(rebuilt)}
    end
  end

  # Re-derives a text's IR from whatever its source of truth is. A CBETA text comes
  # from pinned TEI in `raw/`; a locally-added text comes from its own `text/` directory,
  # which the lockfile hashes the same way. Assuming every text was CBETA made this
  # check fail on a legitimately added local source.
  defp reproduce(%{source_id: "sc"} = text), do: reproduce_bilara(text)

  defp reproduce(%{source_id: source_id} = text)
       when source_id in ["derge", "derge-tengyur"] do
    reproduce_derge(text, normalizer_for(source_id))
  end

  defp reproduce(text) do
    if Sources.local?(text.source_id) do
      reproduce_local(text)
    else
      reproduce_cbeta(text, volumes(text))
    end
  end

  # A CBETA work usually occupies one volume, and six X works occupy two. Re-deriving
  # one of those from a single file rebuilds half the text and the comparison fails
  # with a character count and no reason, so every volume it was assembled from is
  # re-walked in printed order — the same shape as the Derge path above, for the same
  # reason.
  defp reproduce_cbeta(text, volumes) do
    volumes
    |> Enum.zip(cbeta_paths(text, volumes))
    |> Enum.reduce_while({:ok, []}, fn {volume, path}, {:ok, acc} ->
      with {:ok, xml} <- read_raw(path),
           {:ok, ir} <- renormalize(text, xml, volume) do
        {:cont, {:ok, [ir | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, parts |> Enum.reverse() |> IR.concat()}
      error -> error
    end
  end

  # `meta["volumes"]` is written by the loader for an assembled work and is the only
  # record of the span: `text.volume` reads "81-82" there, and parsing a range back out
  # of a display string is how the two halves of a fact drift apart.
  defp volumes(%{meta: %{"volumes" => volumes}}) when is_list(volumes) and volumes != [],
    do: volumes

  defp volumes(text), do: [text.volume && String.to_integer(text.volume)]

  defp normalizer_for("derge"), do: Derge
  defp normalizer_for("derge-tengyur"), do: DergeTengyur

  # One bilara file holds several works, so the work id alone cannot find its source.
  # The path is recorded at ingest for exactly this reason.
  defp reproduce_bilara(%{meta: %{"source_file" => path}} = text) when is_binary(path) do
    with {:ok, json} <- File.read(path),
         {:ok, irs} <- Bilara.normalize_file(json, witness: text.witness_id) do
      pick_work(irs, text.work_id, path)
    end
  end

  defp reproduce_bilara(text), do: {:error, {:no_source_file, text.work_id}}

  # A Derge work can run across thirteen volumes and only the first one names it, so
  # re-deriving one means re-walking every volume it was drawn from, in printed order.
  # The ingest records all of them for this reason; one path would re-derive a fragment
  # and the comparison would fail without saying why.
  defp reproduce_derge(%{meta: %{"source_file" => paths}} = text, normalizer)
       when is_binary(paths) do
    with {:ok, volumes} <- read_volumes(String.split(paths, " ", trim: true), normalizer) do
      DergeEdition.reproduce(volumes, text.work_id, normalizer: normalizer)
    end
  end

  defp reproduce_derge(text, _normalizer), do: {:error, {:no_source_file, text.work_id}}

  # The volume number comes from each file's own title page, exactly as it did at ingest.
  # Deriving it from the order of the recorded paths instead would reproduce the text
  # with anchors that agree with themselves and with nothing printed.
  defp read_volumes(paths, normalizer) do
    paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case read_volume(path, normalizer) do
        {:ok, volume} -> {:cont, {:ok, [volume | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, volumes} -> {:ok, Enum.sort_by(volumes, &elem(&1, 0))}
      error -> error
    end
  end

  defp read_volume(path, normalizer) do
    case File.read(path) do
      {:ok, source} -> named(source, path, normalizer)
      {:error, reason} -> {:error, {:raw_unreadable, path, reason}}
    end
  end

  # Where the volume number lives is a fact about the format. The Kangyur's TEI prints it
  # on the volume's own title page; the Tengyur's plain text has no header at all and
  # carries it in the filename — `079_རྒྱུད་འགྲེལ།_ཚུ.txt`. Deriving it from the ORDER of
  # the recorded paths would reproduce a text whose anchors agree with themselves and with
  # nothing printed.
  defp named(source, path, Derge) do
    case Derge.volume_number(source) do
      {:ok, volume} -> {:ok, {volume, source}}
      :error -> {:error, {:volume_unnamed, path}}
    end
  end

  defp named(source, path, DergeTengyur) do
    case Regex.run(~r/^(\d+)_/, Path.basename(path)) do
      [_, number] -> {:ok, {String.to_integer(number), source}}
      nil -> {:error, {:volume_unnamed, path}}
    end
  end

  defp pick_work(irs, work_id, path) do
    case Enum.find(irs, &(&1.work_id == work_id)) do
      nil -> {:error, {:work_absent_from_file, work_id, path}}
      ir -> {:ok, ir}
    end
  end

  defp reproduce_local(text) do
    dir = Path.join(["sources", "local", String.replace_prefix(text.source_id, "local-", "")])

    with {:ok, manifest} <- load_manifest(dir) do
      LocalNormalizer.normalize(dir, manifest: manifest)
    end
  end

  defp load_manifest(dir) do
    case LocalManifest.load(dir) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, errors} -> {:error, {:manifest_invalid, dir, errors}}
    end
  end

  # THE RECORDED PATH FIRST, reconstruction only for a text baked before paths were
  # stored. `CBETA.work_path/3` pads the volume to two digits and the width belongs to the
  # edition — T, X, J, K, S and M use two, while A, P, L and U use three — so rebuilding
  # `A/A091/A091n1057.xml` from volume 91 produces `A/A91/A91n1057.xml`, which does not
  # exist. Two works failed to bake that way before the path was carried, and this check
  # would have failed on them identically.
  defp cbeta_paths(%{meta: %{"source_file" => recorded}}, volumes)
       when is_binary(recorded) and recorded != "" do
    case String.split(recorded, " ", trim: true) do
      paths when length(paths) == length(volumes) -> paths
      _ -> rebuilt_paths(volumes, nil)
    end
  end

  defp cbeta_paths(text, volumes), do: rebuilt_paths(volumes, text)

  defp rebuilt_paths(volumes, nil), do: Enum.map(volumes, fn _ -> "" end)

  defp rebuilt_paths(volumes, text) do
    canon = text.witness_id
    number = String.replace_prefix(text.work_id, canon, "")

    Enum.map(volumes, fn volume ->
      Path.join([Lockfile.raw_dir(), text.source_id, CBETA.work_path(canon, volume || 0, number)])
    end)
  end

  defp read_raw(path) do
    case File.read(path) do
      {:ok, xml} -> {:ok, xml}
      {:error, reason} -> {:error, {:raw_unreadable, path, reason}}
    end
  end

  defp renormalize(text, xml, volume) do
    canon = text.witness_id
    number = String.replace_prefix(text.work_id, canon, "")

    Normalize.CBETA.normalize(xml,
      work_id: text.work_id,
      canon: canon,
      volume: volume,
      number: number
    )
  end

  defp load_segments(text, :all, _seed) do
    Repo.all(from s in Segment, where: s.text_id == ^text.id, order_by: s.ordinal)
  end

  # SEEDABLE, BECAUSE AN UNSEEDED SPOT CHECK CANNOT BE COMPARED WITH THE ONE BEFORE IT.
  # `--sample` drew a different set of segments every run, so a run that passed and a run
  # that failed were checking different things and neither could confirm the other. CLAUDE.md
  # has asserted "a measurement task takes `--seed`" throughout, and this task did not.
  #
  # `--all` remains the honest default for a published figure; the seed makes a *sample*
  # reproducible, which is a weaker and still useful thing.
  defp load_segments(text, n, seed) do
    base = from s in Segment, where: s.text_id == ^text.id, limit: ^n

    base
    |> seeded_order(seed)
    |> Repo.all()
  end

  # Keyed on the primary key, for the reason `Pramana.Recall` records: a hash order is only
  # as reproducible as its key is unique, and a non-unique key hands the tie-break back to
  # the planner.
  defp seeded_order(query, nil), do: order_by(query, fragment("random()"))

  defp seeded_order(query, seed) do
    order_by(query, [s], fragment("md5(? || ?::text)", ^Sampling.salt(seed), s.id))
  end

  defp segment_checks(text, segments) do
    offset_failures =
      Enum.reject(segments, fn s ->
        binary_part(text.body, s.byte_start, s.byte_end - s.byte_start) == s.content
      end)

    hash_failures =
      Enum.reject(segments, fn s ->
        :crypto.hash(:sha256, s.content) |> Base.encode16(case: :lower) == s.content_sha256
      end)

    urn_failures = Enum.reject(segments, &match?({:ok, _}, URN.parse(&1.urn)))
    urns = Enum.map(segments, & &1.urn)
    dupes = length(urns) - length(Enum.uniq(urns))

    [
      count_check(:offsets_unresolvable, offset_failures),
      count_check(:content_hash_mismatch, hash_failures),
      count_check(:urn_unparseable, urn_failures),
      if(dupes == 0, do: :ok, else: {:duplicate_urns, dupes})
    ]
  end

  defp count_check(_label, []), do: :ok
  defp count_check(label, failures), do: {label, length(failures), Enum.take(failures, 3)}

  # PUBLISH THE GAP, NOT JUST THE TOTAL — rules 22, 44 and 54, inside the gate's own
  # verification step. This printed `segments checked: 2,487,559` above a green `verify OK`,
  # and without `--all` that is **23%** of cbeta's 10,788,972: the default samples 1,000
  # segments per text and nothing in the output said so. A reader sees a check over 4,263
  # texts and concludes the corpus was verified.
  #
  # It also nearly produced a fabricated 4.5x speedup on 2026-08-29, by comparing a sampled
  # run against a full baseline — the coverage was in the numbers all along and unreadable
  # without its denominator.
  defp report(results, [], elapsed, source) do
    checked = Enum.sum(Enum.map(results, & &1.segment_count))
    available = available_segments(source)

    Mix.shell().info("""

    verify OK
      texts checked:    #{length(results)}
      segments checked: #{checked} of #{available} (#{coverage(checked, available)})
      elapsed:          #{Pramana.Elapsed.human(elapsed)} (#{Pramana.Elapsed.rate(length(results), elapsed)} texts/s)
      body re-normalized from raw/ and byte-identical for every text
    """)
  end

  defp report(_results, failures, _elapsed, _source) do
    for f <- failures, do: Mix.shell().error("  #{inspect(f)}")

    Mix.raise("""
    verify FAILED with #{length(failures)} problem(s).

    This indicates silent corpus corruption — the bug class that produces citations
    which look correct and are not. Do not pass the phase gate. See docs/CHECKS.md.
    """)
  end
end
