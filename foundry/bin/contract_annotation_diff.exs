# Does an annotation pass over WORKFLOW-CONTRACT.md change any contract text?
#
# EV-2 and EV-6 annotate clause IDs into R4's and R4a's governing tables. That file is the
# oracle: `r4_coverage_test.exs` parses rows out of it at test time, every scenario's
# citation is checked against it, and `R4Rows.declared_from/1` matches 32 from-cells
# character for character. So the annotation must be provably content-preserving, and
# "I was careful" is not a proof.
#
# This strips the ID markers back out of the working tree's contract and compares the
# result to the same file at a git revision. An empty diff is the proof.
#
#   cd foundry
#   elixir bin/contract_annotation_diff.exs                  # against HEAD
#   elixir bin/contract_annotation_diff.exs <rev>            # against a named revision
#
# What it does NOT prove, each of which needs its own check:
#
#   - That the IDs are RIGHT. A marker carrying the wrong row number strips exactly like
#     one carrying the right number. Content preservation and ID correctness are two
#     claims; this tool makes one of them.
#   - That anything USES the IDs. The coverage number only changes when @clauses/@uncited
#     become ID sets.
#   - Anything about a revision you did not pass. The rev and its subject are printed;
#     read them, because a diff against the wrong baseline is clean for the wrong reason.
#
# It compares the WHOLE FILE, not just the two tables, so it cannot be used for a commit
# that both annotates and intentionally edits the contract. Split those.

Code.require_file("test/support/r4_rows.ex")
alias PramanaFoundry.Test.R4Rows

contract = "docs/WORKFLOW-CONTRACT.md"

compare = fn old, new ->
  old_lines = String.split(old, "\n")
  new_lines = R4Rows.strip_ids(new) |> String.split("\n")

  Enum.zip(old_lines, new_lines)
  |> Enum.with_index(1)
  |> Enum.filter(fn {{o, n}, _} -> o != n end)
  |> Enum.map(fn {{o, n}, i} -> {i, o, n} end)
  |> then(fn diffs ->
    case length(old_lines) - length(new_lines) do
      0 ->
        diffs

      d ->
        diffs ++
          [{:length, "#{length(old_lines)} lines", "#{length(new_lines)} lines, #{d} lost"}]
    end
  end)
end

# Red control, per rule 1. Five mechanisms in this subcommit shipped producing confident,
# clean, entirely vacuous results on their first run. This one says so before it reports.
control_plain = "| queued; no pause/drain/cancel | Create a fresh attempt |"

control_annotated =
  "| queued {R4.04.f1}; no pause/drain/cancel {R4.04.f2} | Create a fresh attempt {R4.04.o1} |"

control_tampered = String.replace(control_annotated, "fresh", "new")

if compare.(control_plain, control_annotated) != [] do
  IO.puts(:stderr, "RED CONTROL FAILED: annotation-only text reported as changed. Halting.")
  System.halt(1)
end

if compare.(control_plain, control_tampered) == [] do
  IO.puts(:stderr, "RED CONTROL FAILED: a changed word reported as identical. Halting.")
  System.halt(1)
end

IO.puts("red controls passed: annotation-only is clean, a one-word edit is caught\n")

rev = List.first(System.argv()) || "HEAD"

{subject, 0} = System.cmd("git", ["log", "-1", "--format=%h %s", rev])
{old, 0} = System.cmd("git", ["show", "#{rev}:#{Path.join("foundry", contract)}"])
new = File.read!(contract)

markers = length(Regex.scan(~r/\{R4a?\.\d{2}\.[fo]\d{1,2}\}/, new))

IO.puts("baseline: #{String.trim(subject)}")
IO.puts("markers stripped from the working tree: #{markers}")

if markers == 0 do
  IO.puts("\nNOTHING IS ANNOTATED. A clean result here proves the file is unchanged,")
  IO.puts("which is not the claim this tool exists to support.")
  System.halt(2)
end

case compare.(old, new) do
  [] ->
    IO.puts("\nCONTENT PRESERVED: #{markers} markers added, contract text identical.")

  diffs ->
    IO.puts("\nCONTENT CHANGED at #{length(diffs)} line(s):\n")

    for {i, o, n} <- Enum.take(diffs, 20) do
      IO.puts("  #{i}")
      IO.puts("  - #{o}")
      IO.puts("  + #{n}\n")
    end

    System.halt(1)
end
