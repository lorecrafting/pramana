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
# Every `{:error, :atom}` in the reducer (`kernel.ex` and its event-family modules) is
# attributed to its enclosing `defp`/`def`. A site
# inside a `require_*` definition is reachable by the sweep, because the sweep neutralises
# the CALLS to that definition. Every other site is not: there is no `require_*(` call to
# neutralise, so no mutation trial exists for it and a clean sweep says nothing about it.
#
# What this cannot see, so it is not mistaken for the whole answer:
#
#   - A THIRD spelling. Two are matched (see `spellings`) and the red control pins one site of
#     each. A refusal built some other way is still invisible, and this script cannot tell you
#     that it is complete - only that the two known spellings are covered and that a regression
#     in either turns the red control red. The previous version matched one spelling, reported
#     a floor, and put a disclaimer where a measurement belonged; an independent review found
#     the missing spelling, which is what disclaimers cost.
#   - Whether any site is REACHABLE. `r4_guard_reachability_test.exs` answers that, keyed
#     by atom. A site counted here may be dead.
#   - Whether a test exercises a site. Nothing but the sweep answers that, which is the
#     whole point: for the sites this script reports as outside, nothing does.
#
# It also does not distinguish two sites sharing one atom. `:ticket_terminal` is raised
# both by `refuse_terminal_ticket/2` in the pipeline and inline in
# `do_transition("cancellation_requested", ...)`, and guard reachability cannot tell them
# apart — that limit is recorded in EVIDENCE-TOOLS.

# Both files that refuse. `Event.validate/1` refuses in kernel/event.ex, outside the sweep and
# outside this script's original scope - counting one file and calling the answer "the kernel's
# refusals" was the same unstated boundary as counting do_transition clauses and calling it all.
# Since 2026-09-23 the reducer is kernel.ex plus one module per event family under kernel/,
# so the family modules are read too. State stays out, as it always did.
sources =
  ["lib/pramana_foundry/workflow/kernel.ex"
   | Path.wildcard("lib/pramana_foundry/workflow/kernel/**/*.ex")] --
    ["lib/pramana_foundry/workflow/kernel/state.ex"]

lines =
  Enum.flat_map(sources, fn file ->
    file |> File.read!() |> String.split("\n") |> Enum.map(&{file, &1})
  end)

defs =
  lines
  |> Enum.with_index(1)
  |> Enum.flat_map(fn {{file, line}, n} ->
    case Regex.run(~r/^  defp? (\w+)/, line) do
      [_, name] -> [{n, file, Path.basename(file) <> " " <> name}]
      nil -> []
    end
  end)

# The enclosing definition in the SAME file: with one module per family, a module header's
# lines would otherwise be charged to the previous file's last function.
owner = fn n, file ->
  defs
  |> Enum.take_while(fn {at, _, _} -> at <= n end)
  |> Enum.filter(fn {_, f, _} -> f == file end)
  |> List.last()
  |> then(&(&1 && elem(&1, 2)))
end

# TWO spellings, not one. `{:error, :atom}` is the common form; `ok_or(:atom)` builds the tuple
# inside a helper from a variable, so the atom never appears beside `:error` anywhere. The first
# version matched only the common form and reported a floor with a disclaimer. A disclaimer is not
# a measurement, and `:unknown_entity_kind` is the same atom that hid from `declared_reasons/0` for
# three reviews by being spelled a second way. A new spelling needs a new alternation here AND a
# new pin in the red control below.
spellings = [~r/\{:error,\s*:(\w+)\}/, ~r/\|>\s*ok_or\(:(\w+)\)/]

sites =
  lines
  |> Enum.with_index(1)
  |> Enum.flat_map(fn {{file, line}, n} ->
    Enum.flat_map(spellings, fn re ->
      re |> Regex.scan(line) |> Enum.map(fn [_, atom] -> {n, owner.(n, file), atom} end)
    end)
  end)

# Red control, per rule 1. A scanner whose regex has drifted reports zero sites outside the
# population — a clean, confident result meaning "the sweep sees everything", which is the
# opposite of the truth. Three sites are known to exist; require them. Keyed by enclosing
# function and atom, NOT by line: the pins were line numbers until 253d9467 added nine lines to
# kernel.ex's moduledoc and every pin silently pointed at a different line - this red control
# went red on a correct scanner, and nothing noticed because this script is not in the gate.
known = [
  {"cancellation.ex do_transition", "ticket_terminal", "cancellation_requested inline if"},
  {"kernel.ex refuse_terminal_ticket", "ticket_terminal", "pipeline"},
  {"kernel.ex apply", "unknown_entity_kind", "ok_or, the second spelling"}
]

missing =
  Enum.reject(known, fn {fun, atom, _} ->
    Enum.any?(sites, fn {_, f, a} -> f == fun and a == atom end)
  end)

if missing != [] do
  IO.puts(:stderr, "RED CONTROL FAILED: known refusal sites not found: #{inspect(missing)}")
  IO.puts(:stderr, "The scanner's regex no longer matches how this kernel spells a refusal.")
  System.halt(1)
end

IO.puts(
  "red control passed: all #{length(known)} known refusal sites located, across both spellings\n"
)

{in_guards, outside} =
  Enum.split_with(sites, fn {_, fun, _} -> fun && fun && String.contains?(fun, "require_") end)

IO.puts(
  "refusal sites across #{Enum.join(Enum.map(sources, &Path.basename/1), " + ")}: #{length(sites)}"
)

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

handlers =
  Enum.filter(outside, fn {_, fun, _} -> fun && String.ends_with?(fun, " do_transition") end)

IO.puts(
  "\nof those, #{length(handlers)} are inline in do_transition clauses; " <>
    "#{length(outside) - length(handlers)} are in the envelope pipeline and the state builders"
)
