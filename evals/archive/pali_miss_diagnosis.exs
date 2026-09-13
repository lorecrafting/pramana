# WHERE DO THE 68 PĀLI RETRIEVAL MISSES ACTUALLY FAIL?
#
# `retrieval/pali` is 82/150 — the largest block of failures in the corpus, and undiagnosed.
# The same probe was run for Tibetan (#10) and answered the question that decides what to
# build: a reranker can only reorder the candidate pool, so it cannot help a case whose gold
# passage never appears in it. Tibetan came back 14% reachable, 48% unreachable.
#
# Classify each MISS by where the gold URN sits at depth 200:
#   rank 11-200  -> a reranker could fix it (mis-ranked, but retrieved)
#   absent       -> recall failure; no reranker helps

alias Pramana.Embed.Serving
alias Pramana.Evals
alias Pramana.Retrieval.Hybrid

serving = Serving.name()
{:ok, cases} = Evals.load("evals/gold")

pali =
  cases
  |> Enum.filter(&(&1.type == :retrieval and &1.tradition == "pali"))

IO.puts("pali retrieval cases: #{length(pali)}")

results =
  pali
  |> Enum.with_index(1)
  |> Enum.map(fn {kase, i} ->
    if rem(i, 25) == 0, do: IO.write("  #{i}/#{length(pali)}\n")

    {:ok, res} =
      Hybrid.search(kase.query,
        limit: 200,
        serving: serving,
        coverage: false
      )

    rank =
      res.results
      |> Enum.with_index(1)
      |> Enum.find_value(fn {hit, r} ->
        if Enum.any?(kase.expect_urns, &Evals.covers?(hit.urn, &1)), do: r
      end)

    {kase, rank}
  end)

hits_at_10 = Enum.count(results, fn {_, r} -> r != nil and r <= 10 end)
reachable = Enum.count(results, fn {_, r} -> r != nil and r > 10 end)
absent = Enum.count(results, fn {_, r} -> is_nil(r) end)
total = length(results)

IO.puts("""

  gold at rank <= 10    #{hits_at_10}  (#{Float.round(hits_at_10 * 100 / total, 1)}%)  already a hit
  gold at rank 11-200   #{reachable}  (#{Float.round(reachable * 100 / total, 1)}%)  a RERANKER could fix
  gold absent from 200  #{absent}  (#{Float.round(absent * 100 / total, 1)}%)  RECALL failure
""")

ranks =
  results |> Enum.filter(fn {_, r} -> r != nil and r > 10 end) |> Enum.map(&elem(&1, 1)) |> Enum.sort()

if ranks != [] do
  IO.puts("  mis-ranked gold sits at: #{inspect(ranks)}")
  IO.puts("  median #{Enum.at(ranks, div(length(ranks), 2))}")
end

IO.puts("\n  a perfect reranker would take pali from #{hits_at_10}/#{total} to at most #{hits_at_10 + reachable}/#{total}")
