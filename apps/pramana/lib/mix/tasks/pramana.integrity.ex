defmodule Mix.Tasks.Pramana.Integrity do
  @shortdoc "Corpus-wide fidelity check: nothing printed in raw/ is missing from the bake"

  @moduledoc """
  Proves the bake did not silently *lose* anything, across the whole corpus.

      mix pramana.integrity
      mix pramana.integrity --limit 50    # a slice, for iterating

  ## Why this exists alongside `mix pramana.verify`

  They answer different questions, and conflating them is how a real defect survived a
  passing gate.

  `verify` re-normalizes from `raw/` and byte-compares against the stored body. That
  proves **reproducibility** — the pipeline is deterministic. It cannot prove
  **fidelity**, because a pipeline that drops the same content on every run drops it
  identically on both sides of the comparison and the check passes.

  That is not hypothetical. It is how 10,590 printed lines — including 473 rare
  characters and 266,547 characters of interlinear note text — sat unreachable in a
  corpus that verified clean. This task counts against the **raw XML** instead.

  ## What it checks

  1. **No `<lb/>` is lost.** Every line-beginning in the raw body must produce exactly
     one IR line. The `<lb/>` is not decoration, it *is* the citation.
  2. **Every non-blank line is addressable.** A line is allowed to have no segment only
     if nothing at all was printed on it — no text, no note, no apparatus, no gaiji.
  3. **No gaiji is stranded.** Every `<g/>` in the raw body must be reachable from some
     segment. Rare characters are exactly the content a reader cannot reconstruct.

  Counts are reported even when they pass, because the numbers are the evidence.
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
  alias Pramana.Repo

  @switches [limit: :integer]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    texts = Repo.all(from t in Text, order_by: t.work_id) |> maybe_limit(opts[:limit])

    if texts == [], do: Mix.raise("nothing baked yet — run `mix pramana.bake_all` first")

    totals = Enum.reduce(texts, empty_totals(), &check_text/2)

    report(length(texts), totals)
  end

  defp maybe_limit(texts, nil), do: texts
  defp maybe_limit(texts, n), do: Enum.take(texts, n)

  defp empty_totals do
    %{lb: 0, ir_lines: 0, segments: 0, blank: 0, g_raw: 0, ir_gaiji: 0, meta_gaiji: 0, bad: []}
  end

  # A local page-anchored text has no `<lb/>` and no `<g/>` — those are TEI concepts.
  # Its equivalent question is the same one in different terms: did every file in
  # `text/` become a line, and did every line with content get an addressable segment?
  # Pretending the TEI checks apply would produce a green tick for a check that never
  # ran.
  # bilara gives segment ids directly, so there is no `<lb/>` to lose and no gaiji. The
  # equivalent question is whether every id in the file became an addressable segment.
  defp check_text(%{source_id: "sc"} = text, totals) do
    {:ok, json} = File.read(text.meta["source_file"])
    {:ok, irs} = Bilara.normalize_file(json, witness: text.witness_id)
    ir = Enum.find(irs, &(&1.work_id == text.work_id))

    segments = Repo.one(from s in Segment, where: s.text_id == ^text.id, select: count(s.id))
    blank = Enum.count(ir.lines, &(&1.text == ""))
    printed = length(ir.lines) - blank

    bad =
      if printed != segments,
        do: [{text.work_id, :line_unaddressable, printed, segments}],
        else: []

    %{
      totals
      | lb: totals.lb + length(ir.lines),
        ir_lines: totals.ir_lines + length(ir.lines),
        segments: totals.segments + segments,
        blank: totals.blank + blank,
        bad: totals.bad ++ bad
    }
  end

  defp check_text(%{source_id: "local-" <> id} = text, totals) do
    dir = Path.join(["sources", "local", id])
    {:ok, manifest} = LocalManifest.load(dir)
    {:ok, ir} = LocalNormalizer.normalize(dir, manifest: manifest)

    segments = Repo.one(from s in Segment, where: s.text_id == ^text.id, select: count(s.id))
    blank = Enum.count(ir.lines, &blank?/1)
    printed = length(ir.lines) - blank

    bad =
      [
        length(manifest.files) != length(ir.lines) &&
          {text.work_id, :file_lost, length(manifest.files), length(ir.lines)},
        printed != segments && {text.work_id, :line_unaddressable, printed, segments}
      ]
      |> Enum.filter(& &1)

    %{
      totals
      | lb: totals.lb + length(manifest.files),
        ir_lines: totals.ir_lines + length(ir.lines),
        segments: totals.segments + segments,
        blank: totals.blank + blank,
        bad: totals.bad ++ bad
    }
  end

  defp check_text(text, totals) do
    xml = File.read!(raw_path(text))
    {:ok, ir} = renormalize(text, xml)

    body = body_region(xml)
    lb = count(body, "<lb ")
    g_raw = count(body, "<g ")

    segments = Repo.one(from s in Segment, where: s.text_id == ^text.id, select: count(s.id))

    meta_gaiji =
      Repo.one(
        from s in Segment,
          where: s.text_id == ^text.id and fragment("? \\? 'gaiji'", s.meta),
          select: coalesce(sum(fragment("jsonb_array_length(? -> 'gaiji')", s.meta)), 0)
      ) || 0

    blank = Enum.count(ir.lines, &blank?/1)
    printed = length(ir.lines) - blank
    ir_gaiji = Enum.sum(Enum.map(ir.lines, &length(&1.gaiji)))
    stranded = ir.lines |> Enum.filter(&blank?/1) |> Enum.map(&length(&1.gaiji)) |> Enum.sum()

    bad =
      [
        lb != length(ir.lines) && {text.work_id, :lb_lost, lb, length(ir.lines)},
        printed != segments && {text.work_id, :line_unaddressable, printed, segments},
        stranded > 0 && {text.work_id, :gaiji_stranded, stranded, 0}
      ]
      |> Enum.filter(& &1)

    %{
      totals
      | lb: totals.lb + lb,
        ir_lines: totals.ir_lines + length(ir.lines),
        segments: totals.segments + segments,
        blank: totals.blank + blank,
        g_raw: totals.g_raw + g_raw,
        ir_gaiji: totals.ir_gaiji + ir_gaiji,
        meta_gaiji: totals.meta_gaiji + meta_gaiji,
        bad: totals.bad ++ bad
    }
  end

  # A line may be dropped only when NOTHING was printed on it. Text, an interlinear
  # note, a variant reading and a rare character are all printed content.
  defp blank?(line),
    do: line.text == "" and line.notes == [] and line.apparatus == [] and line.gaiji == []

  # `<back>` reproduces body text in its apparatus lemmas, so counting the whole file
  # would double-count both <lb/> and <g/>.
  defp body_region(xml) do
    case String.split(xml, "<body>", parts: 2) do
      [_, rest] -> rest |> String.split("</body>", parts: 2) |> hd()
      _ -> ""
    end
  end

  defp count(haystack, needle), do: length(String.split(haystack, needle)) - 1

  defp raw_path(text) do
    number = String.replace_prefix(text.work_id, text.witness_id, "")
    volume = String.to_integer(text.volume || "0")

    Path.join([
      Lockfile.raw_dir(),
      text.source_id,
      CBETA.work_path(text.witness_id, volume, number)
    ])
  end

  defp renormalize(text, xml) do
    number = String.replace_prefix(text.work_id, text.witness_id, "")

    Normalize.CBETA.normalize(xml,
      work_id: text.work_id,
      canon: text.witness_id,
      volume: text.volume && String.to_integer(text.volume),
      number: number
    )
  end

  defp report(text_count, %{bad: []} = t) do
    Mix.shell().info("""

    integrity OK — #{text_count} text(s)

      source anchors:           #{t.lb}   (<lb/> in TEI, page files in a local text)
      IR lines:                 #{t.ir_lines}   (every anchor produced a line)

      lines with printed content: #{t.ir_lines - t.blank}
      segments in the bake:       #{t.segments}   (every one is addressable)
      genuinely blank, skipped:   #{t.blank}

      <g/> in raw body:           #{t.g_raw}
      gaiji on IR lines:          #{t.ir_gaiji}   (repeats collapsed per line)
      gaiji reachable in segments: #{t.meta_gaiji}
      stranded on dropped lines:   0
    """)
  end

  defp report(_text_count, t) do
    for {work, kind, expected, actual} <- Enum.take(t.bad, 25) do
      Mix.shell().error("  #{work}: #{kind} — raw #{expected}, bake #{actual}")
    end

    Mix.raise("""
    integrity FAILED for #{length(t.bad)} text(s).

    Content printed in the source edition is missing from the bake. Note that
    `mix pramana.verify` can still pass while this fails: it compares the bake against
    a re-run of the same pipeline, so anything dropped deterministically is dropped on
    both sides. Reproducibility is not fidelity. See docs/CHECKS.md.
    """)
  end
end
