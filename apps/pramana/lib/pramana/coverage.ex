defmodule Pramana.Coverage do
  @moduledoc """
  What the corpus does **not** contain, stated explicitly.

  An empty result has two completely different meanings — *"the canon does not say
  this"* and *"that part of the canon is not loaded"* — and they are indistinguishable
  from the result alone. Everywhere else in this project that ambiguity is resolved by
  reporting coverage; this module does it for the one gap that matters most.

  ## The Taishō 56–84 gap

  CBETA covers Taishō volumes 1–55 and 85. Volumes **56–84 are exactly the
  Japanese-composed sectarian corpus** — Shingon, Tendai, Nichiren, Zen — which CBETA
  deliberately excludes and which only SAT publishes. Verified against the bake: the 56
  volumes present are precisely 1–55 and 85, and the 29 missing are precisely 56–84.

  So a reader who searches for a Japanese sectarian position today gets nothing, and
  nothing is a *lie by omission* unless the gap is stated. That is the exact inverse of
  the failure this project was built to prevent: instead of presenting a Japanese
  commentary as an Indian sūtra, it would present the Japanese tradition as silent.

  `Pramana.URN.Taisho.provenance_for_volume/1` already implements the 56–84 rule, so
  when SAT is acquired the material lands with correct provenance automatically. The
  blocker is acquisition, not classification — see `docs/SOURCES.md`.

  ## The CBETA collections gap

  The same failure, one level up. CBETA publishes **26 collections** and a bake holds some
  of them. While the Taishō was the only one loaded, "the Chinese canon" and "what we have"
  were close enough to the same sentence that nobody wrote the difference down. They are not
  the same sentence: a reader searching for a 嘉興藏 text the bake does not hold gets an
  empty result with nothing to distinguish *not in the canon* from *not in this bake*.

  **How many are held is deliberately not written here.** `cbeta/0` counts them from the
  corpus, and this paragraph said "two" through four ingests — a doc that quotes a computed
  number is a doc that will be wrong, and this module exists to stop exactly that kind of
  wrongness elsewhere.

  See `cbeta/0` and `Pramana.Cbeta.Collections`.
  """

  import Ecto.Query

  alias Pramana.Cbeta.Collections
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Taisho.Divisions
  alias Pramana.Telemetry

  @taisho_volumes 1..85
  @japanese_delta 56..84

  # The Tōhoku catalogue numbers the Degé Kangyur 1–1108 and the Degé Tengyur 1109–4569.
  # The division is not editorial: the Kangyur is what the tradition holds to be the
  # Buddha's word, the Tengyur is the Indian commentarial literature on it, and a corpus
  # holding one and not the other is silent about a whole genre rather than about a text.
  @kangyur_toh 1..1108
  @tengyur_toh 1109..4569

  @doc """
  How many works carry a date bound, and therefore what a date filter can even see.

  `composed_after`/`composed_before` are the sharpest filters this corpus offers and the
  most dangerous, because a work is datable only when its byline resolved to an authority
  person **and** that person has a recorded birth or death. Everything else is silently
  outside a dated query — not undated-and-therefore-late, just unaddressed by the filter.

  Reporting the total alongside the dated count is rule 44: a filter that discards most of
  the corpus without saying so produces a confident answer about a tenth of the evidence.
  No figure here is written down anywhere — run the function.
  """
  @spec dated() :: map()
  def dated do
    works = Repo.aggregate(Work, :count)
    dated = Repo.aggregate(from(w in Work, where: not is_nil(w.date_basis)), :count)
    linked = Repo.aggregate(from(w in Work, where: not is_nil(w.authority_id)), :count)

    %{
      works: works,
      dated: dated,
      authority_linked: linked,
      undated: works - dated,
      note:
        "#{dated} of #{works} works carry a date. A date is derived from the attributed " <>
          "person's lifespan (`date_basis: authority_lifespan`), so it exists only where a " <>
          "byline resolved to a DILA person with recorded dates — #{linked} works are " <>
          "linked, and not all linked people have dates. A `composed_before`/" <>
          "`composed_after` query therefore searches #{dated} works, not #{works}: an " <>
          "undated work is unaddressed by the filter, NOT excluded on evidence."
    }
  end

  @doc """
  Which Taishō volumes are in the bake and which are missing.

  Computed from the data rather than asserted, so it stays true when SAT lands.
  """
  @spec taisho() :: map()
  def taisho do
    present =
      Repo.all(from t in Text, where: t.witness_id == "T", select: t.volume, distinct: true)
      |> Enum.flat_map(&parse_volume/1)
      |> MapSet.new()

    missing = Enum.reject(@taisho_volumes, &MapSet.member?(present, &1))

    %{
      present: MapSet.size(present),
      expected: Enum.count(@taisho_volumes),
      # A bare list here inspects as a CHARLIST — 56..84 are all printable ASCII, so
      # `missing` renders as ~c"89:;<..." in any IO.inspect and reads as corruption.
      # The list is still what JSON needs; `missing_ranges` is what a human or a model
      # should be shown.
      missing: missing,
      missing_ranges: format_ranges(missing),
      japanese_delta_missing: japanese_delta_missing?(missing),
      # What is missing stated in WORK NUMBERS, not only volumes. A reader asking "do you
      # have Nichiren's writings" is asking about texts, and "volumes 56–84" requires them
      # to already know which volumes those are. The division table settles this without
      # any new acquisition: it records which Taishō number ranges fall in the Japanese
      # sections and how each is classified.
      missing_divisions: missing_divisions(missing),
      note: note(missing)
    }
  end

  # The divisions whose entire work-number range sits in volumes we do not hold.
  #
  # This is the honest half of what a catalogue would give us. We can say *which
  # divisions* are absent, their number ranges, and how the edition classifies them —
  # because the Taishō's own division table is data we already have. What we cannot say
  # is which individual works exist, or their titles and authors: that needs a catalogue
  # of volumes 56–84, and no openly-licensed machine-readable one exists (checked at the
  # #20 gate — CBETA's own catalogue stops at 55, and SAT publishes no bulk metadata).
  #
  # Stating the range without the works is not a half-measure; it is the difference
  # between "something is missing" and "T2185–T2731, the Japanese sub-commentaries, are
  # missing", which is a question a reader can act on.
  defp missing_divisions(missing_volumes) do
    volumes = MapSet.new(missing_volumes)

    Divisions.all()
    |> Enum.filter(fn division ->
      division.volumes
      |> volume_numbers()
      |> case do
        [] -> false
        vols -> Enum.all?(vols, &MapSet.member?(volumes, &1))
      end
    end)
    |> Enum.map(fn division ->
      %{
        division: division.name,
        division_en: division.name_en,
        volumes: division.volumes,
        work_numbers: "T#{pad(division.first)}–T#{pad(division.last)}",
        work_number_count: division.last - division.first + 1,
        composition_origin: division.composition_origin,
        text_role: division.text_role
      }
    end)
  end

  # "56-83" or "84" -> the integers it covers.
  defp volume_numbers(spec) when is_binary(spec) do
    case String.split(spec, "-") do
      [one] ->
        one |> Integer.parse() |> then(fn {n, _} -> [n] end)

      [from, to] ->
        with {a, _} <- Integer.parse(from), {b, _} <- Integer.parse(to), do: Enum.to_list(a..b)
    end
  rescue
    _ -> []
  end

  defp volume_numbers(_), do: []

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 4, "0")

  @doc """
  Which CBETA collections are in the bake, and which are not.

  Computed from the witnesses actually loaded against the pinned catalogue, so it stops
  saying this as collections land. A collection with no name here has not been acquired:
  each CBETA file states its own collection in `<sourceDesc>`, and rather than guess what
  a two-letter code expands to, the name arrives with the files. See
  `Pramana.Cbeta.Collections`.
  """
  @spec cbeta() :: map()
  def cbeta do
    held =
      Repo.all(
        from t in Text, where: t.source_id == "cbeta", select: t.witness_id, distinct: true
      )
      |> MapSet.new()

    {present, missing} = Enum.split_with(Collections.all(), &MapSet.member?(held, &1.id))

    %{
      collections_held: length(present),
      collections_published: length(Collections.all()),
      held: Enum.map(present, & &1.id),
      missing: Enum.map(missing, &Map.take(&1, [:id, :works, :name, :name_en])),
      works_held: Enum.sum(Enum.map(present, & &1.works)),
      works_published: Collections.total_works(),
      catalogue_pin: Collections.pin(),
      note: cbeta_note(present, missing)
    }
  end

  @doc """
  The CBETA coverage sentence for a given held/missing split.

  Public so the wording can be tested without a corpus: this is the sentence a reader of
  the public artefact sees in place of the Chinese canon, and it was wrong for as long as
  nothing exercised the empty case.
  """
  @spec cbeta_note_for([map()], [map()]) :: String.t()
  def cbeta_note_for(present, missing), do: cbeta_note(present, missing)

  defp cbeta_note(_present, []), do: "Every CBETA collection is loaded."

  # HOLDING NONE OF IT IS THE LARGEST GAP, NOT AN ABSENT TOPIC.
  #
  # A bake with no CBETA at all — the public artefact is exactly this — needs the plainest
  # statement there is, and the list-of-what-is-missing sentence below is the wrong shape
  # for it: it renders as "this bake holds 0: ." and then recites 26 collections a reader
  # never expected to be there. Say the one thing that matters instead.
  defp cbeta_note([], missing) do
    "This bake holds NO Chinese Buddhist canon. All #{length(missing)} CBETA collections " <>
      "and #{Enum.sum(Enum.map(missing, & &1.works))} works are absent, so there is no " <>
      "Chinese material here to find — an empty result for a Chinese query means the text " <>
      "is not in this bake and says nothing about the canon. Acquire with " <>
      "`mix pramana.acquire_all --source cbeta --canon <ID>`."
  end

  defp cbeta_note(present, missing) do
    absent_works = Enum.sum(Enum.map(missing, & &1.works))

    # NAMED, not coded. A reader who knows this canon knows it as 嘉興大藏經, and being told
    # that "J (287)" is missing asks them to decode an abbreviation before they can tell
    # whether the gap matters to them.
    top =
      missing
      |> Enum.take(5)
      |> Enum.map_join("; ", fn c -> "#{c.id} #{c.name} (#{c.works} works)" end)

    "CBETA publishes #{length(present) + length(missing)} collections and this bake holds " <>
      "#{length(present)}: #{Enum.map_join(present, ", ", & &1.id)}. " <>
      "#{length(missing)} collections and #{absent_works} works are NOT loaded — largest first: " <>
      "#{top}. An absence of results from those collections means they are not in this " <>
      "bake; it does NOT mean the canon is silent. Acquire one with " <>
      "`mix pramana.acquire_all --source cbeta --canon <ID>`."
  end

  @doc """
  A one-line warning for callers that must not mistake absence for silence, or `nil`.

  Returned as its own field rather than folded into prose so a tool response can carry
  it verbatim and a model cannot skim past it.
  """
  @spec caveat() :: String.t() | nil
  def caveat do
    active = active_caveats()

    # WHICH CAVEAT FIRES MOST IS AN ACQUISITION LIST, and nobody was counting. This is the
    # moment the system says "here is what is missing" — emitted here rather than at each
    # call site so every serving path is counted without one of them being forgotten.
    #
    # It counts internal calls too. That is a known imprecision and a cheap one: the figure
    # answers "which gap do callers keep hitting", and a handful of diagnostic calls does not
    # change which gap is largest.
    if active != [] do
      Telemetry.emit([:pramana, :coverage, :caveat], %{fired: length(active)}, %{
        kinds: Enum.sort(Keyword.keys(active))
      })
    end

    case Keyword.values(active) do
      [] -> nil
      texts -> Enum.join(texts, " ")
    end
  end

  @doc """
  Which gaps are currently worth stating, as atoms.

  `caveat/0` joins these into prose, which is right for a reader and useless for counting —
  and *which* gap callers keep hitting is a prioritised acquisition list. Separating the two
  is what makes the list countable.
  """
  @spec caveats() :: [:taisho | :cbeta | :tibetan]
  def caveats, do: Keyword.keys(active_caveats())

  # Computed ONCE. Each of these runs queries, and an earlier version of `caveat/0` asked for
  # the kinds and then asked again for the prose — paying twice for the same three answers on
  # a path that runs on every search.
  defp active_caveats do
    [taisho: taisho_caveat(), cbeta: cbeta_caveat(), tibetan: tibetan_caveat()]
    |> Enum.reject(fn {_kind, text} -> is_nil(text) end)
  end

  # SUPPRESSED WHEN THERE IS NO TAISHŌ AT ALL, because a narrower true statement in place
  # of a wider one is worse than silence. On the public artefact, which holds no CBETA,
  # "Taishō volumes 56–84 are not loaded" was the ONLY caveat a reader saw — and it implies
  # volumes 1–55 are present. They are not. `cbeta_caveat/0` says the real thing.
  defp taisho_caveat do
    case {taisho(), cbeta()} do
      {_, %{collections_held: 0}} -> nil
      {%{japanese_delta_missing: true}, _} -> japanese_caveat()
      _ -> nil
    end
  end

  # `collections_held: 0` used to return nil here, on the reading that a bake with no CBETA
  # was a bake CBETA had nothing to say about. That is exactly backwards: holding none of it
  # is the largest gap there is, and it was the one case this stayed quiet about.
  defp cbeta_caveat do
    case cbeta() do
      %{missing: [], collections_held: n} when n > 0 -> nil
      %{note: note} -> note
    end
  end

  @doc """
  How far each DERIVATION has got, against the inputs it could reach.

  `gaps/0` and its neighbours ask what has not been **acquired**. `stranded/0` asks what
  was derived and left where nothing queries it. This asks the third question: **has this
  derivation run, and is what it produced the whole of what it can produce?**

  It exists because that question was misread four times on 2026-09-02, always the same
  way — a *value* was checked instead of the *work*. "24 commentaries aligned" reads as a
  quarter of the 89 relations until you know the 43 pairs above the floor collapse to 24
  distinct works, at which point it is complete. `count(title) = 0` reads as "no titles
  exist" when the titles were in `works.meta`. Each time the fix was a denominator.

  So every row here carries its own, and the note says what the remainder IS — because
  "43 of 89" is only useful beside "the other 46 are relations this method cannot see,
  not relations that are wrong".
  """
  @spec derivations() :: [map()]
  def derivations do
    [alignment_coverage(), relation_coverage(), tibetan_title_coverage()]
  end

  # A pair is alignable when both works are Chinese — 科文 alignment rests on an
  # eight-CHARACTER window being unique in the root, which is a fact about Chinese.
  defp alignment_coverage do
    %{rows: [[pairs]]} =
      Repo.query!("""
      SELECT count(*) FROM (
        SELECT DISTINCT r.source_work_id, r.target_work_id
          FROM work_relations r
          JOIN texts cs ON cs.work_id = r.source_work_id
          JOIN texts rt ON rt.work_id = r.target_work_id
         WHERE r.relation = 'comments_on' AND r.target_work_id IS NOT NULL
           AND cs.source_id IN ('cbeta','sat','local-huang-nianzu-jie')
           AND rt.source_id IN ('cbeta','sat','local-huang-nianzu-jie')) x
      """)

    # PAIRS AGAINST PAIRS. Counting distinct commentaries against a pair denominator
    # reads as "24 of 89, a quarter done" — which is precisely the misreading this whole
    # section exists to stop, reproduced inside it. 43 pairs cleared the floor and they
    # collapse to 24 works, because an ambiguous relation gives one commentary several
    # candidate roots.
    %{rows: [[aligned_pairs, works, rows]]} =
      Repo.query!("""
      SELECT count(*), count(DISTINCT commentary_work_id), sum(n) FROM (
        SELECT commentary_work_id, root_work_id, count(*) n
          FROM commentary_alignments GROUP BY 1, 2) x
      """)

    %{
      what: "commentary alignment",
      done: aligned_pairs,
      eligible: pairs,
      unit: "alignable pair(s) — #{works} distinct commentaries, #{rows} line alignments",
      note:
        "A pair below the density floor is not a refuted relation — a commentary may " <>
          "paraphrase, and this method sees only verbatim quotation. More alignments " <>
          "need more `comments_on` relations, not another run."
    }
  end

  defp relation_coverage do
    %{rows: [[linked, commentarial]]} =
      Repo.query!("""
      SELECT count(*) FILTER (WHERE EXISTS (
               SELECT 1 FROM work_relations r
                WHERE r.source_work_id = w.id AND r.relation <> 'parallel_of')),
             count(*)
        FROM works w
       WHERE w.text_role IN ('commentary','subcommentary','treatise')
      """)

    %{
      what: "commentary -> root links",
      done: linked,
      eligible: commentarial,
      unit: "commentarial works reach a root",
      note:
        "Title matching finds a root only when the title names one. 大智度論 explains " <>
          "摩訶般若波羅蜜經 without naming it, so the unlinked remainder is mostly works " <>
          "no title rule can reach — a new signal, not a re-run."
    }
  end

  defp tibetan_title_coverage do
    %{rows: [[titled, total]]} =
      Repo.query!("""
      SELECT count(DISTINCT w.id) FILTER (WHERE w.title IS NOT NULL), count(DISTINCT w.id)
        FROM works w JOIN texts t ON t.work_id = w.id
       WHERE t.source_id IN ('derge','derge-tengyur')
      """)

    %{
      what: "Tibetan work titles",
      done: titled,
      eligible: total,
      unit: "works named",
      note:
        "The remainder print no title block at all — mostly continuations of a work " <>
          "spanning volumes. Closing it needs the Degé dkar chag or BDRC, a new source."
    }
  end

  @doc """
  Data the corpus HOLDS and no query can reach.

  A different question from the rest of this module. Everything else asks what has not
  been acquired; this asks what was acquired, derived, and then left in a place nothing
  reads — where every count looks healthy and a capability is silently absent.

  It exists because of a real one: the Degé ingest writes each work's title into
  `works.meta` and leaves `works.title` null, so 2,675 Tengyur works had a title,
  `get_outline` and `search` could not show it, and `count(title) = 0` invited writing a
  parser for text that had already been parsed. **Both failures are the same failure** —
  nobody asked whether the value was already held somewhere else.

  Each row names the promotion that fixes it, because a warning without a remedy is a
  warning people learn to skim. Returns `[]` when nothing is stranded.
  """
  @spec stranded() :: [%{what: String.t(), count: non_neg_integer(), fix: String.t()}]
  def stranded do
    [
      %{
        query: """
        SELECT count(DISTINCT w.id) FROM works w
         WHERE w.title IS NULL
           AND (w.meta ? 'title_sa_ltn_computed' OR w.meta ? 'title_bo_ltn_computed')
        """,
        what: "works have a title in works.meta and null in works.title",
        fix: "mix pramana.derge.titles --write"
      }
    ]
    |> Enum.map(fn probe ->
      %{rows: [[count]]} = Repo.query!(probe.query)
      %{what: probe.what, count: count, fix: probe.fix}
    end)
    |> Enum.reject(&(&1.count == 0))
  end

  @doc """
  How many texts a `role:` filter cannot reach, because they have no role at all.

  `text_role` is a retrieval FILTER, so a query for `["root"]` returns only texts that
  carry a role — and **1,640 do not**. That is every non-Taishō CBETA collection: the role
  comes from the Taishō's 部 division table, and nothing else has one. A caller asking for
  root scripture gets the Taishō and no indication that X's 1,230 works, J's 285 and N's 38
  were never candidates.

  This is the coverage doctrine applied to a filter rather than to the corpus. The answer
  to a filtered query is not just what matched; it is also **what the filter could never
  have matched**, and only one of those is visible in a result list.

  **Deliberately not fixed by assigning roles.** `Pramana.Cbeta.Byline` refuses to infer
  from 撰 because "guessing would put a wrong label on thousands of works", and N sharpens
  it: N holds the whole Tipiṭaka — sutta, vinaya and abhidhamma — so a single role for the
  collection would be wrong three ways. Reporting the gap is honest; filling it by
  inference is not.
  """
  @spec roles() :: map()
  def roles do
    total = Repo.aggregate(from(t in Text), :count)

    unroled =
      Repo.all(
        from t in Text,
          join: w in Work,
          on: w.id == t.work_id,
          where: is_nil(w.text_role),
          group_by: t.witness_id,
          order_by: [desc: count(t.id)],
          select: {t.witness_id, count(t.id)}
      )

    missing = Enum.reduce(unroled, 0, fn {_w, n}, acc -> acc + n end)

    %{
      texts: total,
      without_role: missing,
      by_witness: Enum.map(unroled, fn {w, n} -> %{witness: w, texts: n} end),
      note: roles_note(missing, unroled)
    }
  end

  defp roles_note(0, _), do: nil

  defp roles_note(missing, unroled) do
    witnesses = Enum.map_join(unroled, ", ", fn {w, n} -> "#{w} (#{n})" end)

    "#{missing} text(s) carry no `text_role`, so a `role:` filter cannot return them at " <>
      "all — by witness: #{witnesses}. The role comes from the Taishō's 部 division table " <>
      "and no other collection has one. An empty or thin result under a role filter may " <>
      "mean the material was never a candidate, not that the canon is silent."
  end

  @doc """
  How much of SuttaCentral's parallel graph this bake can actually open.

  **24,717 of 407,176 — 6.1%.** That number had never been published, and the number that
  had invites the opposite impression: the reader says per work that T0099 has 1,958
  recorded and 1,661 resolvable, which reads as resolution running at 85%.

  Corpus-wide it runs at 6.1%, and the gap is almost entirely the **Vinaya prātimokṣa
  witnesses** — `san-mu-bu-pm-gbm` (12,524 parallels), `san-sarv-bu-pm-tf` (8,946),
  `lzh-sarv-bu-pm` (8,729). SuttaCentral collates the monastic codes across Sanskrit
  manuscript finds and several Chinese recensions it publishes itself; none of those is a
  source in this bake, and CBETA does not publish them separately either.

  This is coverage, not a defect: **every unresolved row was checked and none is a
  resolution failure** — all 363,047 name a work no source here provides. Which is exactly
  why it must be stated. A parallels feature that silently shows a sixteenth of what it
  knows about invites the reading that the rest does not exist.
  """
  @spec parallels() :: map()
  def parallels do
    total = Repo.aggregate(from(p in "text_parallels"), :count)

    resolved =
      Repo.aggregate(
        from(p in "text_parallels", where: not is_nil(p.source_urn) and not is_nil(p.target_urn)),
        :count
      )

    absent =
      Repo.all(
        from p in "text_parallels",
          where: is_nil(p.source_work_id),
          group_by: fragment("regexp_replace(?, \'[0-9].*$\', \'\')", p.source_uid),
          order_by: [desc: count(p.id)],
          limit: 6,
          select: {fragment("regexp_replace(?, \'[0-9].*$\', \'\')", p.source_uid), count(p.id)}
      )

    %{
      recorded: total,
      openable: resolved,
      percent: if(total > 0, do: Float.round(100 * resolved / total, 1), else: 0.0),
      absent_witnesses: Enum.map(absent, fn {uid, n} -> %{prefix: uid, parallels: n} end),
      note: parallels_note(total, resolved, absent)
    }
  end

  defp parallels_note(0, _resolved, _absent), do: "No parallel data is loaded."

  defp parallels_note(total, resolved, absent) do
    names = Enum.map_join(absent, ", ", fn {uid, n} -> "#{uid} (#{n})" end)

    "SuttaCentral records #{total} passage parallels and #{resolved} of them — " <>
      "#{Float.round(100 * resolved / total, 1)}% — have both ends in this bake. " <>
      "The rest point at witnesses the corpus does not hold, chiefly: #{names}. " <>
      "A parallel we cannot open is COUNTED and not dropped, because knowing a passage " <>
      "has a Sanskrit or Gāndhārī parallel is worth something even when we cannot show it."
  end

  @doc """
  Which part of the Tibetan canon is in the bake.

  The Tōhoku numbers say which: 1–1108 is the Kangyur, 1109–4569 the Tengyur. Holding
  one and not the other is the same failure the Taishō 56–84 gap is — an absence that
  reads as the tradition being silent — except that here the missing half is the entire
  Indian commentarial literature. A caller asking what Vasubandhu says about a sūtra gets
  nothing, and nothing is not an answer to that question.

  Computed from the works actually loaded, so it stops saying this when the Tengyur lands.
  """
  @spec tibetan() :: map()
  def tibetan do
    # Both halves of the edition, because the question is about the canon rather than
    # about a source id: the Kangyur and Tengyur are published separately and are one
    # print.
    numbers =
      Repo.all(
        from t in Text,
          where:
            t.source_id in ["derge", "derge-tengyur"] and
              fragment("? ~ '^toh[0-9]+'", t.work_id),
          select: fragment("(regexp_replace(?, '^toh([0-9]+).*$', '\\1'))::int", t.work_id)
      )

    kangyur = Enum.count(numbers, &(&1 in @kangyur_toh))
    tengyur = Enum.count(numbers, &(&1 in @tengyur_toh))

    %{
      kangyur_works: kangyur,
      tengyur_works: tengyur,
      tengyur_missing: kangyur > 0 and tengyur == 0,
      note: tibetan_note(kangyur, tengyur)
    }
  end

  defp tibetan_note(0, _tengyur), do: "No Tibetan material is loaded."

  defp tibetan_note(_kangyur, 0), do: tengyur_caveat()

  defp tibetan_note(kangyur, tengyur),
    do: "#{kangyur} Kangyur and #{tengyur} Tengyur work(s) are loaded."

  defp tibetan_caveat do
    case tibetan() do
      %{tengyur_missing: true} -> tengyur_caveat()
      _ -> nil
    end
  end

  defp tengyur_caveat do
    "The Degé Tengyur (Tōhoku 1109–4569) is NOT loaded — only the Kangyur. The Tengyur " <>
      "is the Indian commentarial literature, so an absence of Tibetan commentary means " <>
      "that half of the canon is not in this bake; it does NOT mean the commentators " <>
      "are silent."
  end

  defp japanese_delta_missing?(missing) do
    Enum.any?(@japanese_delta, &(&1 in missing))
  end

  defp note([]), do: "All 85 Taishō volumes are loaded."

  defp note(missing) do
    if japanese_delta_missing?(missing) do
      japanese_caveat()
    else
      "Missing Taishō volumes: #{format_ranges(missing)}."
    end
  end

  # The count is READ, not asserted, because the sentence around it stopped being true.
  #
  # This said "an absence of Japanese-composed results means the material is not in this
  # bake", which was correct while the Taishō was the only collection held and became
  # wrong the moment CBETA X landed with 145 Japanese-composed works. A caveat that
  # overstates a gap is the same defect as one that understates it: both leave a reader
  # unable to tell what the corpus actually holds. Three gold cases were premised on the
  # old sentence and flipped to failing on an ingest that made the corpus MORE complete.
  defp japanese_caveat do
    held = japanese_works_held()

    # 541, MEASURED — and the 547 this said until 2026-08-30 was never a count. It is
    # 2731 - 2185 + 1, the width of the number range, on the assumption that every Taishō
    # number in it is a work. SAT publishes 541 IIIF manifests in that range
    # (`raw/sat-iiif/manifests_index_20260830.html`, one public directory listing), spanning
    # exactly volumes 56-84. Six numbers in the range are not works.
    #
    # Which is the defect the comment above warns about, committed by the line below it: a
    # caveat that overstates a gap is as wrong as one that understates it. 541 is a floor —
    # a work without a manifest would not appear — so it is stated as "at least".
    "Taishō volumes 56–84 (work numbers T2185–T2731, at least 541 of them) are NOT " <>
      "loaded. Those " <>
      "volumes are the Japanese-composed sectarian corpus (Shingon, Tendai, Nichiren, " <>
      "Zen); CBETA excludes them and only SAT publishes them. " <>
      japanese_held_clause(held) <>
      " So an absence of Japanese-composed results may mean the material is not in this " <>
      "bake, and does NOT mean the tradition is silent."
  end

  defp japanese_held_clause(0),
    do: "This bake holds NO Japanese-composed work at all."

  defp japanese_held_clause(n),
    do:
      "This bake does hold #{n} Japanese-composed work(s), from other CBETA collections — " <>
        "so the Japanese tradition is partially present, not absent."

  defp japanese_works_held do
    Repo.aggregate(from(w in Work, where: w.composition_origin == "japanese"), :count)
  end

  # 56–84 reads better than 29 comma-separated integers, and the gap is contiguous.
  defp format_ranges(volumes) do
    volumes
    |> Enum.sort()
    |> Enum.chunk_while(
      [],
      fn v, acc ->
        case acc do
          [prev | _] when v == prev + 1 -> {:cont, [v | acc]}
          [] -> {:cont, [v]}
          _ -> {:cont, Enum.reverse(acc), [v]}
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Enum.map_join(", ", fn
      [single] -> Integer.to_string(single)
      run -> "#{List.first(run)}–#{List.last(run)}"
    end)
  end

  # Volumes are stored as strings; anything non-numeric is a data problem elsewhere and
  # must not crash a coverage report.
  defp parse_volume(nil), do: []

  defp parse_volume(volume) do
    case Integer.parse(volume) do
      {n, ""} -> [n]
      _ -> []
    end
  end
end
