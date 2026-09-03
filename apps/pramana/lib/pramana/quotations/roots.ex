defmodule Pramana.Quotations.Roots do
  @moduledoc """
  What a commentary comments on, proposed from the quotation graph.

  Title matching reaches a root only when the title names one, which leaves most
  commentarial works with no root at all — `mix pramana.doctor` prints the fraction.
  大智度論 explains 摩訶般若波羅蜜經 and never says so. This proposes the missing ones.

  ## The rule, and what it is not

  **A commentarial work's root is its dominant shared-text partner among works whose
  `text_role` is `root`.** That is a candidate generator over an undirected graph, not a
  reading of a citation graph — the quotation scan finds character identity and cannot
  say who quoted whom (`Pramana.Quotations`, rule 72, `docs/PROXIES.md`). What makes the
  inference legitimate here is the *asymmetry supplied from outside the graph*: one end
  is known to be a commentary and the other known to be scripture, so the direction comes
  from `text_role` rather than from the edge.

  **Restricting partners to root-role works is load-bearing.** Unrestricted, the same
  rule scores 43.8%, because two commentaries on one sūtra share *the sūtra's* words with
  each other — `T1703`'s strongest partner is `T1701`, both commentaries on the Diamond
  Sūtra.

  ## Distinct passages, never rows

  Evidence is `count(DISTINCT text_sha256)`, and counting quotation rows instead is a
  defect rather than a simplification. A root text that repeats itself contributes one
  row per repetition: `T1723` 妙法蓮華經玄贊 shares a single 29-character list of the ten
  stages with `T0220a`, printed there five times, and by row count that one string outvoted
  the Lotus Sūtra it actually explains. Rows measure the corpus's redundancy; distinct
  passages measure the relationship. Rule 73.

  ## Families, not work ids

  `T0220a`–`T0220d` are four ids for one work, so partners are grouped by family —
  `regexp_replace(work_id, '[a-z]+$', '')`, the same key rule 72 requires — before
  dominance is decided, and a partner in the source's own family is dropped as
  self-reference. Within the winning family the best-attested witness is the one
  proposed, and the others travel in `evidence` so that choice stays visible.

  ## Bands, measured against title matching

  `mix pramana.relations.derive` links some of these works from their titles,
  independently of anything here, so it is usable as ground truth. Scoring this rule
  against it — one row per work, so per-work and per-row precision are the same number.
  **These are the figures of 2026-09-02**; `validate/1` re-derives them on every run and
  `mix pramana.relations.shared_text` prints what it gets:

      of what would be WRITTEN                works  correct
      dominant family, n >= 5                    17       14
      dominant family, n < 5                     12        6
      ---                                        29       20

      of what is REFUSED — low earns the refusal
      dominant family, n >= 5                     1        0
      dominant family, n < 5                      3        0
      no dominant family (a tie)                  5        1
      ---                                         9        1

  **38 testable works is small, and the figure has already moved once for that reason.**
  It read `13 of 13` in the strong band against a ground truth of 26, until
  `Pramana.Relations.may_explain/1` let title matching reach twelve more works and three
  of them turned out to disagree. Read the bands as evidence of *shape* — every error is
  below the floor, in a tie, or a role that is refused — and never as a rate.

  The ground truth is also coarser than this rule in a way that scores it DOWN. `T1806`
  四分律比丘含注戒本 is counted wrong for proposing `T1429` 四分律比丘戒本 where the title
  says `T1428` 四分律, and annotating the prātimokṣa is the more precise answer.

  So a dominant family at or above the floor is asserted `probable`, below it `uncertain`,
  and a tie is **reported and not written**. That last is not resolving-versus-recording
  ambiguity: a 33-way tie at one shared passage is an absence of evidence rather than a
  choice between roots, and per row the tied band scored 3 of 22 where per work it
  flattered itself at 3 of 4.

  ## Treatises are derived and not asserted

  **No treatise is testable at all** — none is linked from its title — while treatises are
  82 of the 171 works this proposes for. An untested half would be caveat enough; the
  reason to refuse is stronger than that, and visible.

  A `commentary` is by definition about another text. A `treatise` need not be, and the
  top of its band is one systematic error repeated:

      T1537 阿毘達磨法蘊足論   ->  T0220a 大般若波羅蜜多經     25 shared passages
      T1536 阿毘達磨集異門足論 ->  T0220a                      13
      T1563 阿毘達磨藏顯宗論   ->  T0220a                       8
      T1562 阿毘達磨順正理論   ->  T0220a                       7
      T1544 阿毘達磨發智論     ->  T0220a                       6

  Five Sarvāstivāda Abhidharma treatises proposed as commentaries on the
  Mahāprajñāpāramitā. They are not: they share Abhidharma list-formulae with a sūtra that
  is itself full of them, which is rule 72's failure mode arriving as a *systematic* error
  rather than scattered noise. `T1579` 瑜伽師地論 -> `T0676` 解深密經 is the same shape and
  a subtler one — the Yogācārabhūmi absorbs the Saṃdhinirmocana wholesale and does not
  comment on it.

  Restricted to the roles that are written the artifact shrinks and does not vanish: nine
  proposals still point at the `T0220` family and three are `probable`. Treatises stay
  derived, reported and unwritten until something can test them.

  ## Subcommentaries are refused too, and for a sharper reason

  A `subcommentary` here is a work of `論疏部` (T1816–T1850, "Śāstra exegesis"), a Taishō
  division whose *defining purpose* is commenting on 論 — and every 論 division in
  `Pramana.Taisho.Divisions` is `text_role: treatise`:

      1816-1850  論疏部  Śāstra exegesis  ->  subcommentary
      1536-1563  毘曇部  Abhidharma       ->  treatise
      1564-1578  中觀部  Madhyamaka       ->  treatise
      1579-1627  瑜伽部  Yogācāra         ->  treatise

  **So the partner restriction excludes, by construction, the only works a subcommentary
  can be about.** `T1830` 成唯識論述記 explains `T1585` 成唯識論, a `treatise`; restricted to
  root-role partners it cannot reach it, does not abstain, and proposes the
  Mahāprajñāpāramitā instead. A `subcommentary_of` pointing at a sūtra is incoherent
  whatever the evidence, so these are refused rather than written weakly.

  **The real fix is that the partner role is a function of the source role**, not one
  global constant: a `commentary` (釋經論部, 經疏部, 律疏部) explains scripture and a
  `subcommentary` (論疏部) explains a śāstra. That is read off a division table already in
  the repository and already validated, so it is deterministic — and
  `mix pramana.relations.derive` holds the same constant and therefore the same blind
  spot, which is *why* no subcommentary is testable here. Fixing it there first produces
  the ground truth this rule would need. `docs/PLAN.md`.

  ## The failure mode that survives the refusals

  **The graph may hold no evidence for the right answer, and silence reads as dominance.**
  `T1708` 仁王經疏 shares seven distinct passages with the `T0220` family and *nothing* with
  either surviving 仁王經 (`T0245`, `T0246`) above the scan's 20-character floor. With no
  root-role competitor there is no runner-up, a sole partner is dominance by definition,
  and the answer is confidently wrong at `probable`. **`runner_up_passages: nil` in the
  evidence is the tell** — it means unopposed, not decisive.

  No widening of the partner set reaches this one, and it is not the same defect as the
  subcommentary blind spot above: there the right answer was excluded, here it is absent.
  Requiring a beaten runner-up, or a higher floor when nothing was beaten, are the
  candidates worth measuring against the ground truth.

  **What is not happening: `T0220` is not simply winning by being enormous.** It is the
  top partner for 9 of the written proposals and 3 of the `probable` ones, against 7 and 3
  for `T0279` 華嚴經, which has many real commentaries. A hub penalty was considered and
  has no anomaly to threshold on, so none was built.
  """

  alias Pramana.Repo

  @typedoc "One proposal: a commentarial work and the root it most shares text with."
  @type candidate :: %{
          work_id: String.t(),
          title: String.t() | nil,
          text_role: String.t(),
          target_work_id: String.t(),
          target_title: String.t() | nil,
          family: String.t(),
          family_members: [%{work_id: String.t(), passages: non_neg_integer()}],
          passages: pos_integer(),
          runner_up: non_neg_integer() | nil,
          families: pos_integer(),
          tied: pos_integer(),
          band: :strong | :weak | :tied
        }

  # Five distinct shared passages. The band above it scored 14 of 17 and the band below it
  # 6 of 12 on 2026-09-02, and the cut is quoted with those denominators wherever it is
  # reported: 29 cases cannot establish a threshold, only fail to refute one. It read
  # 13 of 13 against a smaller ground truth, which is why `validate/1` recomputes.
  @strong_passages 5

  # The roles that explain something at all. Derived, not restated: `Pramana.Relations`
  # owns which roles are exegetical and what each may explain (rule 75), and a second copy
  # here is how the first one goes stale.
  @commentarial Pramana.Relations.explanatory_roles()

  # The one role whose works are about ROOT SCRIPTURE, which is what the partner set holds.
  # See the moduledoc: a treatise need not be about anything and nothing tests them, and a
  # subcommentary is about a śāstra the partner set excludes by construction.
  @assertable ~w(commentary)

  @doc "The shared-passage count above which a dominant partner is asserted `probable`."
  @spec strong_passages() :: pos_integer()
  def strong_passages, do: @strong_passages

  @doc "Work roles a proposal may be written for. The moduledoc has why the other two are not."
  @spec assertable_roles() :: [String.t()]
  def assertable_roles, do: @assertable

  @doc """
  The proposals that may be written: a dominant root family, and a role whose works are
  about root scripture.

  Everything else is derived and reported anyway, because a refusal with its evidence is
  worth more than a candidate silently never generated.
  """
  @spec assertable([candidate()]) :: [candidate()]
  def assertable(candidates) do
    Enum.filter(candidates, &(&1.band != :tied and &1.text_role in @assertable))
  end

  @doc """
  Every commentarial work that shares text with a root-role work, with its best candidate.

  One entry per work, banded. Ordered by evidence, strongest first, so a report that
  truncates truncates the weakest end.
  """
  @spec candidates(keyword()) :: [candidate()]
  def candidates(opts \\ []) do
    min_passages = Keyword.get(opts, :min_passages, 1)

    %{rows: rows} = Repo.query!(sql(), [@commentarial, min_passages])

    Enum.map(rows, &row/1)
  end

  defp row([
         work_id,
         title,
         role,
         target,
         target_title,
         family,
         members,
         n,
         runner,
         families,
         tied
       ]) do
    %{
      work_id: work_id,
      title: title,
      text_role: role,
      target_work_id: target,
      target_title: target_title,
      family: family,
      family_members: Enum.map(members, fn [id, count] -> %{work_id: id, passages: count} end),
      passages: n,
      runner_up: runner,
      families: families,
      tied: tied,
      band: band(tied, n)
    }
  end

  defp band(tied, _n) when tied > 1, do: :tied
  defp band(_tied, n) when n >= @strong_passages, do: :strong
  defp band(_tied, _n), do: :weak

  @doc """
  Every work that already explains something.

  A proposal for one of these is corroboration rather than a new link, and the two are
  worth separating in a report: the prize is the works that reach nothing today.

  `:except_method` drops one method's own rows, and a report about that method needs it.
  Without it the count answers "what would be new" only until the first `--write`, after
  which the method's own output makes it permanently zero — a number that silently stops
  measuring what it says.
  """
  @spec already_rooted(keyword()) :: MapSet.t()
  def already_rooted(opts \\ []) do
    {sql, params} =
      case Keyword.get(opts, :except_method) do
        nil -> {"", []}
        method -> {" AND method <> $1", [method]}
      end

    %{rows: rows} =
      Repo.query!(
        "SELECT DISTINCT source_work_id FROM work_relations " <>
          "WHERE relation <> 'parallel_of'" <> sql,
        params
      )

    MapSet.new(rows, &hd/1)
  end

  @doc """
  Scores the proposals against the links `mix pramana.relations.derive` found from titles.

  Independent ground truth, and the only ground truth there is: title matching reads the
  title and this reads the text, so neither can confirm the other by construction. It is
  also imperfect in a way that biases the score DOWN — `T1712` 般若波羅蜜多心經略疏 is
  scored wrong for proposing `T0250` 摩訶般若波羅蜜大明呪經, which is Kumārajīva's Heart
  Sūtra and simply is not among the titles containing 般若波羅蜜多心經.

  Returned per band with both numbers, because a precision without its denominator is the
  failure this project is most prone to — rules 22, 44 and 54. Computed on every run
  rather than quoted, so it cannot go stale as the corpus grows.

  ## Written and refused are scored apart, and blending them was wrong

  A single figure over every testable work answers no question anyone has. It charges the
  rule for proposals it declines to write, and it hides whether declining them was right.
  So `:written` scores what `assertable/1` keeps — *how often is what I wrote correct* —
  and `:refused` scores the rest, which is the refusal decision **measured** rather than
  argued: a refused band that scored well would mean the refusal is costing real links.
  """
  @spec validate([candidate()]) :: %{
          written: scored(),
          refused: scored(),
          roles: %{String.t() => non_neg_integer()}
        }
  def validate(candidates) do
    truth = title_match_targets()

    testable = Enum.filter(candidates, &Map.has_key?(truth, &1.work_id))
    written = assertable(testable)
    refused = testable -- written

    %{
      written: score(written, truth),
      refused: score(refused, truth),
      # The roles present here are the roles the numbers describe, and they are not the
      # roles being proposed for.
      roles: Enum.frequencies_by(testable, & &1.text_role)
    }
  end

  @typedoc "One side of the validation: a total, and the same split by band."
  @type scored :: %{
          works: non_neg_integer(),
          correct: non_neg_integer(),
          bands: [%{band: atom(), works: non_neg_integer(), correct: non_neg_integer()}]
        }

  defp score(works, truth) do
    correct = &Enum.count(&1, fn w -> w.target_work_id in Map.fetch!(truth, w.work_id) end)

    bands =
      works
      |> Enum.group_by(& &1.band)
      |> Enum.map(fn {band, group} ->
        %{band: band, works: length(group), correct: correct.(group)}
      end)
      |> Enum.sort_by(&order(&1.band))

    %{works: length(works), correct: correct.(works), bands: bands}
  end

  defp order(:strong), do: 0
  defp order(:weak), do: 1
  defp order(:tied), do: 2

  defp title_match_targets do
    %{rows: rows} =
      Repo.query!("""
      SELECT source_work_id, array_agg(DISTINCT target_work_id)
        FROM work_relations
       WHERE method = 'title_match'
         AND relation IN ('comments_on', 'subcommentary_of')
         AND target_work_id IS NOT NULL
       GROUP BY 1
      """)

    Map.new(rows, fn [work_id, targets] -> {work_id, targets} end)
  end

  # One statement rather than a walk, because the graph is six figures of rows and the
  # grouping is what Postgres is for. `family` is rule 72's key; `DISTINCT q.text_sha256` is rule
  # 73's; the `<>` on families is self-reference, which excluding on the id alone would
  # miss for exactly the reason rule 72 was written.
  defp sql do
    """
    WITH ends AS (
      SELECT a_work_id AS w, b_work_id AS p, text_sha256 AS s FROM quotations
      UNION ALL
      SELECT b_work_id, a_work_id, text_sha256 FROM quotations
    ),
    per_member AS (
      SELECT e.w,
             e.p AS member,
             regexp_replace(e.p, '[a-z]+$', '') AS family,
             count(DISTINCT e.s)::int AS passages
        FROM ends e
        JOIN works c ON c.id = e.w AND c.text_role = ANY($1)
        JOIN works r ON r.id = e.p AND r.text_role = 'root'
       WHERE regexp_replace(e.p, '[a-z]+$', '') <> regexp_replace(e.w, '[a-z]+$', '')
       GROUP BY 1, 2, 3
    ),
    per_family AS (
      SELECT w, family, sum(passages)::int AS passages FROM per_member GROUP BY 1, 2
    ),
    ranked AS (
      SELECT *,
             rank() OVER (PARTITION BY w ORDER BY passages DESC) AS rk,
             count(*) OVER (PARTITION BY w)::int AS families
        FROM per_family
    ),
    winners AS (SELECT * FROM ranked WHERE rk = 1),
    tied AS (SELECT w, count(*)::int AS tied FROM winners GROUP BY 1),
    runner AS (SELECT w, max(passages)::int AS runner_up FROM ranked WHERE rk > 1 GROUP BY 1),
    -- Within the winning family, the best-attested witness. `member` breaks a tie so the
    -- same input always proposes the same work.
    best AS (
      SELECT DISTINCT ON (win.w)
             win.w, win.family, win.passages, pm.member
        FROM winners win
        JOIN per_member pm ON pm.w = win.w AND pm.family = win.family
       ORDER BY win.w, pm.passages DESC, pm.member
    )
    SELECT b.w,
           cw.title,
           cw.text_role,
           b.member,
           rw.title,
           b.family,
           (SELECT coalesce(json_agg(json_build_array(pm.member, pm.passages)
                                     ORDER BY pm.passages DESC, pm.member), '[]'::json)
              FROM per_member pm WHERE pm.w = b.w AND pm.family = b.family),
           b.passages,
           r.runner_up,
           (SELECT families FROM winners x WHERE x.w = b.w LIMIT 1),
           t.tied
      FROM best b
      JOIN tied t ON t.w = b.w
      JOIN works cw ON cw.id = b.w
      JOIN works rw ON rw.id = b.member
      LEFT JOIN runner r ON r.w = b.w
     WHERE b.passages >= $2
     ORDER BY b.passages DESC, b.w
    """
  end
end
