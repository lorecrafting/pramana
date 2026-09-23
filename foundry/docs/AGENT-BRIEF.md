# Foundry agent brief: the standing clauses

Every delegated Foundry task inherits these. A task prompt names only its base commit, its
goal, its file ownership and its report shape, then says "follow `foundry/docs/AGENT-BRIEF.md`".
Written 2026-09-23 from one day's integration of about twenty agent candidates.

## Setup

- Reset your worktree to the base commit the prompt names, and confirm `git log -1` before
  editing. Worktree agents have started on the wrong base
  ([worktree bases](../../docs/agents/WORKFLOW.md)).
- Never `git stash` or `git checkout` to undo an edit. Reverse the exact string.
- From `foundry/`: `TMPDIR=/private/tmp MIX_ENV=test mix test <files>`. If deps are missing,
  set `MIX_DEPS_PATH` to the main checkout's `foundry/deps`.
- Run focused files only. Never run `ci/run.exs` or the full suite: the lead runs one gate per
  push, and concurrent suites produce false failures in the fault tests.
- Never run `bin/rebind_fr08a.exs`. The lead rebinds once after integration; a red
  `fr08a_protected_boundary_test` is expected when you change a pinned file.
- Before each commit: `mix compile --force --warnings-as-errors` and `mix format`.

## Rules that decide whether the work is right

- Read [the boundary rules](BOUNDARY-RULES.md) before any code change.
- **Fix the class, not the instance.** Before editing a function, grep every caller, including
  cascades (a function that calls the one you fix on another route). On 2026-09-23 a cancel fix
  placed on the direct caller left `set_control`'s cascade still bricking the store.
- **If your fix mirrors an earlier finding, check every sibling.** The same un-CAS'd allocation
  read was fixed for the developer and then rewritten for the reviewer, costing a review round.
  Prefer making the omission impossible (a required argument, a builder that cannot produce
  the bad shape) over a note to remember it.
- **Every new guard has a red control** ([evidence tools](EVIDENCE-TOOLS.md), rule 1): break it
  by an exact-string edit, show the test fail, restore, and quote the failure in your report.
- **A committed state must survive reopen.** Any change to a protected operation's writes needs
  a test that reopens the store and asserts it is `:ready`: the restart check refused six
  committed states in one day.
- **Record, do not decide, open operator questions.** Stop and report rather than choosing a
  contract reading the operator has not approved.

## Commits and report

- One logical change per commit. End each message with the attribution lines the lead gives.
- Report in the word limit the prompt sets: SHAs, what changed with `file:line`, red-control
  output, the tests you ran with counts, and anything left open or found out of scope.

## Reviews

Independent review is a fresh agent on a different model (Fable), never a fork. A reviewer
brief names the delta, the approved design, and the author's own inductive steps to attack.
It never asks for a gate rerun or hash recomputation ([repair plan](REPAIR-PLAN.md)). Protected
Core designs get a review *before* implementation as well as after.
