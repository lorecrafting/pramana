#!/usr/bin/env bash
# Disabled by FR-05. The legacy fixture requested synthetic approval and created
# mutable worktrees before a protected acceptance boundary existed.
set -euo pipefail

printf '%s\n' \
  'tickets_from_review.sh is disabled: synthetic approval is forbidden.' \
  'FR-13/FR-14 restore verified candidate admission and Git promotion.' >&2
exit 78
