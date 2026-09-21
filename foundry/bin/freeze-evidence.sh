#!/usr/bin/env bash
# Freeze evidence for a Foundry candidate.
#
# Every freeze in this repair runs the same four steps and then transcribes the numbers
# into the implementation log by hand. The transcription is where claims have been made
# that were not checked: a suite count reported from memory, a delta asserted rather than
# computed, a preflight described as green from an earlier run. This does the steps and
# emits the evidence block, so the log records what was measured rather than what was
# remembered.
#
#   cd foundry && bin/freeze-evidence.sh [previous_passed_count]
#
# With a previous count it also checks the delta: a freeze that adds N tests must move the
# total by N. A silent drop - a suite that stopped being loaded, a test renamed into
# nonexistence - shows up as a delta that does not add up, which no single run can reveal.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

previous="${1:-}"
build="/private/tmp/freeze-$(date +%s)/_build"
fail=0

say() { printf '%-34s %s\n' "$1" "$2"; }

echo "=== freeze evidence: $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD) ==="
echo

# 1. Preflight first: it is cheap, and a red tree check makes every later number describe
#    something the gate will not build.
if bin/preflight.sh > /private/tmp/freeze-preflight.log 2>&1; then
  say "preflight" "ok"
else
  say "preflight" "FAIL (see /private/tmp/freeze-preflight.log)"
  fail=1
fi

# 2. The full model-free suite, serially, in a fresh build path. Serial because concurrent
#    runs in this repository produce spurious physical-fault failures; fresh because a
#    stale build path has silently served old modules here before.
say "full suite" "running (serial, fresh build path)"
TMPDIR=/private/tmp MIX_BUILD_PATH="$build" mix test --seed 0 --max-cases 1 \
  > /private/tmp/freeze-suite.log 2>&1
suite_status=$?

line=$(grep -E '^[0-9]+ tests?,|^Result:|passed' /private/tmp/freeze-suite.log | tail -1)
passed=$(grep -oE '[0-9]+ (tests?|passed)' /private/tmp/freeze-suite.log | tail -1 | grep -oE '[0-9]+')
skipped=$(grep -oE '[0-9]+ skipped' /private/tmp/freeze-suite.log | tail -1 | grep -oE '[0-9]+' || echo 0)

if [ "$suite_status" -eq 0 ]; then
  say "full suite" "${passed:-?} passed, ${skipped:-0} skipped at seed 0"
else
  say "full suite" "FAIL (see /private/tmp/freeze-suite.log)"
  fail=1
fi

# 3. The delta check. Supplied rather than inferred, because only the author knows how many
#    tests this candidate was meant to add.
if [ -n "$previous" ] && [ -n "${passed:-}" ]; then
  delta=$((passed - previous))
  say "delta from $previous" "$delta"
  echo
  echo "  State the delta in the log and say what accounts for it. A freeze that cannot"
  echo "  explain its own delta is reporting a number, not evidence."
fi

echo
echo "--- evidence block for IMPLEMENTATION-LOG.md ---"
echo "- Suites at freeze: full model-free suite **${passed:-?} passed, ${skipped:-0} skipped at"
echo "  seed 0**, run serially with a fresh \`MIX_BUILD_PATH\`. \`foundry/bin/preflight.sh\`"
echo "  passes. Candidate \`$(git rev-parse --short HEAD)\` on \`$(git rev-parse --abbrev-ref HEAD)\`."
echo

if [ "$fail" -ne 0 ]; then
  echo "freeze evidence INCOMPLETE - do not freeze"
  exit 1
fi

echo "freeze evidence complete"
