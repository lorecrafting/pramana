#!/usr/bin/env bash
# Run the foundry pipeline: create tickets from review findings and enqueue them.
# Requires: daemon running with COORDINATOR_TICK=1 HERDR_ENV=1
set -euo pipefail

cd "$(dirname "$0")/.."
RPC="_build/prod/rel/pramana_foundry/bin/pramana_foundry rpc"

# ── Create ticket checkouts ──
echo "=== Creating ticket worktrees ==="

FOUNDRY_REPO="$(pwd)"
echo "  repo: $FOUNDRY_REPO"
BASE_REV=$(git rev-parse HEAD)
echo "  base_rev: $BASE_REV"

for ticket in FIX-1 FIX-STALE; do
  BRANCH="ticket/${ticket}"
  CHECKOUT="/tmp/pramana-${ticket}"
  echo ""
  echo "  Ticket: $ticket"
  echo "    branch: $BRANCH"
  echo "    checkout: $CHECKOUT"

  # Create worktree
  if [ ! -d "$CHECKOUT" ]; then
    git worktree add -b "$BRANCH" "$CHECKOUT" HEAD 2>&1 | tail -1
  else
    echo "    (checkout exists, updating)"
    git -C "$CHECKOUT" checkout -b "$BRANCH" 2>/dev/null || git -C "$CHECKOUT" checkout "$BRANCH"
  fi

  # Verify base
  TREE_REV=$(git -C "$CHECKOUT" rev-parse HEAD)
  echo "    tree_rev: $TREE_REV"

  # Enqueue via daemon RPC
  case "$ticket" in
    FIX-1)
      # Fix provider cooldown keying — record per-provider, not per-profile
      (cat <<SCRIPT
:ok = PramanaFoundry.Coordinator.reset(accepted_revision: "$BASE_REV")
:ok = PramanaFoundry.Coordinator.enqueue_ticket(%{
  "task_id" => "$ticket",
  "base_revision" => "$BASE_REV",
  "scope" => ["workflow/lib/pramana_workflow/quota/cooldown.ex"],
  "exclusions" => [],
  "checkout" => "$CHECKOUT",
  "required_checks" => [["echo", "ok"]],
  "review_required_checks" => [["echo", "ok"]],
  "auto_approve" => true,
  "corrections" => %{"max" => 1}
})
IO.puts("$ticket enqueued")
SCRIPT
      ) | $RPC 2>/dev/null || echo "    enqueue result: $?"
      ;;

    FIX-STALE)
      # Stale pane prevention — already implemented as code change
      # This ticket tracks the improvement
      (cat <<SCRIPT
:ok = PramanaFoundry.Coordinator.enqueue_ticket(%{
  "task_id" => "$ticket",
  "base_revision" => "$BASE_REV",
  "scope" => ["workflow/lib/pramana_foundry/coordinator.ex"],
  "exclusions" => [],
  "checkout" => "$CHECKOUT",
  "required_checks" => [["echo", "ok"]],
  "review_required_checks" => [["echo", "ok"]],
  "auto_approve" => true,
  "corrections" => %{"max" => 1}
})
IO.puts("$ticket enqueued")
SCRIPT
      ) | $RPC 2>/dev/null || echo "    enqueue result: $?"
      ;;
  esac
done

echo ""
echo "=== Enqueued tickets ==="
$RPC 'IO.puts("queue: #{inspect(PramanaFoundry.Coordinator.state()["queue"])}")' 2>/dev/null
echo ""
echo "=== Daemon will process on next tick (~15s) ==="