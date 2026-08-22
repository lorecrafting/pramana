defmodule Mix.Tasks.Pramana.Evals.Derive do
  @shortdoc "Derives gold-set cases from ground truth already in the corpus"

  @moduledoc """
  Generates `evals/gold/*.jsonl` from facts this corpus can already prove.

      mix pramana.evals.derive
      mix pramana.evals.derive --out evals/gold --per-type 40

  ## Why derive rather than write

  A gold set needs expected answers that are **right**, and the only answers this project
  is entitled to assert are ones it can point at a source for. So every case here is built
  from something already verified:

  | case source | ground truth |
  |---|---|
  | translation anchors | a published translator rendered *this* segment |
  | definitional formulae | the canon's own 云何為X / Katamañca X marks the definition |
  | curated parallels | SuttaCentral's hand-made cross-tradition relations |
  | the Taishō division table | the edition's own classification of every work |
  | the corpus's own gaps | we hold no Japanese-composed works, and say so |

  Asking a language model to invent questions and answers would measure agreement with
  that model. Deriving them measures the system against the field's own scholarship.

  ## What derivation cannot give you

  Derived retrieval queries are **not paraphrases**. A query built from a translator's
  English tests whether the pipeline connects that English to the right anchor among
  327,754 chunks — a real test, and a weaker one than a question a human would actually
  type. Each case therefore records how it was made in its `source` field, and the
  scorecard can be read per-source. Hand-written questions belong alongside these, not
  instead of them.

  The output is data and is committed. This task exists so a reader can see exactly how
  the data was produced, and regenerate it after a re-bake.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Translation
  alias Pramana.Corpus.Work
  alias Pramana.Repo

  @switches [out: :string, per_type: :integer, seed: :integer]

  @default_out "evals/gold"
  @default_per_type 40

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    out = Keyword.get(opts, :out, @default_out)
    per_type = Keyword.get(opts, :per_type, @default_per_type)
    # A fixed seed by default: the gold set must be the same every time it is derived,
    # or the number it produces is not comparable with the last one.
    :rand.seed(:exsss, {Keyword.get(opts, :seed, 20_260_816), 0, 0})

    File.mkdir_p!(out)

    files = [
      {"retrieval_translation.jsonl", translation_cases(per_type)},
      {"retrieval_definition.jsonl", definition_cases(per_type)},
      {"citation_guard.jsonl", guard_cases(per_type)},
      {"provenance.jsonl", provenance_cases(per_type)},
      {"topical.jsonl", topical_cases()},
      {"absence.jsonl", absence_cases()}
    ]

    for {name, cases} <- files do
      path = Path.join(out, name)
      File.write!(path, Enum.map_join(cases, "\n", &Jason.encode!/1) <> "\n")
      Mix.shell().info("  #{path}  #{length(cases)} case(s)")
    end

    total = files |> Enum.map(fn {_, c} -> length(c) end) |> Enum.sum()
    Mix.shell().info("\nderived #{total} case(s) into #{out}")
  end

  # ---- retrieval, from translation anchors ----
  #
  # A published English rendering of one segment, asked as the query; the segment's own
  # anchor is the answer. Cross-lingual by construction: the query is English and the
  # expected citation is Pāli.
  defp translation_cases(n) do
    # Sampled per tradition rather than from the pool as a whole. The Pāli renderings
    # outnumber the Tibetan seven to one, so a flat sample would produce a Tibetan case
    # or two and a per-tradition rate computed from almost nothing — and the
    # per-tradition rate is what this benchmark is FOR.
    traditions = renderable_traditions()
    per = max(div(n, max(length(traditions), 1)), 1)

    traditions
    |> Enum.flat_map(fn {source, tradition} ->
      source |> renderings(per) |> Enum.map(&Map.put(&1, :tradition, tradition))
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {row, i} ->
      urns = Enum.uniq(identical_anchors(row.urn) ++ identically_rendered(row.text))

      %{
        id: "tr-#{pad(i)}",
        type: "retrieval",
        query: String.trim(row.text),
        expect_urns: urns,
        k: 10,
        tradition: row.tradition,
        source:
          "translation anchor: #{row.translator} rendered this passage. The query is " <>
            "that rendering; the expected citation is the source it renders.",
        note:
          "cross-lingual: English query, #{row.tradition} citation" <>
            if(length(urns) > 1,
              do: "; formulaic — #{length(urns)} identical locations",
              else: ""
            )
      }
    end)
  end

  # Which sources have published human English attached, and what to call the tradition.
  defp renderable_traditions do
    present =
      Repo.all(
        from t in Translation,
          join: txt in Text,
          on: txt.work_id == t.work_id,
          where: t.lang == "en" and t.tier == "t0",
          select: txt.source_id,
          distinct: true
      )

    for source <- Enum.sort(present),
        tradition = tradition_of(source),
        not is_nil(tradition),
        do: {source, tradition}
  end

  defp tradition_of("sc"), do: "pali"
  defp tradition_of("derge"), do: "tibetan"
  defp tradition_of("cbeta"), do: "chinese"
  defp tradition_of(_source), do: nil

  # A rendering is usable as a case when its anchor RESOLVES — which is the only property
  # that matters and the only one worth testing for. 84000 anchors a folio of English to
  # the range of Tibetan lines it covers, so joining `anchor_urn` to `segments.urn` by
  # equality (as this did) finds none of the 30,653 of them and Tibetan silently has no
  # cases at all. The rate would then be reported as "not measured" rather than measured
  # and bad, which is the more dangerous of the two.
  defp renderings(source, n) do
    Repo.all(
      from t in Translation,
        join: txt in Text,
        on: txt.work_id == t.work_id,
        where:
          t.lang == "en" and t.tier == "t0" and txt.source_id == ^source and
            fragment("length(?)", t.text) > 60 and
            fragment("length(?)", t.text) < 220,
        select: %{urn: t.anchor_urn, text: t.text, translator: t.translator_id},
        order_by: fragment("md5(?)", t.anchor_urn),
        limit: ^(n * 3)
    )
    # A work held in two witnesses joins twice; the rendering is still one rendering.
    |> Enum.uniq_by(& &1.urn)
    |> Enum.filter(&substantial?/1)
    |> Enum.take(n)
  end

  # The anchor has to RESOLVE, and to something worth asking about. This is also the only
  # check the range-anchored renderings need: a folio anchor either names real lines or it
  # does not, and `Pramana.Corpus` is the authority either way.
  defp substantial?(%{urn: urn}) do
    case Pramana.Corpus.resolve(urn) do
      {:ok, %{content: content}} -> byte_size(content) > 40
      _ -> false
    end
  end

  # EVERY anchor whose text is byte-identical, not just the one the translation happens
  # to hang off.
  #
  # This literature is formulaic by design — it was composed to be memorised, so stock
  # passages recur verbatim across dozens of suttas. `sn12.1@3.1` appears 15 times. A
  # query quoting that sentence cannot distinguish the copies, and no retriever should be
  # marked wrong for returning one of them: the question "where does the canon say this"
  # genuinely has 15 correct answers.
  #
  # Scoring against a single arbitrary copy would measure luck. Left unfixed it cost
  # roughly a third of the Pāli cases and would have been published as a retrieval
  # failure.
  defp identical_anchors(urn) do
    Repo.all(
      from s in Segment,
        join: origin in Segment,
        on: origin.content_sha256 == s.content_sha256,
        where: origin.urn == ^urn,
        select: s.urn,
        order_by: s.urn,
        limit: 50
    )
    |> case do
      [] -> [urn]
      urns -> urns
    end
  end

  # And every anchor carrying the SAME English, which is a different equivalence class
  # from the same source text.
  #
  # 84000's shortest folio renderings are openings and colophons — "Homage to all buddhas
  # and bodhisattvas. Thus did I hear at one time." is the published English of 102
  # separate anchors — and the Tibetan under them is NOT byte-identical, because each
  # names its own sūtra. So `identical_anchors/1` sees one correct answer where the query
  # cannot possibly distinguish 102, and the case measures which copy the retriever
  # happened to rank first. That is the mistake rule 18 was written about, arriving from
  # the other side: there the source repeated, here the translation does.
  defp identically_rendered(text) do
    Repo.all(
      from t in Translation,
        where: t.lang == "en" and t.text == ^text,
        select: t.anchor_urn,
        limit: 200
    )
  end

  # ---- topical questions, hand-written and term-verified ----
  #
  # The questions come from `priv/evals/topical_questions.exs` because a person has to
  # write them: the whole point is to measure what someone actually types, and a derived
  # query is by construction not that. What is NOT hand-written is whether a question is
  # answerable — each names a term in the canon's own vocabulary, and that term is checked
  # against the corpus here.
  #
  # A term is rejected on either side of a range. Absent, and the question cannot be
  # answered by this bake. Too common, and accepting any passage containing it measures
  # nothing: 涅槃 occurs in 49,397 segments, so a case built on it would pass on almost
  # any retrieval at all. Rejected terms are reported, never silently dropped.
  @max_term_segments 2_500

  defp topical_cases do
    questions =
      :pramana
      |> Application.app_dir("priv/evals/topical_questions.exs")
      |> Code.eval_file()
      |> elem(0)

    groups = [
      {questions[:pali], "pali", "pli", "English question, Pāli passage"},
      {questions[:chinese], "chinese", "lzh", "English question, Chinese passage"},
      {questions[:chinese_native], "chinese-native", "lzh", "Chinese question, Chinese passage"},
      {questions[:tibetan], "tibetan", "bo", "English question, Tibetan passage"}
    ]

    {cases, rejected} =
      for {list, tradition, lang, description} <- groups,
          {question, term, topic} <- list,
          reduce: {[], []} do
        {kept, rejected} ->
          case classify_term(term, lang) do
            {:ok, count} ->
              {[topical_case(question, term, topic, tradition, description, count) | kept],
               rejected}

            {:rejected, reason, count} ->
              {kept, [{term, reason, count} | rejected]}
          end
      end

    report_rejected(rejected)

    cases
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {kase, i} -> %{kase | id: "top-#{pad(i)}"} end)
  end

  defp classify_term(term, lang) do
    source = source_for_lang(lang)

    count =
      Repo.aggregate(
        from(s in Segment,
          join: t in Text,
          on: t.id == s.text_id,
          where: t.source_id == ^source and like(s.content, ^"%#{term}%")
        ),
        :count
      )

    cond do
      count == 0 -> {:rejected, :absent_from_corpus, count}
      count > @max_term_segments -> {:rejected, :too_common_to_measure, count}
      true -> {:ok, count}
    end
  end

  defp source_for_lang("pli"), do: "sc"
  defp source_for_lang("bo"), do: "derge"
  defp source_for_lang(_lzh), do: "cbeta"

  defp topical_case(question, term, topic, tradition, description, count) do
    %{
      id: nil,
      type: "topical",
      query: question,
      expect_contains: [term],
      k: 10,
      tradition: tradition,
      topic: topic,
      search_opts: %{},
      source:
        "hand-written question; ground truth is the canon's own term #{term}, which " <>
          "occurs in #{count} segment(s). Correct means: a returned passage contains it.",
      note: description
    }
  end

  defp report_rejected([]), do: :ok

  defp report_rejected(rejected) do
    Mix.shell().info("\n  topical terms rejected (not committed as cases):")

    for {term, reason, count} <- Enum.reverse(rejected) do
      Mix.shell().info("    #{term}: #{reason} (#{count} segments)")
    end
  end

  # ---- retrieval, from the canon's own definitional formulae ----
  #
  # The formula locates the passage deterministically, so the expected answer is not a
  # judgement. The QUERY is the term alone — a much harder ask than the formula, and
  # closer to what someone would type.
  defp definition_cases(n) do
    Repo.all(
      from s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where:
          t.source_id == "cbeta" and like(s.content, "%云何為%") and
            fragment("length(?)", s.content) > 12,
        select: %{urn: s.urn, content: s.content},
        order_by: fragment("md5(?)", s.urn),
        limit: ^(n * 3)
    )
    |> Enum.flat_map(&definition_case/1)
    |> Enum.uniq_by(& &1.query)
    |> Enum.take(n)
    |> Enum.with_index(1)
    |> Enum.map(fn {kase, i} -> %{kase | id: "def-#{pad(i)}"} end)
  end

  defp definition_case(%{urn: urn, content: content}) do
    case Regex.run(~r/云何為([^\s,，。？?]{2,6})/u, content) do
      [_, term] ->
        [
          %{
            id: nil,
            type: "retrieval",
            query: "云何為#{term}",
            expect_urns: [urn],
            k: 10,
            tradition: "chinese",
            source:
              "definitional formula: the canon marks its own definition with 云何為, so " <>
                "the location of this definition is not a judgement call.",
            note: "term: #{term}"
          }
        ]

      _ ->
        []
    end
  end

  # ---- the citation guard, both directions ----
  #
  # A harness that only checks quotations that ARE present measures nothing: a guard
  # returning :ok unconditionally would score 100%. Every accept case therefore has a
  # matching reject case built by altering exactly one character.
  defp guard_cases(n) do
    segments =
      Repo.all(
        from s in Segment,
          where: fragment("length(?)", s.content) > 20 and fragment("length(?)", s.content) < 200,
          select: %{urn: s.urn, content: s.content},
          order_by: fragment("md5(?)", s.urn),
          limit: ^n
      )

    accepts =
      segments
      |> Enum.with_index(1)
      |> Enum.map(fn {row, i} ->
        %{
          id: "quote-ok-#{pad(i)}",
          type: "quote_verify",
          quote: String.slice(row.content, 0, 20),
          expect_urns: [row.urn],
          source: "the passage itself: this text is at this URN in the current bake.",
          note: "the guard must confirm a quotation that is really there"
        }
      end)

    rejects =
      segments
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {row, i} -> reject_case(row, i) end)

    fabricated = [
      %{
        id: "quote-fab-001",
        type: "quote_reject",
        urn: "pramana:cbeta.T:T9999_001@p0001a01",
        quote: "如是我聞",
        expect_urns: [],
        adversarial: true,
        source: "a URN that addresses nothing — well-formed and fabricated.",
        note: "the most damaging failure: a plausible citation to a passage that does not exist"
      }
    ]

    accepts ++ rejects ++ fabricated
  end

  # One character changed, everything else identical. This is the subtle misquotation the
  # guard exists for — a real passage, a real citation, altered words.
  defp reject_case(%{urn: urn, content: content}, i) do
    quoted = String.slice(content, 0, 20)

    case alter_one_character(quoted) do
      nil ->
        []

      altered ->
        [
          %{
            id: "quote-alt-#{pad(i)}",
            type: "quote_reject",
            urn: urn,
            quote: altered,
            expect_urns: [],
            adversarial: true,
            source: "the passage itself, with exactly one character changed.",
            note: "a real passage, a real citation, altered text"
          }
        ]
    end
  end

  @doc false
  # Returns nil rather than an unaltered string. A "reject" case whose text was never
  # actually changed is not a weak test, it is a WRONG one: the guard verifies the quote —
  # correctly, because it really is in the passage — and the harness scores the guard as
  # having failed. Found at n=301, invisible at n=41: `substitute/1` mapped every Han
  # character to 空, so a passage whose midpoint was already 空 was "altered" into itself.
  def alter_one_character(text) do
    graphemes = String.graphemes(text)
    index = div(length(graphemes), 2)

    with char when not is_nil(char) <- Enum.at(graphemes, index),
         replacement when replacement != char <- substitute(char) do
      graphemes |> List.replace_at(index, replacement) |> Enum.join()
    else
      _ -> nil
    end
  end

  # A substitution that stays in the same script, so the alteration is a plausible
  # misquotation rather than an obvious corruption. The second choice exists only so the
  # result is guaranteed to DIFFER from the character being replaced.
  defp substitute("空"), do: "無"
  defp substitute("x"), do: "y"

  defp substitute(char) do
    if String.match?(char, ~r/\p{Han}/u), do: "空", else: "x"
  end

  # ---- provenance labelling ----
  #
  # The Taishō's division table classifies every work; a text's origin and role are
  # therefore catalogue facts, not opinions.
  defp provenance_cases(n) do
    Repo.all(
      from w in Work,
        join: t in Text,
        on: t.work_id == w.id,
        join: s in Segment,
        on: s.text_id == t.id,
        where: not is_nil(w.composition_origin) and s.ordinal == 0,
        select: %{
          urn: s.urn,
          origin: w.composition_origin,
          role: w.text_role,
          division: w.division,
          confidence: w.attribution_confidence
        },
        order_by: fragment("md5(?)", s.urn),
        limit: ^n
    )
    |> Enum.with_index(1)
    |> Enum.map(fn {row, i} ->
      %{
        id: "prov-#{pad(i)}",
        type: "provenance",
        expect_urns: [row.urn],
        expect_provenance:
          %{"composition_origin" => row.origin, "text_role" => row.role}
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new(),
        adversarial: row.confidence == "apocryphal",
        tradition: if(row.origin == "indic", do: "chinese", else: row.origin),
        source: "Taishō division table: #{row.division || "unclassified"}.",
        note: "confidence: #{row.confidence || "unrecorded"}"
      }
    end)
  end

  # ---- absence ----
  #
  # The questions this project most needs to answer correctly are the ones where the
  # honest answer is "we do not hold that". These are hand-written because the corpus
  # cannot derive its own gaps — knowing what is missing is knowledge from outside it.
  defp absence_cases do
    [
      %{
        id: "abs-001",
        type: "absence",
        query: "本門戒體",
        search_opts: %{"origin" => ["japanese"]},
        expect_empty: true,
        adversarial: true,
        source:
          "Taishō 56–84 is Japanese-composed and CBETA excludes it, so this corpus " <>
            "holds no Japanese-composed work (#14).",
        note:
          "a doctrine discussed in Japanese Tendai/Nichiren material. The correct " <>
            "answer is nothing at all — not a Chinese text that mentions similar words."
      },
      %{
        id: "abs-002",
        type: "absence",
        query: "唱題",
        search_opts: %{"origin" => ["japanese"]},
        expect_empty: true,
        adversarial: true,
        source: "as abs-001: no Japanese-composed works are held.",
        note: "Nichiren practice of chanting the daimoku"
      },
      %{
        id: "abs-003",
        type: "absence",
        query: "如是我聞",
        search_opts: %{"origin" => ["japanese"]},
        expect_empty: true,
        adversarial: true,
        source: "as abs-001.",
        note:
          "the opening formula of nearly every sūtra, filtered to Japanese-composed " <>
            "works. A filter that silently does nothing returns thousands of hits here."
      },
      %{
        id: "abs-004",
        type: "absence",
        query: "quantum entanglement in the Pali canon",
        forbid_works: [],
        expect_empty: false,
        adversarial: true,
        source: "no ground truth exists; the corpus contains nothing on this.",
        note:
          "a question with no good answer. Recorded to watch what gets returned; the " <>
            "system is not yet expected to refuse, and pretending otherwise would be " <>
            "the kind of claim this harness exists to prevent."
      }
    ]
  end

  defp pad(i), do: String.pad_leading(Integer.to_string(i), 3, "0")
end
