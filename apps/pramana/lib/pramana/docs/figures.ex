defmodule Pramana.Docs.Figures do
  @moduledoc """
  The corpus figures that documentation is allowed to state, computed from the corpus.

  ## Why this exists

  `CLAUDE.md` says *never write down a number the code computes*, and the documentation
  does it anyway, because a status file whose job is "what is true now" is made of numbers.
  The rule loses to the need. So the numbers stay and stop being written down: they are
  **generated into marked blocks**, and `mix pramana.docs.figures --check` fails when
  regenerating would change one.

  This is `mix format --check-formatted` applied to facts. Nobody is asked to remember;
  the build notices.

  ## What belongs here, and what must never

  **Corpus counts belong.** They drift because the corpus grows, and they drifted five
  times in one week: `work_relations` said 249 when it was 269, `docs/ROADMAP.md` said
  27,254 alignments when there were 72,120, and `docs/PLAN.md` said 17 MCP tools while
  `docs/STATUS.md` said 18 and the directory said 18.

  **Measurements must NOT.** "Retrieval@10 is 74.9%" and "forward order 84.3% over accepted
  pairs" are true *of a date and a method*, not of the corpus, and regenerating them would
  quietly overwrite a record of what was measured with whatever a re-run produced. Those
  keep the other discipline — a statement about the past carries its date — and this module
  is deliberately no help with them.

  The test of whether a figure belongs: **would a second run of the same command change
  it?** A count changes when the corpus grows and should be generated. A measurement
  changes when the method or the sample changes, and then it is a new measurement with a
  new date rather than a stale one.

  ## Reading an empty corpus

  Every figure here is a database count, so a checkout with no bake produces zeroes — and
  a check that rewrote the documentation to zero would be worse than one that never ran.
  `available?/0` says whether there is a corpus to compare against, and the task refuses
  rather than guessing. Same discipline as `Pramana.Coverage`: an absence is stated, not
  inferred.
  """

  import Ecto.Query

  alias Pramana.Repo

  @doc "Whether there is a corpus to read figures from at all."
  @spec available?() :: boolean()
  def available? do
    Repo.aggregate(from(t in "texts"), :count) > 0
  rescue
    _ -> false
  end

  @doc """
  Every generated figure, keyed by the block it belongs to.

  A block is a named region of a document. `corpus` is the table at the top of
  `docs/STATUS.md`; add a key here and a matching marker in a document to grow the set.
  """
  @spec blocks() :: %{String.t() => [{String.t(), String.t()}]}
  def blocks do
    %{"corpus" => corpus(), "relations" => relations(), "derived" => derived()}
  end

  # `Pramana.Coverage.derivations/0` already computes these for `mix pramana.doctor`, and
  # a second copy here is how the first one goes stale — which is the defect this whole
  # module exists for. **Every one of these is a ratio with its denominator**, because a
  # figure without one is the failure this project is most prone to (rules 22, 44, 54).
  defp derived do
    Enum.map(Pramana.Coverage.derivations(), fn d ->
      {d.what, "#{commas(d.done)} of #{commas(d.eligible)} #{d.unit}"}
    end)
  end

  defp corpus do
    [
      {"texts", count("texts")},
      {"segments", count("segments")},
      {"chunks", count("chunks")},
      {"vectors", count("chunk_vectors")},
      {"renderings", count("translations")},
      {"glossary entries", count("glossary_entries")},
      {"quotations", count("quotations")},
      {"MCP tools", mcp_tools()}
    ]
  end

  defp relations do
    by_relation =
      from(r in "work_relations", group_by: r.relation, select: {r.relation, count(r.id)})
      |> Repo.all()
      |> Map.new()

    [
      {"work relations", commas(Enum.sum(Map.values(by_relation)))},
      {"comments_on", commas(Map.get(by_relation, "comments_on", 0))},
      {"subcommentary_of", commas(Map.get(by_relation, "subcommentary_of", 0))},
      {"parallel_of", commas(Map.get(by_relation, "parallel_of", 0))},
      {"commentary alignments", count("commentary_alignments")},
      {"root lines with commentary", count_distinct("commentary_alignments", "root_urn")}
    ]
  end

  # The MCP surface is a directory, not a table, and it is the figure that had two
  # documents disagreeing while the filesystem settled it.
  defp mcp_tools do
    __ENV__.file
    |> Path.join("../../../../../pramana_web/lib/pramana_web/mcp/tools/*.ex")
    |> Path.expand()
    |> Path.wildcard()
    |> length()
    |> commas()
  end

  # Raw SQL because the table name is data here, and `from(x in ^table)` is not a thing
  # Ecto's query macro will take. Every name is a literal in this module, never input.
  defp count(table), do: commas(scalar("SELECT count(*) FROM #{table}"))

  defp count_distinct(table, field),
    do: commas(scalar("SELECT count(DISTINCT #{field}) FROM #{table}"))

  defp scalar(sql) do
    %{rows: [[n]]} = Repo.query!(sql)
    n
  end

  defp commas(n) when is_binary(n), do: n

  defp commas(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
