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
  4. **Every acquired file reached the corpus.** Counted from the lockfile before any
     parsing: files -> works -> texts loaded. The first three checks all start from a
     text row, so none of them can see a work that never became one. Six CBETA X works
     had been overwritten by their own second volume and passed every other check.

  Counts are reported even when they pass, because the numbers are the evidence.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.CBETA
  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake.WorkList
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Local.Manifest, as: LocalManifest
  alias Pramana.Local.Normalizer, as: LocalNormalizer
  alias Pramana.Normalize
  alias Pramana.Normalize.Bilara
  alias Pramana.Normalize.Derge
  alias Pramana.Normalize.Derge.Edition
  alias Pramana.Normalize.IR
  alias Pramana.Normalize.IR.Line
  alias Pramana.Repo

  @switches [limit: :integer]

  @derge_root "raw/derge/UT4CZ5369-200106"

  # Sources whose corpus works are enumerable from the lockfile's file list. bilara packs
  # many works into one file and Derge spreads one work across many, so their file counts
  # answer a different question and are checked by their own reconciliations instead.
  @census_sources ["cbeta"]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    texts = Repo.all(from t in Text, order_by: t.work_id) |> maybe_limit(opts[:limit])

    if texts == [], do: Mix.raise("nothing baked yet — run `mix pramana.bake_all` first")

    started = System.monotonic_time(:millisecond)

    totals =
      texts
      |> Enum.reduce(empty_totals(), &check_text/2)
      |> reconcile_derge(texts, opts[:limit])
      |> census_check(texts, opts[:limit])

    report(length(texts), totals, System.monotonic_time(:millisecond) - started)
  end

  # The per-text checks cannot ask whether the walk dropped anything the edition prints:
  # a Derge volume holds dozens of works and one work holds parts of many volumes, so the
  # question only has an answer for the edition as a whole. A `--limit` run has not seen
  # the whole edition and must not claim to have checked it.
  defp reconcile_derge(totals, _texts, limit) when not is_nil(limit), do: totals

  defp reconcile_derge(totals, texts, _limit) do
    # The byte census is written for the Kangyur's TEI, where an independent counter can
    # walk `<text>` without knowing anything about folios. The Tengyur's plain text has no
    # such envelope — its markup IS its text — so it is checked by the per-work
    # addressability check above and by `mix pramana.verify`, not here.
    if Enum.any?(texts, &(&1.source_id == "derge")) do
      {:ok, volumes} = Edition.volumes_at(@derge_root)
      {:ok, reconciliation} = Edition.reconcile(volumes)

      unexplained =
        for %{dropped: dropped, allowed: allowed} = v <- reconciliation, dropped != allowed do
          {"derge volume #{v.volume}", :bytes_dropped, v.source_bytes, v.walked_bytes}
        end

      %{totals | derge: reconciliation, bad: totals.bad ++ unexplained}
    else
      totals
    end
  end

  # Check 4: every acquired FILE reached the corpus.
  #
  # The per-text checks above all start from a text row and ask whether it is complete.
  # None of them can see a work that never became a row, or one that became a row and
  # then had half of itself overwritten by its own second volume — from inside that row,
  # both look perfect. Six CBETA X works were in exactly that state and passed
  # `mix pramana.verify` over 3,701 texts: the text re-derived byte-identically from the
  # one file it recorded, because the file it recorded was the only half it kept.
  #
  # The count that found it was taken from the SOURCE, before any parsing: 1,236 files
  # on disk against 1,230 works loaded. That is this check, and it is the general form —
  # it will fail the same way for the next source whose works do not map one-to-one onto
  # files, which is most of them.
  #
  # A `--limit` run has deliberately not loaded the whole corpus and cannot ask this.
  defp census_check(totals, _texts, limit) when not is_nil(limit), do: totals

  defp census_check(totals, texts, _limit) do
    baked =
      texts
      |> Enum.filter(&(&1.source_id in @census_sources))
      |> Enum.group_by(& &1.source_id)

    census =
      for {source_id, source_texts} <- baked do
        census = WorkList.census(source_id, nil)
        {source_id, census, length(source_texts)}
      end

    bad =
      for {source_id, census, loaded} <- census, census.works != loaded do
        {source_id, :work_missing, census.works, loaded}
      end

    %{totals | census: census, bad: totals.bad ++ bad}
  end

  defp maybe_limit(texts, nil), do: texts
  defp maybe_limit(texts, n), do: Enum.take(texts, n)

  defp empty_totals do
    %{
      lb: 0,
      foreign_lb: 0,
      ir_lines: 0,
      segments: 0,
      blank: 0,
      g_raw: 0,
      ir_gaiji: 0,
      meta_gaiji: 0,
      derge: [],
      census: [],
      bad: []
    }
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

  # A Derge work has no `<lb/>` and no gaiji: its anchor is a folio and a line milestone,
  # and it can run across thirteen volumes. The per-text question is the same one as
  # everywhere else — did every line with printed content get an addressable segment —
  # and the question this cannot answer per text, whether the walk dropped anything the
  # edition prints, is answered for the whole edition by `reconcile_derge/3` above.
  defp check_text(%{source_id: "derge-tengyur"} = text, totals),
    do: check_derge(text, totals, Pramana.Normalize.DergeTengyur)

  defp check_text(%{source_id: "derge"} = text, totals),
    do: check_derge(text, totals, Pramana.Normalize.Derge)

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
    # EVERY volume the work occupies, not one. Six X works run across two volume files,
    # and counting one file's `<lb/>` against a two-file text would report thousands of
    # lost lines for a text that is intact — or, before the bake assembled them, a clean
    # pass over a text that had lost half of itself.
    parts =
      for volume <- volumes(text) do
        xml = File.read!(raw_path(text, volume))
        {:ok, ir} = renormalize(text, xml, volume)
        {xml, ir}
      end

    ir = parts |> Enum.map(&elem(&1, 1)) |> IR.concat()

    bodies = Enum.map(parts, fn {xml, _ir} -> body_region(xml) end)
    lb = bodies |> Enum.map(&count(&1, "<lb ")) |> Enum.sum()
    g_raw = bodies |> Enum.map(&count(&1, "<g ")) |> Enum.sum()

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

    # Every `<lb/>` in the raw body is accounted for: it became a line, or it belongs to
    # another edition's lineation and was deliberately skipped. An X file carries its own
    # `ed="X"` numbering beside the earlier 卍續藏經 reprint's `ed="R055"`, so a raw count
    # compared against lines alone reports every X text as having lost about half of
    # itself — which is what this check did for 1,228 texts until `foreign_lb` was
    # carried out of the normalizer.
    accounted = length(ir.lines) + ir.foreign_lb

    bad =
      [
        lb != accounted && {text.work_id, :lb_lost, lb, accounted},
        printed != segments && {text.work_id, :line_unaddressable, printed, segments},
        stranded > 0 && {text.work_id, :gaiji_stranded, stranded, 0}
      ]
      |> Enum.filter(& &1)

    %{
      totals
      | lb: totals.lb + lb,
        foreign_lb: totals.foreign_lb + ir.foreign_lb,
        ir_lines: totals.ir_lines + length(ir.lines),
        segments: totals.segments + segments,
        blank: totals.blank + blank,
        g_raw: totals.g_raw + g_raw,
        ir_gaiji: totals.ir_gaiji + ir_gaiji,
        meta_gaiji: totals.meta_gaiji + meta_gaiji,
        bad: totals.bad ++ bad
    }
  end

  defp rederive_derge(text, normalizer) do
    text.meta["source_file"]
    |> String.split(" ", trim: true)
    |> Enum.map(fn path ->
      source = File.read!(path)
      {volume_of(path, source, normalizer), source}
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Edition.reproduce(text.work_id, normalizer: normalizer)
  end

  # The Kangyur's TEI names its volume on its title page; the Tengyur's plain text names
  # it in the filename, because that format has no header to put it in. Both are handed
  # the bytes already read — a work spans up to thirteen volumes and this runs once per
  # text, so reading each file twice is thousands of redundant reads of 2.5 MB.
  defp volume_of(path, _source, Pramana.Normalize.DergeTengyur) do
    [_, number] = Regex.run(~r/^(\d+)_/, Path.basename(path))
    String.to_integer(number)
  end

  defp volume_of(_path, source, _normalizer) do
    {:ok, volume} = Derge.volume_number(source)
    volume
  end

  defp check_derge(text, totals, normalizer) do
    {:ok, ir} = rederive_derge(text, normalizer)

    segments = Repo.one(from s in Segment, where: s.text_id == ^text.id, select: count(s.id))
    blank = Enum.count(ir.lines, &blank?/1)
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

  # A line may be dropped only when NOTHING was printed on it. Text, an interlinear
  # note, a variant reading and a rare character are all printed content. The definition
  # lives on the struct, so this check and the segmenter cannot disagree about it —
  # they did, and the gap was one line with no URN.
  defp blank?(line), do: Line.blank?(line)

  # `<back>` reproduces body text in its apparatus lemmas, so counting the whole file
  # would double-count both <lb/> and <g/>.
  defp body_region(xml) do
    case String.split(xml, "<body>", parts: 2) do
      [_, rest] -> rest |> String.split("</body>", parts: 2) |> hd()
      _ -> ""
    end
  end

  defp count(haystack, needle), do: length(String.split(haystack, needle)) - 1

  defp raw_path(text, volume) do
    number = String.replace_prefix(text.work_id, text.witness_id, "")

    Path.join([
      Lockfile.raw_dir(),
      text.source_id,
      CBETA.work_path(text.witness_id, volume || 0, number)
    ])
  end

  # An assembled work records its volumes in meta; `text.volume` reads "81-82" there and
  # is a label for people, not a number to parse.
  defp volumes(%{meta: %{"volumes" => volumes}}) when is_list(volumes) and volumes != [],
    do: volumes

  defp volumes(text), do: [text.volume && String.to_integer(text.volume)]

  defp renormalize(text, xml, volume) do
    number = String.replace_prefix(text.work_id, text.witness_id, "")

    Normalize.CBETA.normalize(xml,
      work_id: text.work_id,
      canon: text.witness_id,
      volume: volume,
      number: number
    )
  end

  defp report(text_count, %{bad: []} = t, elapsed) do
    Mix.shell().info("""

    integrity OK — #{text_count} text(s) in #{Pramana.Elapsed.human(elapsed)} (#{Pramana.Elapsed.rate(text_count, elapsed)} texts/s)

      source anchors:           #{t.lb}   (<lb/> in TEI, page files in a local text)
      IR lines:                 #{t.ir_lines}   (every anchor produced a line)
      another edition's lines:  #{t.foreign_lb}   (skipped, not lost — see Normalize.CBETA)

      lines with printed content: #{t.ir_lines - t.blank}
      segments in the bake:       #{t.segments}   (every one is addressable)
      genuinely blank, skipped:   #{t.blank}

      <g/> in raw body:           #{t.g_raw}
      gaiji on IR lines:          #{t.ir_gaiji}   (repeats collapsed per line)
      gaiji reachable in segments: #{t.meta_gaiji}
      stranded on dropped lines:   0
    #{census_section(t.census)}#{derge_section(t.derge)}
    """)
  end

  defp report(_text_count, t, _elapsed) do
    for {work, kind, expected, actual} <- Enum.take(t.bad, 25) do
      Mix.shell().error("  #{work}: #{kind} — raw #{expected}, bake #{actual}")
    end

    Mix.raise("""
    integrity FAILED for #{length(t.bad)} text(s).

    Content printed in the source edition is missing from the bake. Note that
    `mix pramana.verify` can still pass while this fails: it compares the bake against
    a re-run of the same pipeline, so anything dropped deterministically is dropped on
    both sides. Reproducibility is not fidelity. See docs/CHECKS.md.
    #{census_help(t.bad)}\
    """)
  end

  # `work_missing` has two readings and the data cannot tell them apart, so the message
  # gives both rather than asserting the alarming one. Either way the corpus does not
  # hold what has been acquired, which is the thing worth knowing.
  defp census_help(bad) do
    if Enum.any?(bad, fn {_, kind, _, _} -> kind == :work_missing end) do
      """

      `work_missing` means the lockfile records works the corpus does not hold. Either
      a collection was acquired and never baked — run `mix pramana.bake_all` — or works
      that share a number across volume files overwrote each other, which is the defect
      this check exists for. `Pramana.Bake.WorkList.census/2` names the works that span
      volumes.
      """
    else
      ""
    end
  end

  # Files against works, per source. Equal counts are the normal case and are printed
  # anyway: the number only does its job if it is visible when it is right.
  defp census_section([]), do: ""

  defp census_section(census) do
    rows =
      for {source_id, c, loaded} <- census do
        spanning =
          case c.multi_volume do
            [] ->
              ""

            works ->
              "  (#{length(works)} work(s) span volumes: #{Enum.map_join(works, ", ", & &1.work_id)})"
          end

        "        #{source_id}: #{c.files} file(s) -> #{c.works} work(s) -> #{loaded} loaded#{spanning}"
      end

    """

      Acquired files against works in the corpus, counted from the lockfile:

    #{Enum.join(rows, "\n")}
    """
  end

  defp derge_section([]), do: ""

  defp derge_section(reconciliation) do
    source = Enum.sum(Enum.map(reconciliation, & &1.source_bytes))
    walked = Enum.sum(Enum.map(reconciliation, & &1.walked_bytes))
    dropped = for v <- reconciliation, v.dropped != 0, do: v

    """

      Derge, counted independently of the parser (non-whitespace bytes inside <text>):

        in the edition:  #{source}
        in the bake:     #{walked}
        difference:      #{source - walked}#{Enum.map(dropped, &"\n          volume #{&1.volume}: #{&1.dropped} bytes before its first toh marker, which belong to no work")}\
    """
  end
end
