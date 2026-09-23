#!/bin/sh
# Simulates every property under both step relations. Usage: sh run.sh [samples] [steps]
# Prints one line per (property, step). See README.md for what each result must be.
set -u
cd "$(dirname "$0")"
SAMPLES=${1:-200000}
STEPS=${2:-20}
npx @informalsystems/quint typecheck core.qnt || exit 1
npx @informalsystems/quint test core.qnt || exit 1
for inv in casCurrent createdAtCurrentRevisions issuedUnderActiveControl allocationConserved \
  lineageWellFormed nonstartAllowance closureTerminal limitBranchHolds settlementIdentity \
  attemptSettledIsClosed launchPlannedIsIssued ctlNoLaunchWhilePaused ctlNoLaunchWhileCancel \
  ctlExhaustedOnlyWhenShort witnessRetry witnessBelow witnessReached witnessClosedWithEffect; do
  for st in step stepFixed; do
    (r=$(npx @informalsystems/quint run core.qnt --step "$st" --invariant "$inv" \
      --max-steps "$STEPS" --max-samples "$SAMPLES" --seed 1 2>&1 |
      grep -E "No violation|\[violation\]|rror" | head -1)
     echo "$inv $st: $r") &
  done
  wait
done
