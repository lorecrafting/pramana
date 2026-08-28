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
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Work
  alias Pramana.Relations
  alias Pramana.Repo

  @switches [dry_run: :boolean, min_title: :integer]

  # Below this, a title is too generic for containment to mean anything.
  @default_min_title 5

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    min_title = Keyword.get(opts, :min_title, @default_min_title)

    roots = load(["root"], min_title)
    commentaries = load(["commentary", "subcommentary", "treatise"], 0)

    matches =
      commentaries
      |> Enum.flat_map(&candidates(&1, roots))
      |> Enum.group_by(& &1.source_work_id)

    report(matches, opts[:dry_run])

    unless opts[:dry_run], do: write(matches)
  end

  defp load(roles, min_title) do
    Repo.all(
      from w in Work,
        where: w.text_role in ^roles and not is_nil(w.title),
        select: %{id: w.id, title: w.title, role: w.text_role}
    )
    |> Enum.filter(&(String.length(&1.title) >= min_title))
  end

  defp candidates(work, roots) do
    roots
    |> Enum.filter(fn root ->
      root.id != work.id and String.contains?(work.title, root.title) and
        work.title != root.title
    end)
    |> keep_longest()
    |> Enum.map(fn root ->
      %{
        source_work_id: work.id,
        target_work_id: root.id,
        source_title: work.title,
        target_title: root.title,
        relation: relation_for(work.role)
      }
    end)
  end

  # A commentary on 金剛般若波羅蜜經 also contains 般若波羅蜜經 as a substring. Keeping only
  # the longest match stops one real link becoming several spurious ones.
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
  end

  defp report(matches, dry_run?) do
    total = matches |> Map.values() |> List.flatten() |> length()
    ambiguous = Enum.count(matches, fn {_k, v} -> length(v) > 1 end)

    Mix.shell().info("""

    #{if dry_run?, do: "DRY RUN — nothing written", else: "deriving relations from titles"}

      works with a match:   #{map_size(matches)}
      relations:            #{total}
      ambiguous (>1 root):  #{ambiguous}   ← recorded as `uncertain`, not resolved
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
