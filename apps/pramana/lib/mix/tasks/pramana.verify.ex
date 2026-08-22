defmodule Mix.Tasks.Pramana.Verify do
  @shortdoc "Re-resolves baked segments and byte-compares them against raw/"

  @moduledoc """
  Data-integrity check for the phase gates (`docs/CHECKS.md`, section 3).

      mix pramana.verify                 # sample 1000 segments PER TEXT
      mix pramana.verify --all           # check every segment; ~2m30s for the full Taisho
      mix pramana.verify --sample 50     # 50 per text
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
  alias Pramana.Sources
  alias Pramana.URN

  @switches [sample: :integer, all: :boolean, source: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    sample = if opts[:all], do: :all, else: Keyword.get(opts, :sample, 1000)

    texts = Repo.all(scope(opts[:source]))

    if texts == [] do
      Mix.raise("nothing baked yet — run `mix pramana.bake` first")
    end

    started = System.monotonic_time(:millisecond)
    results = Enum.map(texts, &verify_text(&1, sample))
    elapsed = System.monotonic_time(:millisecond) - started
    failures = Enum.flat_map(results, & &1.failures)

    report(results, failures, elapsed)
  end

  # `--source` is for iterating on one pipeline; a gate runs the whole corpus.
  defp scope(nil), do: from(t in Text, preload: [:work])
  defp scope(source), do: from(t in Text, where: t.source_id == ^source, preload: [:work])

  defp verify_text(text, sample) do
    checks = [
      body_hash_check(text),
      renormalize_check(text)
    ]

    segments = load_segments(text, sample)
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

  defp reproduce(%{source_id: "derge"} = text), do: reproduce_derge(text, Derge)

  defp reproduce(%{source_id: "derge-tengyur"} = text), do: reproduce_derge(text, DergeTengyur)

  defp reproduce(text) do
    if Sources.local?(text.source_id) do
      reproduce_local(text)
    else
      with {:ok, xml} <- read_raw(text), do: renormalize(text, xml)
    end
  end

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

  defp read_raw(text) do
    canon = text.witness_id
    number = String.replace_prefix(text.work_id, canon, "")
    volume = String.to_integer(text.volume || "0")
    path = Path.join([Lockfile.raw_dir(), text.source_id, CBETA.work_path(canon, volume, number)])

    case File.read(path) do
      {:ok, xml} -> {:ok, xml}
      {:error, reason} -> {:error, {:raw_unreadable, path, reason}}
    end
  end

  defp renormalize(text, xml) do
    canon = text.witness_id
    number = String.replace_prefix(text.work_id, canon, "")

    Normalize.CBETA.normalize(xml,
      work_id: text.work_id,
      canon: canon,
      volume: text.volume && String.to_integer(text.volume),
      number: number
    )
  end

  defp load_segments(text, :all) do
    Repo.all(from s in Segment, where: s.text_id == ^text.id, order_by: s.ordinal)
  end

  defp load_segments(text, n) do
    Repo.all(
      from s in Segment,
        where: s.text_id == ^text.id,
        order_by: fragment("random()"),
        limit: ^n
    )
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

  defp report(results, [], elapsed) do
    total = Enum.sum(Enum.map(results, & &1.segment_count))

    Mix.shell().info("""

    verify OK
      texts checked:    #{length(results)}
      segments checked: #{total}
      elapsed:          #{Pramana.Elapsed.human(elapsed)} (#{Pramana.Elapsed.rate(length(results), elapsed)} texts/s)
      body re-normalized from raw/ and byte-identical for every text
    """)
  end

  defp report(_results, failures, _elapsed) do
    for f <- failures, do: Mix.shell().error("  #{inspect(f)}")

    Mix.raise("""
    verify FAILED with #{length(failures)} problem(s).

    This indicates silent corpus corruption — the bug class that produces citations
    which look correct and are not. Do not pass the phase gate. See docs/CHECKS.md.
    """)
  end
end
