#!/usr/bin/env bash
# Self-healing daemon with auto-reload on code changes.
#
# Watches foundry/lib/ for .ex/.exs changes, rebuilds the release,
# then restarts the daemon. The coordinator's event sourcing means
# state survives restarts — in-flight tickets are recovered from the
# event log.
#
# Usage:
#   cd /Users/raymondluong/dev/pramana/foundry
#   bash bin/pramana-live.sh
#
# Environment:
#   COORDINATOR_TICK=1  (required — enables queue processing)
#   HERDR_ENV=1         (required — enables agent dispatch)
#   EVENT_LOG=path      (default: local/state/current/events.jsonl)

set -euo pipefail

cd "$(dirname "$0")/.."

RELEASE="_build/prod/rel/pramana_foundry/bin/pramana_foundry"
WATCH_DIRS="lib"
COOLDOWN_SECS=3

cleanup() {
  echo ""
  echo "=== Shutting down ==="
  $RELEASE daemon stop 2>/dev/null || true
  exit 0
}
trap cleanup SIGINT SIGTERM

build_and_start() {
  echo "--- Building release..."
  if MIX_ENV=prod mix release --overwrite 2>&1 | tail -1; then
    echo "--- Starting daemon..."
    COORDINATOR_TICK=1 HERDR_ENV=1 \
      $RELEASE daemon
    sleep 2
    echo "--- Daemon ready"
    return 0
  else
    echo "!!! Build failed, retaining previous release"
    return 1
  fi
}

# ---- Initial startup ----
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  Pramāṇa Foundry — Live Daemon            ║"
echo "║  Watching: $WATCH_DIRS"
echo "║  Event log: local/state/current/events.jsonl"
echo "╚════════════════════════════════════════════╝"
echo ""

# Stop any previous daemon
$RELEASE daemon stop 2>/dev/null || true
sleep 1

build_and_start

# ---- File watcher loop ----
echo "--- Watching for changes (cooldown=${COOLDOWN_SECS}s)..."
fswatch -l 1 -0 -e ".*" -i "\\.ex$" -i "\\.exs$" \
  --event Updated \
  $WATCH_DIRS |
while read -d "" event; do
  echo ""
  echo "=== Change detected: $(basename "$event") ==="

  # Cooldown — debounce rapid edits
  sleep "$COOLDOWN_SECS"

  # Stop daemon gracefully
  echo "--- Stopping daemon..."
  $RELEASE daemon stop 2>/dev/null || true
  sleep 1

  # Build and restart
  build_and_start || true

  echo "--- Watching for changes..."
done