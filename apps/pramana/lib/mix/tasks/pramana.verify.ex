defmodule Mix.Tasks.Pramana.Verify do
  @shortdoc "Re-resolves baked segments and byte-compares them against raw/"

  @moduledoc """
  Data-integrity check for the phase gates (`docs/CHECKS.md`, section 3).

      mix pramana.verify              # sample 1000 segments PER TEXT
      mix pramana.verify --all        # check every segment; ~2m30s for the full Taisho
      mix pramana.verify --sample 50  # 50 per text

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
  alias Pramana.Normalize
  alias Pramana.Normalize.IR
  alias Pramana.Repo
  alias Pramana.URN

  @switches [sample: :integer, all: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    sample = if opts[:all], do: :all, else: Keyword.get(opts, :sample, 1000)

    texts = Repo.all(from t in Text, preload: [:work])

    if texts == [] do
      Mix.raise("nothing baked yet — run `mix pramana.bake` first")
    end

    results = Enum.map(texts, &verify_text(&1, sample))
    failures = Enum.flat_map(results, & &1.failures)

    report(results, failures)
  end

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
    with {:ok, xml} <- read_raw(text),
         {:ok, ir} <- renormalize(text, xml) do
      rebuilt = IR.body(ir)

      if rebuilt == text.body do
        :ok
      else
        {:renormalize_mismatch, text.urn_prefix,
         stored_chars: String.length(text.body), rebuilt_chars: String.length(rebuilt)}
      end
    else
      {:error, reason} -> {:renormalize_failed, text.urn_prefix, reason}
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

  defp report(results, []) do
    total = Enum.sum(Enum.map(results, & &1.segment_count))

    Mix.shell().info("""

    verify OK
      texts checked:    #{length(results)}
      segments checked: #{total}
      body re-normalized from raw/ and byte-identical for every text
    """)
  end

  defp report(_results, failures) do
    for f <- failures, do: Mix.shell().error("  #{inspect(f)}")

    Mix.raise("""
    verify FAILED with #{length(failures)} problem(s).

    This indicates silent corpus corruption — the bug class that produces citations
    which look correct and are not. Do not pass the phase gate. See docs/CHECKS.md.
    """)
  end
end
