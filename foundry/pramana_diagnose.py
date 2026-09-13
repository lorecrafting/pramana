#!/usr/bin/env python3
"""Pramāṇa Supervisor & Task Diagnostic Utility.

Inspects supervisor state, active cooldowns, blocked queue items, and parked
assignments to provide structured root-cause analysis and actionable recovery commands.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any] | None:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def check_pid(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def format_duration(seconds: float) -> str:
    if seconds <= 0:
        return "expired"
    mins = int(seconds // 60)
    secs = int(seconds % 60)
    hours = mins // 60
    mins = mins % 60
    if hours > 0:
        return f"{hours}h {mins}m {secs}s"
    return f"{mins}m {secs}s"


def diagnose_assignment(task_id: str, assign: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    blocker = assign.get("blocker") or "none"
    status = assign.get("status", "unknown")
    run_id = assign.get("run_id", "unknown")
    worker_name = assign.get("worker_name", "unknown")
    ticket = assign.get("ticket", {})
    scope = set(ticket.get("scope", []))
    base_rev = ticket.get("base_revision", "")
    checkout = ticket.get("checkout")

    diag: dict[str, Any] = {
        "task_id": task_id,
        "status": status,
        "run_id": run_id,
        "worker_name": worker_name,
        "blocker": blocker,
        "category": "unknown",
        "details": [],
        "recommendation": "",
    }

    if "changed path outside allowed scope" in blocker:
        diag["category"] = "SCOPE_VIOLATION"
        offending = blocker.split("outside allowed scope:")[-1].strip()
        diag["details"].append(f"Offending file: {offending}")
        diag["details"].append(f"Declared allowed scope: {list(scope)}")
        diag["recommendation"] = (
            f"Amend ticket {task_id} to expand scope to include '{offending}', "
            f"or revert the out-of-scope edits inside checkout {checkout}."
        )
    elif "integration checkout moved beyond accepted revision" in blocker or "stale-base" in blocker:
        diag["category"] = "REVISION_RACE_STALE_BASE"
        diag["details"].append(f"Ticket base revision: {base_rev[:10]}")
        diag["details"].append(f"Current accepted revision: {state.get('accepted_revision', '')[:10]}")
        diag["recommendation"] = (
            f"Candidate was valid, but integration branch advanced concurrently. "
            f"Rebase candidate branch onto accepted revision {state.get('accepted_revision', '')[:10]} "
            f"or allow PM to admit a fresh run with updated base."
        )
    elif "rejected after 2 correction rounds" in blocker:
        diag["category"] = "REVIEW_REJECTION_LOOP"
        diag["details"].append(f"Correction rounds exhausted ({assign.get('correction_rounds', 0)}/2)")
        rev_path = assign.get("review_path")
        if rev_path and Path(rev_path).exists():
            rev_data = load_json(Path(rev_path))
            if rev_data:
                diag["details"].append(f"Last verdict summary: {rev_data.get('summary', 'none')}")
                diag["details"].append(f"Remaining risks: {rev_data.get('remaining_risks', [])}")
        diag["recommendation"] = (
            f"Review rejected code twice. Inspect checkout {checkout}, address reviewer findings, "
            f"or park/split the ticket."
        )
    elif "dialog watchdog" in blocker:
        diag["category"] = "WATCHDOG_INTERVENTION"
        diag["recommendation"] = (
            "Interactive agent prompted unexpected dialog or session identity was mismatched. "
            "Inspect Herdr pane transcript and check if model prompted for interactive confirmation."
        )
    elif "usage_limit_reached" in blocker or "rate_limit_reached" in blocker:
        diag["category"] = "PROVIDER_LIMIT"
        diag["recommendation"] = (
            "Wait for provider cooldown window to expire, or configure a fallback profile."
        )
    else:
        diag["category"] = "GENERAL_FAILURE"
        diag["recommendation"] = f"Inspect assignment artifacts under artifacts/assignments/{run_id}*."

    return diag


def main() -> int:
    parser = argparse.ArgumentParser(description="Pramāṇa Supervisor & Task Diagnostic Utility")
    parser.add_argument("task_id", nargs="?", help="Specific task ID to diagnose")
    parser.add_argument("--state-root", help="Path to supervisor state root",
                        default="/Users/raymondluong/dev/pramana-integration/.pramana-supervisor/current")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    args = parser.parse_args()

    state_root = Path(args.state_root)
    state_file = state_root / "state.json"
    lock_file = state_root / "supervisor.lock"

    if not state_file.exists():
        print(f"Error: state file not found at {state_file}", file=sys.stderr)
        return 1

    state = load_json(state_file) or {}
    lock_data = load_json(lock_file) or {}
    now = time.time()

    # 1. Daemon Health
    daemon_pid = lock_data.get("pid")
    daemon_running = check_pid(daemon_pid) if daemon_pid else False

    # 2. Provider Cooldowns
    cooldowns = state.get("provider_cooldowns", {})
    active_cooldowns = []
    for prof, data in cooldowns.items():
        until = data.get("until_epoch", 0)
        rem = until - now
        if rem > 0:
            until_dt = datetime.datetime.fromtimestamp(until).strftime("%Y-%m-%d %H:%M:%S")
            active_cooldowns.append({
                "profile": prof,
                "provider": data.get("provider"),
                "signal": data.get("signal"),
                "until": until_dt,
                "remaining_seconds": rem,
                "remaining_text": format_duration(rem),
                "reset_hint": data.get("reset_hint"),
            })

    # 3. PM Planning Status
    pm_info = state.get("pm", {})
    pm_status = pm_info.get("status", "unknown")
    planning_halt = pm_info.get("planning_attempt_halt")

    # 4. Queue Analysis
    queue = state.get("queue", [])
    queue_diagnostics = []
    scheduler_decisions = {d.get("task_id"): d for d in state.get("scheduler", {}).get("decisions", [])}
    for q_task in queue:
        dec = scheduler_decisions.get(q_task, {})
        queue_diagnostics.append({
            "task_id": q_task,
            "status": dec.get("status", "queued"),
            "reason": dec.get("reason", "none"),
        })

    # 5. Assignments
    assignments = state.get("assignments", {})
    diagnosed_assignments = []
    if args.task_id:
        if args.task_id in assignments:
            diagnosed_assignments.append(diagnose_assignment(args.task_id, assignments[args.task_id], state))
        else:
            print(f"Task '{args.task_id}' not found in assignments.", file=sys.stderr)
            return 1
    else:
        for tid, a in assignments.items():
            if a.get("status") in {"parked", "blocked", "failed"}:
                diagnosed_assignments.append(diagnose_assignment(tid, a, state))

    report = {
        "timestamp": datetime.datetime.now().isoformat(),
        "supervisor": {
            "pid": daemon_pid,
            "running": daemon_running,
            "accepted_revision": state.get("accepted_revision"),
            "generation": state.get("generation"),
            "status": state.get("status"),
        },
        "planning": {
            "status": pm_status,
            "halt": planning_halt,
        },
        "active_cooldowns": active_cooldowns,
        "queue": queue_diagnostics,
        "parked_or_blocked_tasks": diagnosed_assignments,
    }

    if args.json:
        print(json.dumps(report, indent=2))
        return 0

    # Human-Readable Formatting
    print("=" * 72)
    print("  PRAMĀṆA SUPERVISOR DIAGNOSTIC REPORT")
    print("=" * 72)
    status_icon = "🟢 RUNNING" if daemon_running else "🔴 STOPPED"
    print(f"Supervisor Daemon: {status_icon} (PID: {daemon_pid})")
    print(f"Accepted Revision: {state.get('accepted_revision', '')}")
    print(f"PM Status:         {pm_status}")

    if planning_halt:
        print("\n⚠️  PLANNING HALTED BY ATTEMPT CAP:")
        print(f"   Reason: {planning_halt.get('reason')}")
        print(f"   Clear with: bin/pramana-supervisor reset-pm-attempts --revision {state.get('accepted_revision')}")

    if active_cooldowns:
        print("\n⏳ ACTIVE PROVIDER COOLDOWNS:")
        for cd in active_cooldowns:
            print(f"   • {cd['profile']} ({cd['provider']}): {cd['signal']}")
            print(f"     Cooldown until {cd['until']} (Remaining: {cd['remaining_text']})")
            if cd['reset_hint']:
                print(f"     Hint: {cd['reset_hint']}")
    else:
        print("\n✅ No active provider cooldowns.")

    if queue_diagnostics:
        print("\n📋 QUEUE STATUS:")
        for qd in queue_diagnostics:
            flag = "⚠️ " if qd['reason'] != "none" else "• "
            print(f"   {flag}{qd['task_id']}: [{qd['status']}] {qd['reason']}")

    if diagnosed_assignments:
        print(f"\n🚨 PARKED / BLOCKED TASKS ({len(diagnosed_assignments)}):")
        for diag in diagnosed_assignments:
            print("-" * 72)
            print(f"Task:      {diag['task_id']} ({diag['status'].upper()})")
            print(f"Worker:    {diag['worker_name']} (run: {diag['run_id'][:10]})")
            print(f"Category:  {diag['category']}")
            print(f"Blocker:   {diag['blocker']}")
            for d in diag['details']:
                print(f"  > {d}")
            print(f"👉 Recommendation: {diag['recommendation']}")
    else:
        print("\n✅ No parked or blocked tasks.")

    print("=" * 72)
    return 0


if __name__ == "__main__":
    sys.exit(main())
