defmodule Mix.Tasks.Pramana.Relations.Parallels do
  @shortdoc "Derives work-level parallel_of from curated passage parallels"

  @moduledoc """
  Populates `work_relations` with `parallel_of` between Chinese works, aggregated from
  SuttaCentral's curated passage-level parallels.

      mix pramana.relations.parallels           # writes
      mix pramana.relations.parallels --dry-run
      mix pramana.relations.parallels --min-full 10

  ## The hole this closes

  `parallel_of` existed in the relation vocabulary and **nothing populated it** — the only
  asserted relations were 90 `comments_on` links. `Pramana.Compare` documents the gap and
  refuses to return an always-empty `alternates` key, and #23 (translator fingerprinting)
  is blocked on it outright: comparing how Kumārajīva and Xuanzang rendered a term requires
  knowing which works are versions of each other.

  The evidence was already in the database. `text_parallels` holds **3,103 Chinese↔Chinese
  passage parallels across 455 work pairs**, curated by SuttaCentral rather than computed
  here — which is invariant #5 in its strongest form: this is scholarship we hold, not a
  similarity score we invented.

  ## WHAT THIS DOES NOT CLAIM

  **Not 異譯本.** That means "an alternate translation of the same Indic original", and the
  parallel data does not distinguish it from other kinds of parallelism:

      T0099 <-> T0100   736 passages   雜阿含經 and 別譯雜阿含經 — the name of the second
                                       literally means "separately translated". 異譯本.
      T0099 <-> T0125   133 passages   Saṃyukta and Ekottarika Āgama — DIFFERENT
                                       COLLECTIONS transmitting related material, and
                                       neither a translation of the other.

  Both are genuine parallels; only the first is an alternate translation. So the relation
  asserted is `parallel_of` — a sibling — and never `translates`. Deciding which pairs are
  真 異譯本 is a scholarly judgement this data cannot make, and #23 should treat these as
  **candidates** rather than as settled versions. `Compare` already draws the same line for
  Chinese↔Pāli: "both descend from something earlier".

  ## Why a threshold, and why it is a judgement

  Passage parallels are evidence about *passages*. Promoting them to a claim about *works*
  needs enough of them. The distribution is severely skewed — median **2** shared passages
  per pair, p90 **4**, max **736** — so most pairs are two works that happen to share a
  couple of discourses, which is not a statement that the works are versions of each other.
  Those links already exist and are served by `get_parallels`; duplicating them as a
  whole-work claim would inflate a relation a reader is entitled to trust.

  `--min-full` defaults to **3** and the actual count is recorded in `evidence`, so the
  threshold is visible and arguable rather than buried. Confidence is graded by the same
  evidence: **probable** at 10 or more full parallels, **uncertain** below that.

  `mentions` parallels are excluded entirely — a work mentioning another is a reference,
  not a parallel.

  ## Symmetric, and stored both ways

  A parallel has no direction. Both `(a, b)` and `(b, a)` are written so that
  `Relations.related/1` finds it from either end without every caller remembering to check
  twice — the kind of thing that is silently wrong exactly half the time.
  """

  use Mix.Task

  alias Pramana.Relations

  @switches [dry_run: :boolean, min_full: :integer]

  # Three curated full parallels is the point where a shared-passage count starts to say
  # something about the works rather than about two discourses. See the moduledoc: the
  # median pair shares two.
  @default_min_full 3

  # At and above this, the pair shares enough material that "these are versions of the
  # same thing" is the natural reading — T0099/T0100 sit at 736.
  @probable_at 10

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    min_full = Keyword.get(opts, :min_full, @default_min_full)
    dry_run? = Keyword.get(opts, :dry_run, false)

    pairs = candidate_pairs(min_full)

    Mix.shell().info("  #{length(pairs)} work pair(s) at >= #{min_full} full parallels")

    if dry_run? do
      Enum.each(pairs, fn p ->
        Mix.shell().info(
          "    #{p.a} <-> #{p.b}   full #{p.full}  resembling #{p.resembling}  " <>
            "(#{confidence(p.full)})"
        )
      end)

      Mix.shell().info("\n  --dry-run: nothing written")
    else
      written = Enum.reduce(pairs, 0, fn p, acc -> acc + write_pair(p) end)
      Mix.shell().info("  wrote #{written} relation row(s) (both directions per pair)")
    end
  end

  defp candidate_pairs(min_full) do
    sql = """
    SELECT least(p.source_work_id, p.target_work_id)    AS a,
           greatest(p.source_work_id, p.target_work_id) AS b,
           count(*) FILTER (WHERE p.relation = 'full')       AS full_n,
           count(*) FILTER (WHERE p.relation = 'resembling') AS resembling_n
    FROM text_parallels p
    WHERE p.source_work_id IS NOT NULL
      AND p.target_work_id IS NOT NULL
      AND p.source_work_id <> p.target_work_id
      AND p.relation IN ('full', 'resembling')
      -- BOTH ENDS CHINESE. Pāli↔Chinese parallels are the majority of this table and
      -- they are already served by `get_parallels`; asserting them as work-level
      -- relations would duplicate that and invite exactly the reading `Compare` refuses,
      -- where a Pāli sutta looks like a version of a Chinese one. The gap #23 needs is
      -- Chinese↔Chinese.
      --
      -- Identified by SOURCE, not by an id prefix: `greatest('T0210','thag17.3')` is the
      -- Pāli id, so a `LIKE 'T%'` test passes on the wrong end of the pair. `EXISTS`
      -- rather than a join, because a work may have several witnesses and joining would
      -- multiply the passage counts this whole decision rests on.
      AND EXISTS (
        SELECT 1 FROM texts t
        WHERE t.work_id = p.source_work_id AND t.source_id = 'cbeta'
      )
      AND EXISTS (
        SELECT 1 FROM texts t
        WHERE t.work_id = p.target_work_id AND t.source_id = 'cbeta'
      )
    GROUP BY 1, 2
    HAVING count(*) FILTER (WHERE p.relation = 'full') >= $1
    ORDER BY 3 DESC
    """

    %{rows: rows} = Pramana.Repo.query!(sql, [min_full])

    Enum.map(rows, fn [a, b, full, resembling] ->
      %{a: a, b: b, full: full, resembling: resembling}
    end)
  end

  defp write_pair(pair) do
    evidence = %{
      "full_parallels" => pair.full,
      "resembling_parallels" => pair.resembling,
      "derived_from" => "text_parallels",
      "curated_by" => "suttacentral"
    }

    [{pair.a, pair.b}, {pair.b, pair.a}]
    |> Enum.count(fn {source, target} ->
      case Relations.assert(%{
             source_work_id: source,
             target_work_id: target,
             relation: "parallel_of",
             method: "catalogue",
             confidence: confidence(pair.full),
             scope: "whole_work",
             evidence: evidence
           }) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    end)
  end

  defp confidence(full) when full >= @probable_at, do: "probable"
  defp confidence(_full), do: "uncertain"
end
