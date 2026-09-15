#!/usr/bin/env bash
# ABBA depth arms over the 64 retrieval/tibetan gold cases.
#
# Back to back in ONE session, in ABBA order, because arms run hours apart measured cache
# weather rather than depth: 13m12s for depth 120 against 11m21s for depth 200, which is
# backwards. The two matched arms agreeing is what makes the middle number readable.
#
# Exit codes are captured per arm and never piped into anything that can swallow them —
# a `grep` in the last pipeline hid a crash while the loop still exited 0.
set -u

LOG="${1:?usage: depth_abba.sh <logfile>}"
: > "$LOG"

# Retrieval cases are semantic; without this the harness scores the LEXICAL path only and
# an English query cannot reach Tibetan at all. The first run of this script forgot it and
# produced a clean, fast, entirely meaningless 0/64 — so the flag is set here rather than
# left to the caller, and the guard below refuses the arm if it did not take effect.
export PRAMANA_EMBEDDING=1

for arm in 60 120 120 60; do
  echo "=== ARM depth=${arm} start $(date +%T)" | tee -a "$LOG"
  start=$SECONDS
  arm_log=$(mktemp)
  mix pramana.evals --only retrieval --tradition tibetan --depth "$arm" > "$arm_log" 2>&1
  code=$?
  cat "$arm_log" >> "$LOG"

  # A run that scored fewer cases than it was given has not measured what its rate claims.
  # Abort the whole ABBA rather than let a degraded arm sit in a comparison table.
  if grep -q "embedding serving is not running" "$arm_log"; then
    echo "=== ABORT: arm ran WITHOUT the embedding serving; the number is meaningless" | tee -a "$LOG"
    exit 1
  fi
  # An errored case does NOT abort the ABBA. Depth 120 exceeds the 120s pool timeout on
  # roughly one arm in two, so aborting on it means the four-arm design may never finish.
  # The arm is flagged instead, loudly, because its rate is over a smaller denominator —
  # arm 3 last time scored 25/63 = 39.7%, which reads as BETTER than arm 2's 25/64 = 39.1%
  # purely from losing a case. Any arm carrying this line is not comparable on rate.
  if grep -q "ERRORED" "$arm_log"; then
    n=$(grep -o "ERRORS:  [0-9]*" "$arm_log" | head -1 | tr -dc 0-9)
    echo "=== DEGRADED: depth=${arm} lost ${n} case(s) to errors — rate is over a smaller set" | tee -a "$LOG"
  fi
  rm -f "$arm_log"

  echo "=== ARM depth=${arm} end $(date +%T) elapsed $((SECONDS - start))s exit ${code}" | tee -a "$LOG"
done

echo "=== ALL ARMS DONE $(date +%T)" | tee -a "$LOG"
