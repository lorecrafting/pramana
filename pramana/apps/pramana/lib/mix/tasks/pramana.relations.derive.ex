defmodule Mix.Tasks.Pramana.Relations.Derive do
  @shortdoc "Derives commentary→root relations from work titles"

  @moduledoc """
  Populates `work_relations` deterministically from titles.

      mix pramana.relations.derive          # writes
      mix pramana.relations.derive --dry-run

  Chinese commentary titles usually contain the title of the work they explain:
  大方廣圓覺修多羅了義經略疏 comments on 大方廣圓覺修多羅了義經, 仁王護國般若波羅蜜多經疏 on
  仁王護國般若波羅蜜多經. Containment is checkable, so this is derived rather than guessed —
  `CLAUDE.md` invariant #5: deterministic first, LLM only for the residual.

  ## What it deliberately does not claim

  Recorded as `method: title_match` with `confidence: probable`, never `certain`. A
  title is strong evidence and not proof: 大般涅槃經疏 could in principle gloss a different
  text of the same name.

  **Ambiguity is recorded, not resolved.** 金剛般若波羅蜜經破取著不壞假名論 matches all three
  surviving Chinese translations of the Diamond Sūtra (T0235, T0236a, T0236b). It really
  does comment on "the Diamond Sūtra"; *which* translation is a genuine scholarly
  question. Picking one would be inventing an answer, so all candidates are recorded and
  the count is carried in `evidence`, letting a reader see the ambiguity.

  Only the **longest** matching root title is kept per candidate, so a commentary on
  金剛般若波羅蜜經 is not also linked to a shorter title that happens to be a substring of it.

  ## What a work may be found to explain depends on what it is

  This looked for a `text_role: root` target whatever the source was, until 2026-09-02.
  That is a claim about the literature — *only scripture is commented on* — and the
  Taishō's own division table, which `Pramana.Taisho.Divisions` already holds and
  validates, contradicts it:

      1816-1850  論疏部  Śāstra exegesis  ->  subcommentary
      1536-1563  毘曇部  Abhidharma       ->  treatise
      1564-1578  中觀部  Madhyamaka       ->  treatise
      1579-1627  瑜伽部  Yogācāra         ->  treatise

  **論疏部 is a whole division whose purpose is commenting on 論**, and every 論 division is
  `treatise` — so a single global `["root"]` made every subcommentary in the corpus
  unlinkable, silently. `T1830` 成唯識論述記 contains 成唯識論 literally and was found by
  nothing. `Pramana.Relations.may_explain/1` now maps each source role to the roles it may
  explain, and the containment test is unchanged: this widens what is compared, never how.

  It matters beyond this task. `Pramana.Quotations.Roots` restricted its partners the same
  way and did not merely miss those works — it proposed root scripture for them instead,
  because filtering out the right answer leaves the runner-up looking like the answer.
  Rule 75. Links found here are also the only ground truth that rule can be scored
  against, so this is the end that has to move first.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Bake
  alias Pramana.Corpus.Work
  alias Pramana.Derivations
  alias Pramana.Relations
  alias Pramana.Repo

  @switches [dry_run: :boolean, min_title: :integer]

  # Below this, a title is too generic for containment to mean anything.
  #
  # **3, calibrated 2026-09-02 by censusing what each floor admits** — not sampling it: the
  # populations are small enough to read entirely. At 4 and at 3 every admitted pair is
  # correct. At 2 they are not: `人本欲生經註` matches `生經` (its root is 人本欲生經) and
  # `彌勒上生經宗要` matches it too. So 3 is the lowest value admitting no error, which is
  # how `docs/COMMENTARY.md` set the alignment density floor.
  #
  # It was 5, and that silently excluded 成唯識論 — four characters — so the four great
  # 成唯識論 commentaries `T1830`-`T1833` were unfindable by a second constant even after
  # `Relations.may_explain/1` fixed the first. A generic-title guard and a role restriction
  # are different questions and both were answering "no".
  @default_min_title 3

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    min_title = Keyword.get(opts, :min_title, @default_min_title)
    receipt = begin_receipt(opts[:dry_run], min_title)

    sources = load(Relations.explanatory_roles(), 0)

    by_role =
      Relations.explanatory_roles()
      |> Enum.flat_map(&Relations.may_explain/1)
      |> Enum.uniq()
      |> load(min_title)
      |> Enum.group_by(& &1.role)

    matches =
      sources
      |> Enum.flat_map(&candidates(&1, targets_for(&1, by_role)))
      |> Enum.group_by(& &1.source_work_id)

    report(matches, opts[:dry_run])

    unless opts[:dry_run] do
      stats = write(matches)
      Derivations.finish_run!(receipt, stats)
    end
  end

  defp begin_receipt(true, _min_title), do: nil

  defp begin_receipt(false, min_title) do
    Derivations.begin_run(
      "relations_title",
      Bake.current_id(),
      %{"mode" => "full"},
      %{"min_title" => min_title}
    )
  end

  # `Pramana.Relations.may_explain/1` owns this, because `Pramana.Quotations.Roots` needs
  # the same answer and a second copy is how the first one goes stale.
  defp targets_for(%{role: role}, by_role) do
    role
    |> Relations.may_explain()
    |> Enum.flat_map(&Map.get(by_role, &1, []))
  end

  defp load(roles, min_title) do
    Repo.all(
      from w in Work,
        where: w.text_role in ^roles and not is_nil(w.title),
        select: %{id: w.id, title: w.title, role: w.text_role}
    )
    |> Enum.filter(&(String.length(&1.title) >= min_title))
  end

  # `targets`, not `roots`: since 2026-09-02 a subcommentary's target is a treatise, and a
  # name that still said `root` would be the old premise surviving as vocabulary.
  defp candidates(work, targets) do
    targets
    |> Enum.filter(fn target ->
      target.id != work.id and String.contains?(work.title, target.title) and
        work.title != target.title
    end)
    |> keep_longest()
    |> Enum.map(fn target ->
      %{
        source_work_id: work.id,
        target_work_id: target.id,
        source_title: work.title,
        target_title: target.title,
        relation: relation_for(work.role)
      }
    end)
  end

  # A commentary on 金剛般若波羅蜜經 also contains 般若波羅蜜經 as a substring. Keeping only
  # the longest match stops one real link becoming several spurious ones — and it is what
  # makes a 3-character floor safe: 成唯識論述記 matches both 成唯識論 and 唯識論, and only
  # the first survives.
  defp keep_longest([]), do: []

  defp keep_longest(matches) do
    longest = matches |> Enum.map(&String.length(&1.title)) |> Enum.max()
    Enum.filter(matches, &(String.length(&1.title) == longest))
  end

  defp relation_for("subcommentary"), do: "subcommentary_of"
  defp relation_for(_), do: "comments_on"

  defp write(matches) do
    {ok, failed} =
      matches
      |> Enum.flat_map(fn {_source, candidates} ->
        ambiguity = length(candidates)
        Enum.map(candidates, &{&1, ambiguity})
      end)
      |> Enum.reduce({0, 0}, fn {match, ambiguity}, {ok, failed} ->
        attrs = %{
          source_work_id: match.source_work_id,
          target_work_id: match.target_work_id,
          relation: match.relation,
          method: "title_match",
          # Strong evidence, not proof — and weaker still when several works share the
          # matched title.
          confidence: if(ambiguity == 1, do: "probable", else: "uncertain"),
          evidence: %{
            "source_title" => match.source_title,
            "matched_title" => match.target_title,
            "candidates" => ambiguity
          }
        }

        case Relations.assert(attrs) do
          {:ok, _} -> {ok + 1, failed}
          {:error, _} -> {ok, failed + 1}
        end
      end)

    Mix.shell().info(
      "\n  wrote #{ok} relation(s)#{if failed > 0, do: ", #{failed} failed", else: ""}"
    )

    %{
      "failures" => failed,
      "assertions_succeeded" => ok,
      "assertions_attempted" => ok + failed
    }
  end

  defp report(matches, dry_run?) do
    total = matches |> Map.values() |> List.flatten() |> length()
    ambiguous = Enum.count(matches, fn {_k, v} -> length(v) > 1 end)

    Mix.shell().info("""

    #{if dry_run?, do: "DRY RUN — nothing written", else: "deriving relations from titles"}

      works with a match:      #{map_size(matches)}
      relations:               #{total}
      ambiguous (>1 target):   #{ambiguous}   ← recorded as `uncertain`, not resolved
    """)

    matches
    |> Enum.sort_by(fn {_k, v} -> -length(v) end)
    |> Enum.take(5)
    |> Enum.each(fn {source, candidates} ->
      first = hd(candidates)
      targets = Enum.map_join(candidates, ", ", & &1.target_work_id)
      Mix.shell().info("    #{source} #{first.source_title}  →  #{targets}")
    end)
  end
end
