defmodule PramanaFoundry.StressTest do
  @moduledoc """
  Stress and edge-case tests for the event-sourced coordinator.

  Tests cover corrupted event logs, duplicate events, mixed transitions,
  incomplete lifecycles, and recovery from various failure modes.
  These tests run against pure state reconstruction (Transition.rebuild)
  and do not require a running GenServer.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Transition

  @base_rev "c8ede6a17323c080124aa4512a83494b537648a5"
  @commit "1111222233334444555566667777888899990000"

  # ── Helpers ──

  defp event(event, attrs \\ %{}) do
    %{
      "schema_version" => 1,
      "event" => event,
      "at" => "2026-09-12T00:00:00Z",
      "task_id" => "T-STRESS-1",
      "run_id" => "run-1",
      "role" => "developer",
      "attributes" => attrs,
      "evidence" => %{}
    }
  end

  # ── Corrupted event log tests ──

  describe "corrupted event log" do
    test "empty event list produces clean empty state" do
      assert {:ok, %{projection: proj, state: state}} = Transition.rebuild([])
      assert proj.assignments == %{}
      assert state["queue"] == []
      assert state["assignments"] == %{}
    end

    test "fails closed on schema-invalid events" do
      # A valid ticket_enqueued followed by an event with no "event" key
      valid = %{
        "schema_version" => 1,
        "event" => "ticket_enqueued",
        "at" => "2026-09-12T00:00:00Z",
        "task_id" => "T-STRESS-1",
        "run_id" => "pending",
        "role" => "system",
        "attributes" => %{"ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}},
        "evidence" => %{}
      }

      missing_event_field = %{
        "schema_version" => 1,
        # no "event" key — invalid
        "at" => "2026-09-12T00:00:00Z",
        "task_id" => "T-STRESS-2",
        "attributes" => %{},
        "evidence" => %{}
      }

      wrong_type = %{
        "schema_version" => 1,
        "event" => 42,
        "at" => "2026-09-12T00:00:00Z",
        "attributes" => %{},
        "evidence" => %{}
      }

      unknown_fields = %{
        "schema_version" => 1,
        "event" => "ticket_enqueued",
        "at" => "2026-09-12T00:00:00Z",
        "task_id" => "T-STRESS-3",
        "unknown_top_level" => "should be rejected",
        "attributes" => %{},
        "evidence" => %{}
      }

      assert {:error, _reason} =
               Transition.rebuild([valid, missing_event_field, wrong_type, unknown_fields])
    end

    test "garbage binary records fail closed" do
      base1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-GARBAGE-1", "base_revision" => @base_rev}
        })

      e1 = %{base1 | "task_id" => "T-GARBAGE-1"}

      # Simulate what happens when a garbage binary line is read from JSONL
      garbage_not_a_map = "this is not a map"

      base2 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-GARBAGE-2", "base_revision" => @base_rev}
        })

      e2 = %{base2 | "task_id" => "T-GARBAGE-2"}

      assert {:error, _reason} = Transition.rebuild([e1, garbage_not_a_map, e2])
    end
  end

  # ── Duplicate admission tests ──

  describe "duplicate admission events" do
    test "same identity repeated is a duplicate event but does not crash rebuild" do
      e1 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})

      assert {:ok, %{state: state}} = Transition.rebuild([e1, e1])
      # The duplicate is idempotently projected; state reflects the same admission.
      assert state["assignments"]["T-STRESS-1"]["status"] == "dispatched"
      assert state["assignments"]["T-STRESS-1"]["run_id"] == "run-1"
      # Queue should have removed this task
      refute "T-STRESS-1" in state["queue"]
    end

    test "different run_id after launch_retried supersedes and is convergent" do
      e1 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})
      base = e1

      retry = %{
        base
        | "event" => "launch_retried",
          "attributes" => %{
            "retry_count" => 1,
            "max_retries" => 3,
            "error_reason" => "launch_failed"
          }
      }

      # Second admit with a DIFFERENT run_id
      e2 = %{base | "run_id" => "run-2", "attributes" => %{"checkout" => "/tmp/w1"}}

      assert {:ok, %{state: state, projection: proj}} = Transition.rebuild([e1, retry, e2])
      # State should show latest dispatch
      assert state["assignments"]["T-STRESS-1"]["status"] == "dispatched"
      assert state["assignments"]["T-STRESS-1"]["run_id"] == "run-2"
      # Projection should show latest identity
      assert proj.assignments["T-STRESS-1"] == {"run-2", "developer"}
    end

    test "multiple admit-retry cycles converge to final state" do
      base = event("assignment_admitted", %{"checkout" => "/tmp/w1"})

      r1 = %{
        base
        | "event" => "launch_retried",
          "attributes" => %{
            "retry_count" => 1,
            "max_retries" => 3,
            "error_reason" => "fail"
          }
      }

      e2 = %{base | "run_id" => "run-2", "attributes" => %{"checkout" => "/tmp/w1"}}

      r2 = %{
        base
        | "event" => "launch_retried",
          "run_id" => "run-2",
          "attributes" => %{
            "retry_count" => 2,
            "max_retries" => 3,
            "error_reason" => "fail2"
          }
      }

      e3 = %{base | "run_id" => "run-3", "attributes" => %{"checkout" => "/tmp/w1"}}

      assert {:ok, %{state: state, projection: proj}} = Transition.rebuild([base, r1, e2, r2, e3])
      assert state["assignments"]["T-STRESS-1"]["status"] == "dispatched"
      assert state["assignments"]["T-STRESS-1"]["run_id"] == "run-3"
      assert proj.assignments["T-STRESS-1"] == {"run-3", "developer"}
    end

    test "admit then park then admit converges correctly" do
      base = event("assignment_admitted", %{"checkout" => "/tmp/w1"})

      park = %{
        base
        | "event" => "launch_parked",
          "attributes" => %{
            "retry_count" => 3,
            "max_retries" => 3,
            "error_reason" => "max_retries"
          }
      }

      # After parking, a manual re-enqueue + admit
      re_enq = %{
        base
        | "event" => "ticket_re_enqueued",
          "attributes" => %{
            "reason" => "manual",
            "previous_status" => "parked"
          }
      }

      e2 = %{base | "run_id" => "run-2", "attributes" => %{"checkout" => "/tmp/w1"}}

      assert {:ok, %{state: state, projection: proj}} =
               Transition.rebuild([base, park, re_enq, e2])

      assert state["assignments"]["T-STRESS-1"]["status"] == "dispatched"
      assert state["assignments"]["T-STRESS-1"]["run_id"] == "run-2"
    end
  end

  # ── Incomplete lifecycle tests ──

  describe "incomplete lifecycles rebuild correctly" do
    test "just a ticket_enqueued — rebuilt as queued" do
      e =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}
        })

      assert {:ok, %{state: state}} = Transition.rebuild([e])
      assert state["assignments"]["T-STRESS-1"]["status"] == "queued"
      assert "T-STRESS-1" in state["queue"]
    end

    test "ticket_enqueued then admitted — rebuilt as dispatched" do
      e1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}
        })

      e2 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})
      assert {:ok, %{state: state}} = Transition.rebuild([e1, e2])
      assert state["assignments"]["T-STRESS-1"]["status"] == "dispatched"
      refute "T-STRESS-1" in state["queue"]
    end

    test "full lifecycle: enqueue → admit → handoff → review → integrate" do
      e1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}
        })

      e2 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})

      e3 =
        event("handoff_received", %{"handoff" => %{"commit" => @commit, "status" => "completed"}})

      e4 = event("review_received", %{"verdict" => "approved", "correction_count" => 0})
      e5 = event("integration_started", %{"commit" => @commit})
      e6 = event("integration_completed", %{"outcome" => "succeeded", "commit" => @commit})

      assert {:ok, %{state: state}} = Transition.rebuild([e1, e2, e3, e4, e5, e6])
      assert state["assignments"]["T-STRESS-1"]["status"] == "integration_unverified"
      assert state["accepted_revision"] != @commit
      assert get_in(state, ["integration", "legacy_unverified_claims"]) != []
      assert state["integration"]["owner"] == nil
    end

    test "enqueue → admit → crash recovers correctly" do
      e1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}
        })

      e2 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})
      base = e2

      e3 = %{
        base
        | "event" => "task_crashed",
          "attributes" => %{"reason" => "agent_crashed: :normal"}
      }

      assert {:ok, %{state: state}} = Transition.rebuild([e1, e2, e3])
      assert state["assignments"]["T-STRESS-1"]["status"] == "crashed"
      assert String.contains?(state["assignments"]["T-STRESS-1"]["error"] || "", "agent_crashed")
    end

    test "integration failure parks the task and preserves revision" do
      original_rev = "original_rev_000000000000000000000000000000000000"

      e1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => original_rev}
        })

      e2 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})

      e3 =
        event("handoff_received", %{"handoff" => %{"commit" => @commit, "status" => "completed"}})

      e4 = event("review_received", %{"verdict" => "approved", "correction_count" => 0})
      e5 = event("integration_started", %{"commit" => @commit})

      e6 =
        event("integration_completed", %{
          "outcome" => "failed",
          "reason" => "check failed: exit 1"
        })

      assert {:ok, %{state: state}} = Transition.rebuild([e1, e2, e3, e4, e5, e6])
      assert state["assignments"]["T-STRESS-1"]["status"] == "parked"
      # Accepted revision should NOT change on failure
      refute state["accepted_revision"] == @commit
      assert state["integration"]["owner"] == nil
    end
  end

  # ── Mixed and weird state tests ──

  describe "mixed transitions and event ordering" do
    test "review with correction_needed restores correction state" do
      e1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}
        })

      e2 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})

      e3 =
        event("handoff_received", %{"handoff" => %{"commit" => @commit, "status" => "completed"}})

      e4 = event("review_received", %{"verdict" => "correction_needed", "correction_count" => 0})

      assert {:ok, %{state: state}} = Transition.rebuild([e1, e2, e3, e4])
      assert state["assignments"]["T-STRESS-1"]["correction_count"] == 1
      assert state["assignments"]["T-STRESS-1"]["status"] == "queued"
      assert "T-STRESS-1" in state["queue"]
    end

    test "review with correction_count restores correct value on approve" do
      e1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}
        })

      e2 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})

      e3 =
        event("handoff_received", %{"handoff" => %{"commit" => @commit, "status" => "completed"}})

      e4 = event("review_received", %{"verdict" => "approved", "correction_count" => 2})

      assert {:ok, %{state: state}} = Transition.rebuild([e1, e2, e3, e4])
      assert state["assignments"]["T-STRESS-1"]["status"] == "review_approved"
      assert state["assignments"]["T-STRESS-1"]["correction_count"] == 2
    end

    test "pane_created sets pane info without changing status" do
      e1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}
        })

      e2 = event("assignment_admitted", %{"checkout" => "/tmp/w1"})
      base = e2

      cleanup_identity = %{
        "name" => "pramana-dev-test",
        "pane_id" => "w3:p42",
        "terminal_id" => "term-42",
        "session" => %{"source" => "agent_session", "value" => "session-42"}
      }

      presentation_identity = %{
        "pane_id" => "w3:p42",
        "terminal_id" => "term-42",
        "process_identity" => %{
          "pane_id" => "w3:p42",
          "terminal_id" => "term-42",
          "shell_pid" => 101,
          "started_at" => "fixture-1",
          "foreground_pid" => 202,
          "foreground_started_at" => "foreground-fixture-1"
        }
      }

      e3 = %{
        base
        | "event" => "pane_created",
          "attributes" => %{
            "pane_id" => "w3:p42",
            "agent_name" => "pramana-dev-test",
            "cleanup_identity" => cleanup_identity,
            "presentation_identity" => presentation_identity
          }
      }

      assert {:ok, %{state: state}} = Transition.rebuild([e1, e2, e3])
      assert state["assignments"]["T-STRESS-1"]["pane_id"] == "w3:p42"
      assert state["assignments"]["T-STRESS-1"]["agent_name"] == "pramana-dev-test"
      assert state["assignments"]["T-STRESS-1"]["cleanup_identity"] == cleanup_identity

      assert state["assignments"]["T-STRESS-1"]["presentation_identity"] ==
               presentation_identity

      # Status stays dispatched — no terminal event written yet
      assert state["assignments"]["T-STRESS-1"]["status"] == "dispatched"
    end

    test "unknown event types fail strict replay" do
      e1 =
        event("ticket_enqueued", %{
          "ticket" => %{"task_id" => "T-STRESS-1", "base_revision" => @base_rev}
        })

      base = e1

      unknown = %{
        base
        | "event" => "completely_unknown_event_type",
          "attributes" => %{"foo" => "bar"}
      }

      assert {:error, %{reason: %{reason: :unknown_event_type}}} =
               Transition.rebuild([e1, unknown])
    end
  end

  # ── Large event log performance smoke test ──

  describe "large event log" do
    @tag timeout: 10_000
    test "rebuilds 5000 events without blowing up" do
      # Generate 5000 ticket_enqueued events for different task IDs
      events =
        Enum.map(1..5000, fn i ->
          tid = "T-LARGE-#{String.pad_leading("#{i}", 4, "0")}"

          %{
            "schema_version" => 1,
            "event" => "ticket_enqueued",
            "at" => "2026-09-12T00:00:00Z",
            "task_id" => tid,
            "run_id" => "pending",
            "role" => "system",
            "attributes" => %{
              "ticket" => %{
                "task_id" => tid,
                "base_revision" => @base_rev,
                "scope" => ["lib/**"],
                "exclusions" => [],
                "required_checks" => [["echo", "ok"]]
              }
            },
            "evidence" => %{}
          }
        end)

      assert {:ok, %{state: state}} = Transition.rebuild(events)
      assert map_size(state["assignments"]) == 5000
      assert length(state["queue"]) == 5000
    end
  end
end
