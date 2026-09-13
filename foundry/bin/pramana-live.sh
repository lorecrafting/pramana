#!/usr/bin/env bash
# Mutable-source activation is intentionally unavailable.
# FR-17 replaces this legacy watcher with immutable accepted-build activation.

set -euo pipefail

printf '%s\n' \
  'pramana-live.sh is disabled: mutable source cannot select or activate a runtime.' \
  'FR-17 restores activation from immutable, verified accepted builds.' >&2
exit 78
