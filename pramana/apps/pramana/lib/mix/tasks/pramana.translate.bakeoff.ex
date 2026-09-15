defmodule Mix.Tasks.Pramana.Translate.Bakeoff do
  @shortdoc "Builds a blinded side-by-side sheet for ranking translations"

  @moduledoc """
  A blinded comparison of renderings, for choosing a translation model by reading rather
  than by trusting a metric.

      mix pramana.translate.bakeoff --anchors 40
      mix pramana.translate.bakeoff --anchors 40 --work T0099 --out /tmp/bakeoff
      mix pramana.translate.bakeoff --anchors 30 --repeats 6

  Writes two files: a **sheet** with the source and its candidate renderings labelled
  A/B/C, and a **key** naming which is which. Rank the sheet, then open the key.

  ## Why blinded, and why nothing is scored against a human

  The obvious design is to score a model against a good human translator and call the
  difference error. **This project already refuses that move one level down** — where
  translators disagree, `docs/TRANSLATION.md` returns the disagreement with its
  attribution rather than picking a winner, because a translation is an argument about a
  passage. Making one translator the definition of correct contradicts that.

  So the human is **one anonymous candidate among the others**. If a model outranks him
  the sheet can say so; if he outranks everything, that is worth knowing too. What is
  being measured is translation quality, not similarity to one person.

  Labels are shuffled **per row**, not once for the sheet, so a ranker cannot learn that
  "B is always the model" halfway down and start scoring the label.

  ## The ranker's own reliability is measured, because n is small

  A handful of rows are **repeated later in the sheet under fresh labels**. Ranking them
  the same way both times is what distinguishes *this model is better* from *I prefer this
  register today* — and with one ranker, that distinction is the whole question. The key
  reports the repeats so consistency can be counted rather than assumed.

  This costs nothing and is the difference between a decision and a preference.

  ## What this does NOT decide

  The **index** tier of `docs/PLAN.md` § E1 — generated English that is matched against and
  never read — is decided by `mix pramana.recall --renderings`, automatically, with no
  human and no reference translation. Fidelity only governs the **reader** tier. Do not use
  a ranking from this sheet to choose the model for the index tier; they are different
  questions and the automatic one is the cheaper and better-posed of the two.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Translation
  alias Pramana.Repo

  @switches [
    anchors: :integer,
    work: :string,
    out: :string,
    repeats: :integer,
    seed: :integer,
    lang: :string,
    min_chars: :integer,
    reveal: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    count = Keyword.get(opts, :anchors, 40)
    repeats = Keyword.get(opts, :repeats, 5)
    out = Keyword.get(opts, :out, "evals/experiments/bakeoff")
    seed = Keyword.get(opts, :seed, 42)
    lang = Keyword.get(opts, :lang, "en")

    :rand.seed(:exsss, {seed, seed, seed})

    rows = candidates(count, opts[:work], lang, Keyword.get(opts, :min_chars, 80))

    if rows == [] do
      Mix.raise("""
      no anchors with two or more renderings#{if opts[:work], do: " in #{opts[:work]}", else: ""}.

      A bake-off needs at least two candidates per passage. Today that means an anchor
      with two human translators, or a generated arm loaded into the pool alongside one.
      """)
    end

    sheet_rows = with_repeats(rows, repeats)
    File.mkdir_p!(Path.dirname(out))
    File.write!(out <> ".md", sheet(sheet_rows, lang))
    File.write!(out <> ".key.json", Jason.encode!(key(sheet_rows), pretty: true) <> "\n")

    if opts[:reveal], do: File.write!(out <> ".revealed.md", revealed(rows, lang))

    report(rows, sheet_rows, out, opts[:reveal])
  end

  # An anchor is usable when two or more translators rendered it. Ordered by a hash of the
  # anchor rather than at random, so the same seed and the same corpus give the same sheet
  # — a comparison somebody has half-finished should not reshuffle under them.
  # A MINIMUM LENGTH, because the first run produced a sheet of Therīgāthā titles — "An
  # Unnamed Nun (2nd)" against "Verses of a Certain Unknown Elder" — which is a real
  # difference and tells you nothing about how a model handles a passage of doctrine.
  defp candidates(count, work, lang, min_chars) do
    anchors =
      from(t in Translation,
        where: t.lang == ^lang and fragment("length(?) >= ?", t.text, ^min_chars),
        group_by: t.anchor_urn,
        having: count(fragment("distinct ?", t.translator_id)) >= 2,
        order_by: [asc: fragment("abs(hashtext(?))", t.anchor_urn)],
        # Over-fetched, because deduplicating by source text below removes stock formulae
        # and a sheet asked for forty passages should contain forty.
        limit: ^(count * 4),
        select: t.anchor_urn
      )
      |> then(fn q -> if work, do: where(q, [t], t.work_id == ^work), else: q end)
      |> Repo.all()

    renderings =
      from(t in Translation,
        where: t.anchor_urn in ^anchors and t.lang == ^lang,
        order_by: [asc: t.anchor_urn, asc: t.translator_id],
        select: %{
          anchor_urn: t.anchor_urn,
          translator_id: t.translator_id,
          method: t.method,
          text: t.text
        }
      )
      |> Repo.all()
      |> Enum.group_by(& &1.anchor_urn)

    sources = source_text(anchors)
    chunk_level = chunk_level_candidates(anchors)

    anchors
    |> Enum.map(fn urn ->
      exact = Map.get(renderings, urn, [])
      seen = MapSet.new(exact, & &1.translator_id)

      covering =
        chunk_level
        |> Map.get(urn, [])
        |> Enum.reject(&MapSet.member?(seen, &1.translator_id))

      %{
        anchor_urn: urn,
        source: Map.get(sources, urn),
        candidates: exact ++ covering
      }
    end)
    |> Enum.reject(&(length(&1.candidates) < 2))
    # DEDUPLICATED BY SOURCE TEXT, not by anchor. The canon is full of stock formulae —
    # `ekaṁ samayaṁ bhagavā sāvatthiyaṁ viharati…` opens hundreds of suttas at hundreds of
    # distinct anchors — and the first sheet this produced had the same sentence at
    # passages 1 and 2. Ranking forty rows of "at one time the Buddha was staying near
    # Sāvatthī" measures a house style and nothing about how a model handles doctrine.
    # Falling back to the ANCHOR when the source is missing. `row.source && trim` returns
    # nil for every source-less row, and `uniq_by` treats one nil like another — so a
    # sheet of 205 chunk-anchored passages silently became a sheet of 1. A deduplication
    # key that collapses on absence is rule 71's shape in a different place.
    |> Enum.uniq_by(fn row -> (row.source && String.trim(row.source)) || row.anchor_urn end)
    |> Enum.take(count)
  end

  # The passage being translated, so a ranker can check a rendering against it rather than
  # against their taste. A sheet without the source measures fluency.
  # A rendering may be anchored to a SEGMENT or to a CHUNK, and both are addressed by URN.
  # Looking in only one of them left every chunk-anchored passage without its source —
  # which is both a sheet that cannot be checked against the Chinese and, through the
  # deduplication above, a sheet that was almost entirely thrown away.
  defp source_text(anchors) do
    segments =
      from(s in Segment, where: s.urn in ^anchors, select: {s.urn, s.content}) |> Repo.all()

    chunks = from(c in Chunk, where: c.urn in ^anchors, select: {c.urn, c.content}) |> Repo.all()

    Map.new(segments ++ chunks)
  end

  # THE HUMAN CANDIDATE, WHICH LIVES AT A DIFFERENT GRAIN.
  #
  # A generated rendering is anchored to the chunk it was given; Patton's is anchored to
  # the Taishō line it renders. They are renderings of the same passage and they never
  # share an `anchor_urn`, so grouping by anchor alone produces a sheet of model arms with
  # no human in it — and the human is what bounds the arms from above and calibrates the
  # ranker.
  #
  # `chunk_vectors` already holds each translator's English assembled per chunk, in
  # reading order since rule 71, so the alignment does not have to be recomputed here.
  defp chunk_level_candidates(anchors) do
    from(v in ChunkVector,
      join: c in Chunk,
      on: c.id == v.chunk_id,
      where: c.urn in ^anchors and v.kind == "translation",
      select: %{anchor_urn: c.urn, translator_id: v.translator_id, text: v.content}
    )
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :method, "human"))
    |> Enum.group_by(& &1.anchor_urn)
  end

  # REPEATS ARE SEPARATED, not adjacent. A repeat next to its original is a memory test;
  # placed a dozen rows later under fresh labels it is a consistency test, which is the
  # thing worth knowing.
  defp with_repeats(rows, 0), do: Enum.map(rows, &{shuffle(&1), false})

  defp with_repeats(rows, repeats) do
    # SHUFFLED PER APPEARANCE, so a repeated passage gets fresh labels — the point of a
    # repeat is to re-ask the question, not to ask whether the ranker remembers a letter.
    repeated =
      rows |> Enum.take_random(min(repeats, length(rows))) |> Enum.map(&{shuffle(&1), true})

    originals = Enum.map(rows, &{shuffle(&1), false})

    (originals ++ repeated)
    |> Enum.with_index()
    |> Enum.sort_by(fn {{_row, repeat?}, i} -> if repeat?, do: i + length(rows), else: i end)
    |> Enum.map(&elem(&1, 0))
  end

  # SHUFFLE ONCE AND CARRY IT. The first version shuffled inside the sheet renderer and
  # built the key from the unshuffled list, so the key named the candidates in
  # translator-id order while the sheet showed them in another — the labels a ranker wrote
  # against mapped to nothing, and the comment above the key claimed the two could not
  # disagree. Discovered by reading the generated files rather than the code.
  defp shuffle(row), do: %{row | candidates: Enum.shuffle(row.candidates)}

  defp sheet(rows, lang) do
    header = """
    # Translation bake-off — blinded

    Rank the candidates under each passage. **The labels are shuffled per passage**, so
    A is not the same source twice, and one of the candidates may be a published human
    translation. Read the source; do not rank on fluency alone.

    A few passages appear **twice**, under different labels. That is deliberate and it
    measures nothing about you that is not worth knowing: ranking them consistently is
    what makes a single ranker's verdict a decision rather than a preference.

    Language: #{lang}. Write your ranking under each passage, best first, e.g. `B > A > C`.

    ---

    """

    rows
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {{row, _repeat?}, i} -> passage(row, i) end)
    |> then(&(header <> &1))
  end

  defp passage(row, i) do
    candidates =
      row.candidates
      |> Enum.with_index()
      |> Enum.map_join("\n\n", fn {c, n} ->
        "**#{label(n)}.** #{String.trim(c.text)}"
      end)

    """
    ## #{i}

    > #{String.trim(row.source || "(source text not held for this anchor)")}

    #{candidates}

    _Ranking:_ ______________________

    ---
    """
  end

  defp label(n), do: <<?A + n>>

  # THE SAME PASSAGES WITH THE NAMES ON, for reading rather than for ranking.
  #
  # Deliberately a separate file and deliberately not the default. Knowing which rendering
  # came from which model is exactly the information that makes a ranking worthless — you
  # cannot un-know that B is the one you are hoping wins, and this project's whole posture
  # is that a comparison has to survive the person running it. So: rank the sheet first,
  # then read this.
  #
  # No repeats here, because a repeat exists to measure whether a ranker agrees with
  # themselves under fresh labels, and there are no labels to be fresh.
  defp revealed(rows, lang) do
    header = """
    # Bake-off, revealed — #{lang}

    **Read this AFTER ranking `.md`, not before.** These are the same passages with the
    translator named beside each rendering. A `t0`/human rendering is a published human
    translation; a `t1`/llm one is generated and is not citable as source (invariant #8).

    ---

    """

    rows
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {row, i} ->
      candidates =
        row.candidates
        |> Enum.sort_by(& &1.translator_id)
        |> Enum.map_join("\n\n", fn c ->
          "**#{c.translator_id}** (#{c.method}) — #{String.trim(c.text)}"
        end)

      """
      ## #{i} · `#{row.anchor_urn}`

      > #{String.trim(row.source || "(source text not held for this anchor)")}

      #{candidates}

      ---
      """
    end)
    |> then(&(header <> &1))
  end

  # Built from the SAME shuffled list the sheet rendered, so label position is the key's
  # ordering and the two cannot disagree. `label` is stored explicitly rather than left
  # implicit in the array order, because an implicit contract between two functions is
  # exactly what went wrong the first time.
  defp key(rows) do
    rows
    |> Enum.with_index(1)
    |> Enum.map(fn {{row, repeat?}, i} ->
      %{
        passage: i,
        anchor_urn: row.anchor_urn,
        repeat_of_earlier_passage: repeat?,
        candidates:
          row.candidates
          |> Enum.with_index()
          |> Enum.map(fn {c, n} ->
            %{label: label(n), translator_id: c.translator_id, method: c.method}
          end)
      }
    end)
  end

  defp report(rows, sheet_rows, out, reveal?) do
    repeats = Enum.count(sheet_rows, fn {_row, repeat?} -> repeat? end)

    translators =
      rows
      |> Enum.flat_map(& &1.candidates)
      |> Enum.frequencies_by(& &1.translator_id)

    Mix.shell().info("""

    bake-off sheet written
      passages:        #{length(rows)} (#{repeats} repeated for consistency)
      rows in sheet:   #{length(sheet_rows)}
      candidates by translator: #{inspect(translators)}

      sheet  #{out}.md
      key    #{out}.key.json     <- do not open until the sheet is ranked
    #{if reveal?, do: "  read   #{out}.revealed.md   <- named, for reading; ranking after this is not blind", else: ""}

    The index tier is NOT decided here — `mix pramana.recall --renderings` decides that
    automatically and without a reference translation. This sheet is for the reader tier.
    """)
  end
end
