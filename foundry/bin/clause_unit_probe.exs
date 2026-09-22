# What does the "57 asserted / 57 uncited" coverage number actually count?
#
# EV-2's thesis is that the clause unit in `r4_coverage_test.exs` is punctuation rather than
# semantics: `String.split(~r/;|(?<=\.)\s+/)` decides where an obligation begins, and a
# fragment counts as asserted if it CONTAINS any cited quote. This measures what that costs,
# so the annotation pass that replaces it starts from numbers rather than from the argument.
#
#   cd foundry
#   elixir bin/clause_unit_probe.exs
#
# Three questions, each reported with its denominator per rule 2:
#
#   ORPHANS   outcome text that no @clauses, @uncited or @partial entry accounts for. Each
#             shares a punctuation fragment with an asserted quote, so the fragment counts
#             as covered and the obligation beside it is invisible. This flatters coverage.
#   OVERLAPS  text claimed by two entries at once - typically a cited quote spanning a `;`
#             while the clause after the `;` is separately recorded as uncited. The same
#             obligation is then counted in both totals.
#   REACH     how much of each outcome cell any entry accounts for at all.
#
# This probe reads the two maps out of the test's own source and evaluates them, rather than
# transcribing them, because a third hand-maintained copy of the contract is the defect being
# measured. It becomes obsolete the moment EV-2 lands: with IDs, an obligation is asserted or
# it is not, and none of these three questions can be asked.
#
# What it cannot see: whether a scenario's assertions actually discharge the clause it cites.
# Citing pins the transcription to the contract's words, never the assertion to the clause -
# that is the human step, and the four stale @uncited entries this probe finds were confirmed
# by reading each scenario, not by running this.

Code.require_file("test/support/r4_rows.ex")
alias PramanaFoundry.Test.R4Rows

test_source = File.read!("test/pramana_foundry/workflow/r4_coverage_test.exs")

literal = fn name ->
  start = :binary.match(test_source, "@#{name} %{") |> elem(0)
  open = :binary.match(binary_part(test_source, start, byte_size(test_source) - start), "%{")
  from = start + elem(open, 0)
  rest = binary_part(test_source, from, byte_size(test_source) - from)
  {stop, _} = :binary.match(rest, "\n  }")
  {value, _} = Code.eval_string(binary_part(rest, 0, stop + 4))
  value
end

clauses = literal.("clauses")
uncited = literal.("uncited")
partial = literal.("partial")

entries =
  Enum.flat_map(clauses, fn {row, qs} -> Enum.map(qs, &{row, &1, :cited}) end) ++
    Enum.flat_map(uncited, fn {row, qs} -> Enum.map(qs, &{row, &1, :uncited}) end) ++
    Enum.flat_map(partial, fn {row, note} ->
      ~r/"([^"]{12,})"/ |> Regex.scan(note) |> Enum.map(&{row, List.last(&1), :partial})
    end)

anchor_check = fn set ->
  for {row, quote, _kind} <- set,
      outcome = R4Rows.outcome(row),
      not (is_binary(outcome) and String.contains?(outcome, quote)),
      do: {row, quote}
end

# Red control, per rule 1. A matcher that silently fails reports zero orphans, zero overlaps
# and zero unanchored quotes - a clean, confident, entirely vacuous result, which is how five
# mechanisms in this subcommit shipped. Feed it a quote that is certainly not in the contract
# and require it to say so.
control = [{List.first(R4Rows.ids()), "no contract outcome cell contains this", :cited}]

if anchor_check.(control) == [] do
  IO.puts(:stderr, "RED CONTROL FAILED: a quote absent from the contract reported as anchored.")
  System.halt(1)
end

IO.puts("red control passed: a quote absent from the contract is reported\n")

unanchored = anchor_check.(entries)

IO.puts(
  "entries: #{length(entries)} (#{map_size(clauses)} rows cited, #{map_size(uncited)} recorded uncited)"
)

IO.puts("unanchored quotes: #{length(unanchored)}\n")

Enum.each(unanchored, fn {row, q} -> IO.puts("  UNANCHORED #{row}: #{inspect(q)}") end)

spans =
  Map.new(R4Rows.ids(), fn row ->
    outcome = R4Rows.outcome(row) || ""

    row_spans =
      for {^row, quote, kind} <- entries,
          {at, len} <- :binary.matches(outcome, quote),
          do: {at, at + len, kind, quote}

    {row, Enum.sort(row_spans)}
  end)

overlaps =
  for {row, row_spans} <- spans,
      [{a_at, a_end, a_kind, a_q}, {b_at, b_end, b_kind, b_q}] <-
        Enum.chunk_every(row_spans, 2, 1, :discard),
      b_at < a_end,
      do: {row, {a_kind, a_at, a_end, a_q}, {b_kind, b_at, b_end, b_q}}

orphans =
  for row <- R4Rows.ids(),
      outcome = R4Rows.outcome(row) || "",
      outcome != "",
      covered =
        Enum.reduce(spans[row], MapSet.new(), fn {a, b, _, _}, acc ->
          MapSet.union(acc, MapSet.new(a..(b - 1)))
        end),
      run <-
        0..(String.length(outcome) - 1)
        |> Enum.chunk_by(&MapSet.member?(covered, &1))
        |> Enum.reject(&MapSet.member?(covered, List.first(&1)))
        |> Enum.map(fn idx ->
          outcome
          |> String.slice(List.first(idx), length(idx))
          |> String.replace(~r/^[\s;.,]+|[\s;.,]+$/, "")
        end),
      String.length(run) >= 12,
      do: {row, run}

total = R4Rows.ids() |> Enum.map(&String.length(R4Rows.outcome(&1) || "")) |> Enum.sum()

reach =
  R4Rows.ids()
  |> Enum.map(fn row ->
    spans[row]
    |> Enum.reduce(MapSet.new(), fn {a, b, _, _}, acc ->
      MapSet.union(acc, MapSet.new(a..(b - 1)))
    end)
    |> MapSet.size()
  end)
  |> Enum.sum()

IO.puts(
  "REACH: #{reach} of #{total} outcome characters are inside some entry (#{round(100 * reach / total)}%)\n"
)

IO.puts("ORPHANS: #{length(orphans)} substantive runs no entry accounts for")

Enum.each(orphans, fn {row, run} -> IO.puts("  #{row}: #{inspect(run)}") end)

IO.puts("\nOVERLAPS: #{length(overlaps)} places where two entries claim the same text")

Enum.each(overlaps, fn {row, {ak, _, _, aq}, {bk, _, _, bq}} ->
  IO.puts("  #{row}")
  IO.puts("    #{ak}: #{inspect(aq)}")
  IO.puts("    #{bk}: #{inspect(bq)}")
end)
