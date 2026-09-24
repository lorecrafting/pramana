# From the repository root: mix run --no-start bench/evidence_scaling.exs
# Pure parser/interval/output work: no database, corpus, providers or server.
# Median of five warmed samples. Report scaling, not hardware-specific pass/fail.
measure = fn fun ->
  fun.()

  samples =
    for _ <- 1..5 do
      :erlang.garbage_collect()
      {elapsed, _} = :timer.tc(fun)
      elapsed
    end

  samples |> Enum.sort() |> Enum.at(2)
end

IO.puts(
  "citations,bytes,occurrences_us,bare_occurrences_us,disjoint_conflicts_us,nested_conflicts_us,edits_us"
)

for count <- [500, 1_000, 2_000, 4_000] do
  token = "[pramana:cbeta.T:T0262_001@p0001a01]\n"
  text = String.duplicate(token, count)
  occurrences = Pramana.Guard.occurrences(text)
  true = length(occurrences) == count

  scopes =
    Enum.map(occurrences, fn o ->
      {o.citation_range.byte_start, o.citation_range.byte_end, o.urn_range.byte_start}
    end)

  nested = for n <- 1..count, do: {0, n + 1, n}

  edits =
    Enum.map(occurrences, fn o ->
      %{range: o.citation_range, before: String.trim_trailing(token), after: ""}
    end)

  true = Pramana.EvidenceInput.apply_edits(text, edits) == String.duplicate("\n", count)
  parse = measure.(fn -> Pramana.Guard.occurrences(text) end)
  bare = String.duplicate("pramana:cbeta.T:T0262_001@p0001a01 漢\n", count)
  bare_parse = measure.(fn -> Pramana.Guard.occurrences(bare) end)
  disjoint = measure.(fn -> Pramana.Repair.Intervals.conflicts(scopes, scopes) end)
  nested_time = measure.(fn -> Pramana.Repair.Intervals.conflicts(nested, nested) end)
  render = measure.(fn -> Pramana.EvidenceInput.apply_edits(text, edits) end)
  IO.puts("#{count},#{byte_size(text)},#{parse},#{bare_parse},#{disjoint},#{nested_time},#{render}")
end
