defmodule Mix.Tasks.Pramana.Relations.SharedText do
  @shortdoc "Links Chinese commentaries to their roots through the quotation graph"

  @moduledoc """
      mix pramana.relations.shared_text            # report only, writes nothing
      mix pramana.relations.shared_text --write

  **Most commentarial works reach no root** — `mix pramana.doctor` prints the fraction —
  because `mix pramana.relations.derive` can only find one when the title names it. 大智度論
  explains 摩訶般若波羅蜜經 and never says so, and that is the ordinary case rather than the
  awkward one.

  The quotation graph can find those pairs — **not as a citation graph, which it is not**
  (`docs/PROXIES.md`, rule 72), but as a candidate generator, which is what a shared-text
  graph is good for. `Pramana.Quotations.Roots` holds the rule, the counting decision that
  makes it work, and the measurement; this reports and writes.

      T1509 大智度論  ->  T0223 摩訶般若波羅蜜經     654 shared passages, runner-up 12

  ## Options

    * `--write` — assert the proposals. Without it nothing is written and the report is
      the same, which is the point: the counts below are what you are about to commit
    * `--min-passages` — floor on distinct shared passages, default 1
    * `--limit` — how many proposals to print, strongest first, default 10

  ## What it writes, and what it refuses to

  `method: shared_text` — its own value in the enum, because the claim is a different kind
  from `lemma_match`, which names what happens *after* a `comments_on` relation exists.
  See the migration for the argument.

  | band | confidence | measured 2026-09-02 |
  |---|---|---|
  | dominant root family, ≥ 5 shared passages | `probable` | 14 of 17 |
  | dominant root family, fewer | `uncertain` | 6 of 12 |
  | no dominant family — a tie | **not written** | 1 of 5 |

  Those denominators are the whole story and are re-derived on every run by
  `Roots.validate/1` rather than quoted: some of these works are also linked from their
  titles, independently, which is the only ground truth available. **It is small, and it
  has already moved** — the strong band read `13 of 13` until title matching learned to
  reach twelve more works.

  **Written and refused are scored apart**, because a blended figure charges the rule for
  proposals it declines to make and hides whether declining them was right. The refused
  side scoring low is the refusal earning itself.

  A tie is reported and not asserted. That is not a departure from *ambiguity is recorded,
  never resolved* — a 33-way tie at one shared passage is an absence of evidence rather
  than a choice between roots, and per row that band scored 3 of 22 where per work it
  flattered itself at 3 of 4.

  **Only `text_role: commentary` is written**, which is the narrowing this measurement
  earned. No treatise is testable at all, while treatises were 82 of the 171 proposed for
  on 2026-09-02, and the strongest five of them are Sarvāstivāda Abhidharma śāstras aimed
  at the Mahāprajñāpāramitā because both are full of the same list-formulae.

  **Subcommentaries are refused for a different and sharper reason**: 論疏部 explains 論,
  and every 論 division in `Pramana.Taisho.Divisions` is `text_role: treatise`, so the
  partner set excludes by construction the only works a subcommentary can be about. That
  is a wrong constant rather than a missing measurement, and it is shared with
  `mix pramana.relations.derive`. `Pramana.Quotations.Roots` has both tables.

  A work already linked by title is proposed again anyway. `Relations.assert/1` keeps the
  same relation from two methods as two rows, because corroboration is information, and it
  leaves the validation above visible in the data instead of only in this docstring.
  """

  use Mix.Task

  alias Pramana.Bake
  alias Pramana.Derivations
  alias Pramana.Quotations.Roots
  alias Pramana.Relations

  @switches [write: :boolean, min_passages: :integer, limit: :integer]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    min_passages = Keyword.get(opts, :min_passages, 1)
    bake_id = Bake.current_id()
    receipt = begin_receipt(opts[:write], bake_id, min_passages)

    candidates = Roots.candidates(min_passages: min_passages, bake_id: bake_id)
    assertable = Roots.assertable(candidates)

    report(candidates, assertable, opts)

    if opts[:write] do
      stats = write(assertable)
      Derivations.finish_run!(receipt, stats)
    end
  end

  defp begin_receipt(false, _bake_id, _min_passages), do: nil

  defp begin_receipt(true, bake_id, min_passages) do
    Derivations.begin_run(
      "relations_shared_text",
      bake_id,
      %{"mode" => "full"},
      %{"min_passages" => min_passages}
    )
  end

  defp write(assertable) do
    {ok, failed} =
      Enum.reduce(assertable, {0, 0}, fn candidate, {ok, failed} ->
        case Relations.assert(attrs(candidate)) do
          {:ok, _} -> {ok + 1, failed}
          {:error, _} -> {ok, failed + 1}
        end
      end)

    Mix.shell().info(
      "\n  wrote #{ok} relation(s)#{if failed > 0, do: ", #{failed} failed", else: ""}"
    )

    %{
      "failures" => failed,
      "expected_output_count" => ok,
      "assertions_succeeded" => ok,
      "assertions_attempted" => ok + failed
    }
  end

  defp attrs(c) do
    %{
      source_work_id: c.work_id,
      target_work_id: c.target_work_id,
      relation: relation_for(c.text_role),
      method: "shared_text",
      confidence: if(c.band == :strong, do: "probable", else: "uncertain"),
      evidence: %{
        "rule" => "dominant_shared_text_partner_among_root_works",
        # Distinct passage texts, never quotation rows — a root that repeats itself would
        # otherwise outvote the real root. Rule 73.
        "shared_passages" => c.passages,
        "runner_up_passages" => c.runner_up,
        "root_families" => c.families,
        # `T0220a`-`T0220d` are one work. The family decided the winner; the member with
        # the most shared passages is the witness proposed, and the others are here so
        # that choice is visible rather than silent.
        "family" => c.family,
        "family_members" => c.family_members
      }
    }
  end

  defp relation_for("subcommentary"), do: "subcommentary_of"
  defp relation_for(_), do: "comments_on"

  defp report(candidates, assertable, opts) do
    # Excluding this method's own rows: otherwise a re-run after `--write` reports zero
    # new links forever, because it is counting what it wrote last time.
    rooted = Roots.already_rooted(except_method: "shared_text")
    new = Enum.reject(assertable, &MapSet.member?(rooted, &1.work_id))

    Mix.shell().info("""

    #{if opts[:write], do: "linking Chinese commentaries through the quotation graph", else: "DRY RUN — nothing written; add --write"}

      commentarial works sharing text with a root:  #{length(candidates)}
      proposals that may be written:                #{length(assertable)}
      of those, reaching no root today:             #{length(new)}

    #{bands(candidates)}
    #{refusals(candidates)}
    #{validation(candidates)}
    #{sample(assertable, opts)}
    """)
  end

  defp bands(candidates) do
    counts = Enum.frequencies_by(Roots.assertable(candidates), & &1.band)

    """
      WRITTEN — roles #{Enum.join(Roots.assertable_roles(), ", ")}

      band                                          works   confidence
      dominant root family, >= #{Roots.strong_passages()} shared passages     #{pad(Map.get(counts, :strong, 0))}   probable
      dominant root family, fewer                   #{pad(Map.get(counts, :weak, 0))}   uncertain

      one row per work, so per-work and per-row precision are the same number.
    """
  end

  # A refusal is reported with its size AND its reason, because the two refused roles are
  # refused for different reasons and only one of them is fixable by finding ground truth.
  # A candidate that is generated and declined is information; one that was never generated
  # is invisible, and the next session re-derives it.
  defp refusals(candidates) do
    tied = Enum.count(candidates, &(&1.band == :tied))
    by_role = Enum.frequencies_by(candidates, & &1.text_role)

    roles =
      by_role
      |> Enum.reject(fn {role, _} -> role in Roots.assertable_roles() end)
      |> Enum.sort()
      |> Enum.map_join("\n", fn {role, count} ->
        "  role #{String.pad_trailing(role, 41)}#{pad(count)}   #{why(role)}"
      end)

    """
      NOT WRITTEN — derived, and declined

      no dominant root family (a tie)                #{pad(tied)}   absence of evidence, not a choice
    #{roles}

      #{overlap(candidates)} of those are refused twice over, by role and by tie.
    """
  end

  # 論疏部 explains 論, and every 論 division is `text_role: treatise` — so the partner set
  # excludes what a subcommentary is about. A treatise need not be about anything at all.
  defp why("subcommentary"), do: "its roots are treatises, which partners exclude"
  defp why("treatise"), do: "untested, and need not be about another text"
  defp why(_), do: "not an assertable role"

  defp overlap(candidates) do
    Enum.count(candidates, &(&1.band == :tied and &1.text_role not in Roots.assertable_roles()))
  end

  # Re-derived every run against the title-matched links, which are independent evidence.
  # Printed with both numbers because a precision without its denominator is the failure
  # this project is most prone to — rules 22, 44 and 54.
  defp validation(candidates) do
    %{written: written, refused: refused, roles: roles} = Roots.validate(candidates)
    total = written.works + refused.works

    """
      MEASURED against the #{total} of these also linked from their titles — independent
      evidence, and imperfect in a direction that scores this DOWN (`Roots.validate/1`):

    #{side("of what would be WRITTEN", written)}
    #{side("of what is REFUSED — low is the refusal earning itself", refused)}
      #{total} is small. Read each band with its denominator and none of them as a rate.
      By role, the testable works are: #{Enum.map_join(roles, ", ", fn {role, n} -> "#{role} #{n}" end)}.
    """
  end

  # The two sides are never summed. A blended figure charges the rule for proposals it
  # declines to write and hides whether declining them was right.
  defp side(_label, %{works: 0}), do: ""

  defp side(label, %{works: works, correct: correct, bands: bands}) do
    rows =
      Enum.map_join(bands, "\n", fn %{band: band, works: w, correct: c} ->
        "        #{String.pad_trailing(label(band), 44)}#{pad(c)} of #{w}"
      end)

    """
      #{pad(correct)} of #{works} #{label}
    #{rows}
    """
  end

  defp label(:strong), do: "dominant root family, >= #{Roots.strong_passages()} passages"
  defp label(:weak), do: "dominant root family, fewer"
  defp label(:tied), do: "no dominant family (not written)"

  defp pad(n), do: String.pad_leading(to_string(n), 3)

  defp sample(assertable, opts) do
    assertable
    |> Enum.take(Keyword.get(opts, :limit, 10))
    |> Enum.map_join("\n", fn c ->
      "    #{c.work_id} #{c.title}\n" <>
        "      -> #{c.target_work_id} #{c.target_title}   " <>
        "#{c.passages} shared passage(s), runner-up #{c.runner_up || "none"}"
    end)
  end
end
