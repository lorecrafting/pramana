#!/usr/bin/env bash
# Pre-freeze preflight for Foundry candidates.
#
# Runs the cheap checks that the canonical gate performs but a focused `mix test` does
# not, so a candidate is not frozen on evidence the gate will reject. Roughly 30 seconds
# against several minutes for a full ci/run.exs cycle.
#
# It is NOT a substitute for `elixir ci/run.exs`, which remains the only acceptance
# evidence. It is a way to stop discovering these at the gate.
#
#   cd foundry && bin/preflight.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0

say() { printf '%-34s %s\n' "$1" "$2"; }

# 1. The gate validates the COMMIT and refuses a dirty tree. Local test runs read the
#    working tree, so unstaged edits pass locally and fail the gate. This was the single
#    most common cause of a red gate after a green local run.
dirty=$(git status --porcelain=v1 --untracked-files=all | wc -l | tr -d ' ')
if [ "$dirty" = "0" ]; then say "committed tree clean" "ok"; else
  say "committed tree clean" "FAIL ($dirty uncommitted paths)"
  git status --porcelain=v1 --untracked-files=all | head -5 | sed 's/^/    /'
  fail=1
fi

# 2. mix test does not force a clean rebuild, so a warning in an already-compiled file
#    stays invisible until the gate forces one.
if MIX_ENV=test mix compile --force --warnings-as-errors >/tmp/preflight-compile.log 2>&1; then
  say "forced compile, warnings-as-errors" "ok"
else
  say "forced compile, warnings-as-errors" "FAIL"
  grep -E "warning:|error:" /tmp/preflight-compile.log | head -5 | sed 's/^/    /'
  fail=1
fi

# 2b. `mix compile` covers lib/ only; test files compile at `mix test` time, so a warning
#     in test/**/*.exs is invisible to the check above. Running with a tag no test carries
#     compiles every test file and executes none, in about two seconds. Its exit status is
#     nonzero by design ("no test was executed"), so only the output is inspected.
#     This WARNS rather than fails. The canonical gate does not reject test-file
#     warnings, and the tree carries pre-existing ones, so failing here would block on
#     conditions unrelated to the change being frozen — a false positive is worse than no
#     check. Read the list and confirm none of them are yours.
MIX_ENV=test mix test --only preflight_compile_probe >/tmp/preflight-tests.log 2>&1
warned=$(grep -c "warning:" /tmp/preflight-tests.log || true)
if [ "${warned:-0}" -gt 0 ]; then
  say "test files compile" "WARN ($warned warning(s); see /tmp/preflight-tests.log)"
  grep "warning:" /tmp/preflight-tests.log | head -3 | sed 's/^/    /'
else
  say "test files compile" "ok"
fi

# 3. Cheap, and the gate checks it.
if mix format --check-formatted >/tmp/preflight-format.log 2>&1; then
  say "formatting" "ok"
else
  say "formatting" "FAIL"; head -5 /tmp/preflight-format.log | sed 's/^/    /'; fail=1
fi

# 4. The physical fault tests simulate real ENOSPC and sync failures and produce spurious
#    failures when two suite runs overlap. This warns rather than fails, because the
#    contending process may not be ours.
others=$(pgrep -fl "mix test|ci/run.exs" 2>/dev/null | grep -cv preflight || true)
if [ "${others:-0}" -gt 0 ]; then
  say "machine quiet for fault tests" "WARN ($others suite process(es) running)"
else
  say "machine quiet for fault tests" "ok"
fi

# 5. TMPDIR must resolve to itself; a symlinked one makes the durable store refuse its
#    parent and produces ~74 spurious failures.
real=$(cd "${TMPDIR:-/tmp}" && pwd -P)
if [ "$real" = "${TMPDIR:-/tmp}" ] || [ "$real" = "${TMPDIR%/}" ]; then
  say "TMPDIR is a real path" "ok"
else
  say "TMPDIR is a real path" "WARN (${TMPDIR:-/tmp} resolves to $real; export TMPDIR=/private/tmp)"
fi

echo
[ "$fail" = "0" ] && echo "preflight ok — safe to run ci/run.exs" || echo "preflight FAILED — fix before freezing"
exit "$fail"
