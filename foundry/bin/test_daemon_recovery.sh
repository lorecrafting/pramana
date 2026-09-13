#!/usr/bin/env bash
# Test daemon restart recovery and pane leak cleanup
#
# Prerequisites:
#   - herdr installed at /opt/homebrew/bin/herdr
#   - HERDR_ENV=1 (real herdr environment)
#   - Build: cd foundry && MIX_ENV=prod mix release --overwrite
#
# Usage:
#   cd /Users/raymondluong/dev/pramana/foundry
#   bash bin/test_daemon_recovery.sh

set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE="_build/prod/rel/pramana_foundry/bin/pramana_foundry"
RPC_CMD="$RELEASE rpc"
EVENT_LOG="local/state/current/events.jsonl"
CHECKOUT="/tmp/pramana-daemon-test"

cleanup() {
  echo "--- Cleanup: stopping daemon..."
  $RELEASE daemon stop 2>/dev/null || true
  # Close any leaked herdr panes
  herdr pane list -f json 2>/dev/null | jq -r '.result.panes[].pane_id' 2>/dev/null | while read -r pid; do
    herdr pane close "$pid" 2>/dev/null || true
  done
  rm -rf "$CHECKOUT"
}
trap cleanup EXIT

echo "=== Daemon Recovery Integration Test ==="

# ---- Setup checkout with proper git history ----
echo "--- Setup: preparing git checkout..."
rm -rf "$CHECKOUT"
mkdir -p "$CHECKOUT"
git init "$CHECKOUT"
git -C "$CHECKOUT" config user.email "test@pramana.local"
git -C "$CHECKOUT" config user.name "Pramana Test"
echo "base content" > "$CHECKOUT/base.txt"
git -C "$CHECKOUT" add base.txt
git -C "$CHECKOUT" commit -m "base commit"
BASE_REV=$(git -C "$CHECKOUT" rev-parse HEAD)
echo "  base revision: $BASE_REV"

# Make a branch for task work
echo "task content" > "$CHECKOUT/task.txt"
git -C "$CHECKOUT" add task.txt
git -C "$CHECKOUT" commit -m "task commit"
TASK_COMMIT=$(git -C "$CHECKOUT" rev-parse HEAD)
echo "  task commit: $TASK_COMMIT"

# ---- Start daemon ----
echo "--- Starting daemon..."
: > "$EVENT_LOG"
COORDINATOR_TICK=1 HERDR_ENV=1 \
  $RELEASE daemon &
DAEMON_PID=$!
echo "  daemon PID: $DAEMON_PID"
sleep 3  # Wait for readiness

# ---- Test 1: Full lifecycle through handoff ----
echo ""
echo "=== Test 1: Full lifecycle through handoff ==="

TASK_ID="T-DAEMON-1"

$RPC_CMD "
:ok = PramanaFoundry.Coordinator.enqueue_ticket(%{
  \"task_id\" => \"$TASK_ID\",
  \"base_revision\" => \"$BASE_REV\",
  \"scope\" => [\"*\"],
  \"exclusions\" => [],
  \"checkout\" => \"$CHECKOUT\",
  \"required_checks\" => [[\"echo\", \"ok\"]],
  \"review_required_checks\" => [[\"echo\", \"ok\"]]
})
"

echo "  Enqueued $TASK_ID"

# Wait for tick to admit and launch agent
sleep 5

# Check state
STATUS=$($RPC_CMD "PramanaFoundry.Coordinator.state() |> Map.get(\"assignments\") |> Map.get(\"$TASK_ID\") |> Map.get(\"status\")" 2>/dev/null || echo "unknown")
echo "  Task status after tick: $STATUS"

# If herdr launched, submit handoff
HANDOFF='{
  "schema_version": 1,
  "task_id": "'"$TASK_ID"'",
  "run_id": "pending",
  "assigned_base": "'"$BASE_REV"'",
  "commit": "'"$TASK_COMMIT"'",
  "changed_files": ["task.txt"],
  "reproduction_evidence": {},
  "checks": [{"command": ["echo", "ok"], "exit_code": 0}],
  "remaining_risks": [],
  "status": "completed",
  "outcome": "test"
}'

$RPC_CMD "
PramanaFoundry.Coordinator.receive_handoff(\"$TASK_ID\", $HANDOFF, [])
" 2>/dev/null || echo "  Handoff submission expected (may fail without herdr)"

echo ""
echo "=== Test 2: Daemon restart recovery ==="

echo "--- Killing daemon (ungracefully)..."
kill -9 "$DAEMON_PID" 2>/dev/null || true
sleep 1

echo "--- Restarting daemon..."
COORDINATOR_TICK=1 HERDR_ENV=1 \
  $RELEASE daemon &
DAEMON_PID=$!
sleep 3

# Check that events were recovered
EVENT_COUNT=$(wc -l < "$EVENT_LOG" 2>/dev/null || echo 0)
echo "  Event log: $EVENT_COUNT events"

RECOVERED=$($RPC_CMD "
state = PramanaFoundry.Coordinator.state()
assignments = Map.get(state, \"assignments\", %{})
Map.keys(assignments) |> Enum.count()
" 2>/dev/null || echo "unknown")
echo "  Recovered assignments: $RECOVERED"

echo ""
echo "=== Test 3: Pane leak cleanup ==="
echo "  (Requires running herdr to have launched panes during Test 1)"
echo "  Waiting for orphan cleanup (16 ticks ≈ 4 minutes)..."
echo "  Check manually with: herdr pane list"

# Wait for multiple ticks to trigger orphan cleanup
for i in $(seq 1 20); do
  sleep 15
  PANE_COUNT=$(herdr pane list -f json 2>/dev/null | jq '.result.panes | length' 2>/dev/null || echo "0")
  echo "  Tick $i: $PANE_COUNT panes visible"
done

echo ""
echo "=== Results ==="
echo "Recovery: $RECOVERED assignments recovered from $EVENT_COUNT events"
echo "Panes: Checked 20 ticks after restart"
echo ""
echo "=== Daemon Recovery Test Complete ==="