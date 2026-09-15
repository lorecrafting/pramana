#!/usr/bin/env bash
# Which ARM does the depth gain live in?
#
# Depth 120 is worth +5 of 64 retrieval/tibetan cases, reproduced five times, and costs
# ~4x on the full retrieval set. If the gain is semantic and the cost is lexical, the two
# can be separated and the gain bought cheaply.
#
# Three arms on the 64 Tibetan cases, back to back in one session:
#
#   1  default        both arms at 60   -> expect 20/64  (the control)
#   2  semantic deep  semantic 120, lexical 60
#   3  lexical deep   lexical 120, semantic 60
#
# Arm 2 at 25/64 and arm 3 at 20/64 means the gain is entirely semantic, and deep-semantic
# with shallow-lexical is the shipping configuration. Any other combination refutes the
# split and the single `depth` knob stands.
set -u

LOG="${1:?usage: arm_depth_probe.sh <logfile>}"
: > "$LOG"

export PRAMANA_EMBEDDING=1

arm() {
  label="$1"; shift
  echo "=== ARM ${label} start $(date +%T)" | tee -a "$LOG"
  start=$SECONDS
  out=$(mktemp)
  mix pramana.evals --only retrieval --tradition tibetan "$@" > "$out" 2>&1
  code=$?
  cat "$out" >> "$LOG"
  grep -q "embedding serving is not running" "$out" && { echo "=== ABORT: no serving" | tee -a "$LOG"; exit 1; }
  grep -q "ERRORED" "$out" && echo "=== DEGRADED ${label}: rate is over a smaller set" | tee -a "$LOG"
  rm -f "$out"
  echo "=== ARM ${label} end $(date +%T) elapsed $((SECONDS - start))s exit ${code}" | tee -a "$LOG"
}

arm "default-60"
arm "semantic-120" --semantic-depth 120 --lexical-depth 60
arm "lexical-120"  --lexical-depth 120 --semantic-depth 60

echo "=== PROBE DONE $(date +%T)" | tee -a "$LOG"
