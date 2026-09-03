defmodule Mix.Tasks.Pramana.Derge.Relations do
  @shortdoc "Links Tibetan commentaries to the works they explain, from their titles"

  @moduledoc """
      mix pramana.derge.relations           # report only, writes nothing
      mix pramana.derge.relations --write

  **41 of 3,923 commentarial works in this corpus reach a root, and none of them are
  Tibetan.** `resolve_root/2` walks a chain to depth 10 and `get_commentaries` is a live
  MCP tool, so the capability a reader wants — from a sūtra to its commentary to the
  subcommentary on that — is built and exposed and has almost nothing to walk.

  `mix pramana.relations.derive` cannot fill it, because it matches the way Chinese titles
  work: a commentary's title *contains* its root's. Tibetan shares a **stem** and differs
  by genre suffix, so neither title contains the other. `Pramana.Derge.Genre` reads the
  suffix; this walks the families it finds.

  ## The parent is the longest title this one extends, not the family's root

      toh4210  ཚད་མ་རྣམ་འགྲེལ་གྱི་ཚིག་ལེའུར་བྱས་པ       Pramāṇavārttika-kārikā
      toh4221  ཚད་མ་རྣམ་འགྲེལ་གྱི་རྒྱན                  its alaṃkāra
      toh4222  ཚད་མ་རྣམ་འགྲེལ་གྱི་རྒྱན་གྱི་འགྲེལ་བཤད     a ṭīkā on the alaṃkāra

  `toh4222` explains `toh4221`. Assigning every family member to the root would assert
  something its own title denies, so the most specific parent wins and the relation is
  `subcommentary_of` when that parent is itself a commentary.

  ## What it will not claim

  `method: title_match`, `confidence: probable` — and `uncertain` when several works are
  equally good parents, with the count carried in `evidence`. That follows
  `mix pramana.relations.derive`: ambiguity is **recorded, not resolved**, because picking
  one of two equally-named roots is inventing an answer.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Derge.Genre
  alias Pramana.Relations
  alias Pramana.Repo

  @switches [write: :boolean, limit: :integer]
  @sources ~w(derge derge-tengyur)

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    works = load()
    matches = matches(works)

    report(works, matches, opts)

    if opts[:write], do: write(matches)
  end

  defp load do
    Repo.all(
      from w in Work,
        join: t in Text,
        on: t.work_id == w.id,
        where: t.source_id in ^@sources and not is_nil(w.title_original),
        distinct: w.id,
        select: %{id: w.id, title: w.title_original}
    )
    |> Enum.map(&Map.put(&1, :comparable, Genre.comparable(&1.title)))
  end

  # A candidate is a work whose title names a commentarial genre. Its parent is the
  # longest OTHER title it extends — which is its stem when nothing more specific exists,
  # and something deeper in the chain when it does.
  defp matches(works) do
    by_comparable = Enum.group_by(works, & &1.comparable)
    by_stem = Enum.group_by(works, &stem_of/1)

    # The tuple pattern is the filter: a generator whose pattern does not match drops the
    # element, so `:none` never reaches the body and needs no test of its own.
    for work <- works,
        {stem, genre, depth} <- [Genre.classify(work.title)],
        parents = parents_of(work, stem, depth, by_comparable, by_stem),
        parents != [],
        into: %{} do
      {work.id, Enum.map(parents, &match(work, &1, genre, depth))}
    end
  end

  # A work's family key: its stem when it names a genre, otherwise its whole title. The
  # root of a family usually names one too — `ཚིག་ལེའུར་བྱས་པ`, the verses — so a family
  # cannot be found by title alone.
  defp stem_of(work) do
    case Genre.classify(work.title) do
      {stem, _, _} -> stem
      :none -> work.comparable
    end
  end

  # TWO RULES, and the second is why the flagship case needed it.
  #
  # **The title this one extends**, longest first: `ཚད་མ་རྣམ་འགྲེལ་གྱི་རྒྱན་གྱི་འགྲེལ་བཤད`
  # extends `ཚད་མ་རྣམ་འགྲེལ་གྱི་རྒྱན`, so the ṭīkā is attached to the alaṃkāra rather than
  # to the root three layers below it.
  #
  # **Failing that, a shallower work in the same family.** `ཚད་མ་རྣམ་འགྲེལ་གྱི་འགྲེལ་པ`
  # extends nothing — the root it explains is
  # `ཚད་མ་རྣམ་འགྲེལ་གྱི་ཚིག་ལེའུར་བྱས་པ`, which is LONGER than the shared stem because the
  # root names its own genre. Prefix matching alone finds no parent for the whole
  # Pramāṇavārttika chain, which is the literature this system is named after.
  defp parents_of(work, stem, depth, by_comparable, by_stem) do
    case extended_titles(work, stem, by_comparable) do
      [] -> shallower_siblings(work, stem, depth, by_stem)
      parents -> parents
    end
  end

  defp extended_titles(work, stem, by_comparable) do
    by_comparable
    |> Enum.filter(fn {comparable, _} ->
      comparable != work.comparable and String.starts_with?(stem, comparable)
    end)
    |> Enum.sort_by(fn {comparable, _} -> -String.length(comparable) end)
    |> case do
      [] -> []
      [{_longest, parents} | _] -> Enum.reject(parents, &(&1.id == work.id))
    end
  end

  # The nearest layer below this one, not every layer below: a ṭīkā in a family holding
  # both a vṛtti and the root verses explains the vṛtti.
  defp shallower_siblings(work, stem, depth, by_stem) do
    by_stem
    |> Map.get(stem, [])
    |> Enum.reject(&(&1.id == work.id))
    |> Enum.map(&{&1, sibling_depth(&1)})
    |> Enum.filter(fn {_w, d} -> d != nil and d < depth end)
    |> case do
      [] ->
        []

      candidates ->
        nearest = candidates |> Enum.map(&elem(&1, 1)) |> Enum.max()
        for {w, d} <- candidates, d == nearest, do: w
    end
  end

  defp sibling_depth(work) do
    case Genre.classify(work.title) do
      {_, _, d} -> d
      :none -> 0
    end
  end

  defp match(work, parent, genre, depth) do
    parent_depth =
      case Genre.classify(parent.title) do
        {_, _, d} -> d
        :none -> nil
      end

    %{
      source_work_id: work.id,
      target_work_id: parent.id,
      relation: Genre.relation_to(parent_depth),
      source_title: work.title,
      target_title: parent.title,
      genre: genre,
      depth: depth
    }
  end

  defp write(matches) do
    {ok, failed} =
      matches
      |> Enum.flat_map(fn {_id, candidates} ->
        Enum.map(candidates, &{&1, length(candidates)})
      end)
      |> Enum.reduce({0, 0}, fn {m, ambiguity}, {ok, failed} ->
        attrs = %{
          source_work_id: m.source_work_id,
          target_work_id: m.target_work_id,
          relation: m.relation,
          method: "title_match",
          confidence: if(ambiguity == 1, do: "probable", else: "uncertain"),
          evidence: %{
            "source_title" => m.source_title,
            "matched_title" => m.target_title,
            "genre" => Atom.to_string(m.genre),
            "candidates" => ambiguity,
            "rule" => "tibetan_stem_and_genre_suffix"
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

  defp report(works, matches, opts) do
    classified = Enum.count(works, &(Genre.classify(&1.title) != :none))
    edges = matches |> Map.values() |> List.flatten()
    ambiguous = Enum.count(matches, fn {_k, v} -> length(v) > 1 end)
    by_relation = Enum.frequencies_by(edges, & &1.relation)

    Mix.shell().info("""

    #{if opts[:write], do: "linked Tibetan commentaries to their roots", else: "DRY RUN — nothing written; add --write"}

      Tibetan works with a title:   #{length(works)}
      naming a commentarial genre:  #{classified}
      with a parent found:          #{map_size(matches)}
      relations:                    #{length(edges)}   #{inspect(by_relation)}
      ambiguous (>1 parent):        #{ambiguous}   ← recorded as `uncertain`, not resolved

    #{sample(edges, opts)}
    """)
  end

  defp sample(edges, opts) do
    edges
    |> Enum.take(Keyword.get(opts, :limit, 8))
    |> Enum.map_join("\n", fn m ->
      "    #{m.source_work_id} #{m.source_title}\n      -#{m.relation}->  #{m.target_work_id} #{m.target_title}"
    end)
  end
end
