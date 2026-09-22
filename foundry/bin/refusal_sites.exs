# How many of the kernel's refusals can the guard mutation sweep actually neutralise?
#
# The sweep's population is every non-definition `require_*(` CALL site. A refusal written
# any other way is outside it, and `EVIDENCE-TOOLS.md` says so — but said it without a
# denominator, and the first denominator recorded was wrong: "9 inline refusals across 7
# handlers" counted only the sites inside `do_transition` clauses and missed everything in
# the envelope pipeline and the state builders. Counting by eye is how that happens.
#
#   cd foundry
#   elixir bin/refusal_sites.exs
#
# Every `{:error, :atom}` in `kernel.ex` is attributed to its enclosing `defp`. A site
# inside a `require_*` definition is reachable by the sweep, because the sweep neutralises
# the CALLS to that definition. Every other site is not: there is no `require_*(` call to
# neutralise, so no mutation trial exists for it and a clean sweep says nothing about it.
#
# What this cannot see, so it is not mistaken for the whole answer:
#
#   - A refusal that is not spelled `{:error, :atom}` on one line. A tuple built across
#     lines, or returned from a helper that computes the atom, is invisible here. That is
#     the same one-of-several-spellings blind spot that hid `:unknown_entity_kind` from the
#     declared-reason inventory for three reviews.
#   - Whether any site is REACHABLE. `r4_guard_reachability_test.exs` answers that, keyed
#     by atom. A site counted here may be dead.
#   - Whether a test exercises a site. Nothing but the sweep answers that, which is the
#     whole point: for the sites this script reports as outside, nothing does.
#
# It also does not distinguish two sites sharing one atom. `:ticket_terminal` is raised
# both by `refuse_terminal_ticket/2` in the pipeline and inline in
# `do_transition("cancellation_requested", ...)`, and guard reachability cannot tell them
# apart — that limit is recorded in EVIDENCE-TOOLS.

kernel = "lib/pramana_foundry/workflow/kernel.ex"
lines = kernel |> File.read!() |> String.split("\n")

defs =
  lines
  |> Enum.with_index(1)
  |> Enum.flat_map(fn {line, n} ->
    case Regex.run(~r/^  defp? (\w+)/, line) do
      [_, name] -> [{n, name}]
      nil -> []
    end
  end)

owner = fn n ->
  defs |> Enum.take_while(fn {at, _} -> at <= n end) |> List.last() |> then(&(&1 && elem(&1, 1)))
end

sites =
  lines
  |> Enum.with_index(1)
  |> Enum.flat_map(fn {line, n} ->
    ~r/\{:error,\s*:(\w+)\}/
    |> Regex.scan(line)
    |> Enum.map(fn [_, atom] -> {n, owner.(n), atom} end)
  end)

# Red control, per rule 1. A scanner whose regex has drifted reports zero sites outside the
# population — a clean, confident result meaning "the sweep sees everything", which is the
# opposite of the truth. Two sites are known to exist by line number; require them.
known = [{393, "cancellation_requested inline if"}, {217, "refuse_terminal_ticket"}]
missing = Enum.reject(known, fn {line, _} -> Enum.any?(sites, fn {n, _, _} -> n == line end) end)

if missing != [] do
  IO.puts(:stderr, "RED CONTROL FAILED: known refusal sites not found: #{inspect(missing)}")
  IO.puts(:stderr, "The scanner's regex no longer matches how this kernel spells a refusal.")
  System.halt(1)
end

IO.puts("red control passed: both known refusal sites located\n")

{in_guards, outside} =
  Enum.split_with(sites, fn {_, fun, _} -> fun && String.starts_with?(fun, "require_") end)

IO.puts("{:error, :atom} sites in #{kernel}: #{length(sites)}")
IO.puts("  inside require_* definitions, so reachable by the sweep: #{length(in_guards)}")
IO.puts("  outside, so NO mutation trial exists for them:           #{length(outside)}\n")

outside
|> Enum.group_by(fn {_, fun, _} -> fun end)
|> Enum.sort_by(fn {_, group} -> -length(group) end)
|> Enum.each(fn {fun, group} ->
  atoms = group |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort()

  IO.puts(
    "  #{String.pad_trailing(fun || "(no enclosing defp)", 26)} #{length(group)}  #{Enum.join(atoms, ", ")}"
  )
end)

handlers = Enum.filter(outside, fn {_, fun, _} -> fun == "do_transition" end)

IO.puts(
  "\nof those, #{length(handlers)} are inline in do_transition clauses; " <>
    "#{length(outside) - length(handlers)} are in the envelope pipeline and the state builders"
)
