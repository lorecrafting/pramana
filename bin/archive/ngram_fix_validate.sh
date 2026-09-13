#!/usr/bin/env bash
# Does the n-gram fix hold outside Tibetan?
#
# It changes the fallback for EVERY alphabetic query, not just the ones that motivated it:
# 150 retrieval/pali cases and 49 topical cases are all English queries that now take the
# word path instead of grapheme trigrams. Validating on Tibetan alone and shipping would
# repeat rule 37 — a fix measured on one workload, credited against another.
#
# Run at the SHIPPED default depth, so this isolates the n-gram change from the depth
# question. Compared against evals/baseline.json, which predates both.
set -u

LOG="${1:?usage: ngram_fix_validate.sh <logfile>}"
: > "$LOG"

export PRAMANA_EMBEDDING=1

run() {
  echo "=== $* start $(date +%T)" | tee -a "$LOG"
  start=$SECONDS
  mix pramana.evals "$@" >> "$LOG" 2>&1
  echo "=== $* end $(date +%T) elapsed $((SECONDS - start))s exit $?" | tee -a "$LOG"
}

run --only retrieval --tradition pali
run --only topical

echo "=== VALIDATION DONE $(date +%T)" | tee -a "$LOG"
