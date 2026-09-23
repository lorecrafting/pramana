defmodule PramanaFoundry.TransitionTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.{Cleanup, Status, Transition}

  test "unresolved cleanup replays as a blocking obligation while preserving work verdict" do
    records = [
      admission("T-CLEAN", "run-clean"),
      pane_event(cleanup_attributes()),
      cleanup_event("cleanup_pending")
    ]

    unresolved =
      cleanup_event("cleanup_result", %{
        "status" => "unresolved",
        "reason" => ":pane_process_identity_changed"
      })

    completed =
      event("task_completed", %{
        "reason" => inspect({:handoff, :ok}),
        "cleanup_status" => "unresolved"
      })

    assert {:ok, %{state: state}} = Transition.rebuild(records ++ [completed, unresolved])
    assignment = state["assignments"]["T-CLEAN"]
    assert assignment["status"] == "cleanup_blocked"
    assert assignment["work_status"] == "review"
    assert assignment["cleanup_outstanding"] == true
    assert assignment["cleanup_obligations"]["developer:run-clean"]["pane_id"] == "pane-owned"
    refute "T-CLEAN" in state["queue"]
  end

  test "only an exact matching terminal cleanup result releases the obligation" do
    pending = cleanup_event("cleanup_pending")

    mismatched =
      cleanup_event("cleanup_result", %{
        "status" => "closed",
        "session" => %{
          "source" => "agent_session",
          "value" => "session-recycled",
          "terminal_id" => "terminal-owned",
          "agent" => "omp"
        }
      })

    assert {:error, %{reason: :cleanup_result_identity_mismatch}} =
             Transition.rebuild([
               admission("T-CLEAN", "run-clean"),
               pane_event(cleanup_attributes()),
               pending,
               mismatched
             ])

    closed = cleanup_event("cleanup_result", %{"status" => "closed"})

    completed =
      event("task_completed", %{
        "reason" => inspect({:handoff, :ok}),
        "cleanup_status" => "closed"
      })

    assert {:ok, %{state: state}} =
             Transition.rebuild([
               admission("T-CLEAN", "run-clean"),
               pane_event(cleanup_attributes()),
               pending,
               completed,
               closed
             ])

    assignment = state["assignments"]["T-CLEAN"]
    assert assignment["status"] == "review"
    assert assignment["work_status"] == "review"
    assert assignment["cleanup_outstanding"] == false
    assert assignment["cleanup_obligations"] == %{}
  end

  test "missing incarnation remains durably attributable and unresolved" do
    missing = %{"presentation_identity" => nil, "session" => nil}
    pending = cleanup_event("cleanup_pending", missing)
    unresolved = cleanup_event("cleanup_result", Map.merge(missing, %{"status" => "unresolved"}))

    assert {:ok, %{state: state}} =
             Transition.rebuild([
               admission("T-CLEAN", "run-clean"),
               pane_event(Map.merge(cleanup_attributes(), missing)),
               pending,
               unresolved
             ])

    obligation =
      state["assignments"]["T-CLEAN"]["cleanup_obligations"]["developer:run-clean"]

    assert obligation["pane_id"] == "pane-owned"
    assert obligation["presentation_identity"] == nil
    assert obligation["status"] == "unresolved"
    assert state["assignments"]["T-CLEAN"]["status"] == "cleanup_blocked"
  end

  test "pending cleanup removes a previously queued assignment from ordinary admission" do
    state = %{
      "assignments" => %{"T-CLEAN" => %{"status" => "queued"}},
      "queue" => ["T-OTHER", "T-CLEAN"]
    }

    assert {:ok, state} = Cleanup.register_resource(state, cleanup_attributes())
    assert {:ok, blocked} = Cleanup.apply_pending(state, cleanup_attributes())
    assert blocked["queue"] == ["T-OTHER"]
    assert blocked["assignments"]["T-CLEAN"]["status"] == "cleanup_pending"
  end

  test "owned resource requires terminal evidence independently of work status" do
    for status <-
          ~w(dispatched handoff_received review review_approved correcting completed failed) do
      assignment = %{
        "status" => status,
        "pane_id" => "pane-owned",
        "terminal_id" => "terminal-owned",
        "agent_name" => "agent-owned",
        "cleanup_outstanding" => false
      }

      state = %{"assignments" => %{"T-CLEAN" => assignment}}
      refute Cleanup.all_owned_resources_terminal?(state), status

      closed =
        put_in(state, ["assignments", "T-CLEAN", "cleanup_last_result"], %{
          "status" => "closed",
          "pane_id" => "pane-owned",
          "terminal_id" => "terminal-owned",
          "agent_name" => "agent-owned"
        })

      assert Cleanup.all_owned_resources_terminal?(closed), status

      recycled =
        put_in(closed, ["assignments", "T-CLEAN", "cleanup_last_result", "pane_id"], "pane-new")

      refute Cleanup.all_owned_resources_terminal?(recycled), status
    end

    assert Cleanup.all_owned_resources_terminal?(%{
             "assignments" => %{"T-NOT-LAUNCHED" => %{"status" => "queued"}}
           })
  end

  test "replay retains sibling resources and only each exact receipt settles its owner" do
    developer = resource_attributes("developer", "run-clean", "dev")
    reviewer = resource_attributes("reviewer", "run-review", "review")

    records = [
      admission("T-CLEAN", "run-clean"),
      pane_event(developer),
      pane_event(reviewer),
      event("cleanup_pending", reviewer, "T-CLEAN", "run-review", "reviewer"),
      event(
        "cleanup_result",
        Map.merge(reviewer, %{"status" => "closed", "reason" => nil}),
        "T-CLEAN",
        "run-review",
        "reviewer"
      )
    ]

    assert {:ok, %{state: one_closed}} = Transition.rebuild(records)
    resources = one_closed["assignments"]["T-CLEAN"]["cleanup_resources"]
    assert resources["developer:run-clean"]["status"] == "owned"
    assert resources["reviewer:run-review"]["status"] == "closed"
    refute Cleanup.all_owned_resources_terminal?(one_closed)

    public_resources = Status.status(one_closed)["cleanup_resources"]["T-CLEAN"]
    assert map_size(public_resources) == 2
    assert public_resources["developer:run-clean"]["pane_id"] == "pane-dev"
    assert public_resources["reviewer:run-review"]["pane_id"] == "pane-review"

    duplicate =
      event(
        "cleanup_result",
        Map.merge(reviewer, %{"status" => "closed", "reason" => nil}),
        "T-CLEAN",
        "run-review",
        "reviewer"
      )

    assert {:error, %{reason: :cleanup_pending_not_found}} =
             Transition.rebuild(records ++ [duplicate])

    developer_pending = event("cleanup_pending", developer)

    stale_developer_result =
      reviewer
      |> Map.merge(%{
        "task_id" => developer["task_id"],
        "execution_id" => developer["execution_id"],
        "role" => developer["role"],
        "status" => "closed",
        "reason" => nil
      })
      |> then(&event("cleanup_result", &1))

    assert {:error, %{reason: :cleanup_result_identity_mismatch}} =
             Transition.rebuild(records ++ [developer_pending, stale_developer_result])

    developer_closed =
      event("cleanup_result", Map.merge(developer, %{"status" => "closed", "reason" => nil}))

    assert {:ok, %{state: both_closed}} =
             Transition.rebuild(records ++ [developer_pending, developer_closed])

    assert Cleanup.all_owned_resources_terminal?(both_closed)
  end

  test "registered ownership rejects a sibling pending before any identity can be rewritten" do
    developer = resource_attributes("developer", "run-clean", "dev")
    reviewer = resource_attributes("reviewer", "run-review", "review")

    registered_events = [
      admission("T-CLEAN", "run-clean"),
      pane_event(developer),
      pane_event(reviewer)
    ]

    assert {:ok, %{state: registered}} = Transition.rebuild(registered_events)
    original_resources = registered["assignments"]["T-CLEAN"]["cleanup_resources"]

    misattributed =
      reviewer
      |> Map.merge(%{
        "task_id" => developer["task_id"],
        "execution_id" => developer["execution_id"],
        "role" => developer["role"]
      })

    assert {:error, %{reason: :cleanup_pending_resource_identity_mismatch}} =
             Transition.rebuild(registered_events ++ [event("cleanup_pending", misattributed)])

    conflicting_registration = pane_event(misattributed)

    assert {:error, %{reason: :cleanup_resource_registration_conflict}} =
             Transition.rebuild(registered_events ++ [conflicting_registration])

    assert {:ok, duplicate_pending} = Cleanup.apply_pending(registered, developer)
    assert {:ok, duplicate_pending} = Cleanup.apply_pending(duplicate_pending, developer)

    resources = duplicate_pending["assignments"]["T-CLEAN"]["cleanup_resources"]

    assert Map.take(
             resources["developer:run-clean"],
             ~w(pane_id terminal_id session presentation_identity)
           ) ==
             Map.take(
               original_resources["developer:run-clean"],
               ~w(pane_id terminal_id session presentation_identity)
             )

    assert resources["reviewer:run-review"] == original_resources["reviewer:run-review"]

    malformed_owner = Map.put(developer, "execution_id", "")
    assert {:error, :invalid_cleanup_owner} = Cleanup.apply_pending(registered, malformed_owner)

    malformed_resource_key = Map.put(developer, "resource_id", "reviewer:run-review")

    assert {:error, :invalid_cleanup_owner} =
             Cleanup.apply_pending(registered, malformed_resource_key)

    malformed_identity = Map.put(developer, "session", %{"source" => "agent_session"})

    assert {:error, :invalid_cleanup_resource_identity} =
             Cleanup.apply_pending(registered, malformed_identity)

    assert registered["assignments"]["T-CLEAN"]["cleanup_resources"] == original_resources

    unregistered = %{
      "assignments" => %{"T-CLEAN" => %{"status" => "dispatched"}},
      "queue" => []
    }

    assert {:error, :cleanup_resource_not_registered} =
             Cleanup.apply_pending(unregistered, developer)
  end

  test "fresh split registration accepts only linked native-session enrichment" do
    complete = resource_attributes("developer", "run-clean", "dev")
    fresh = Map.put(complete, "session", nil)

    state = %{
      "assignments" => %{"T-CLEAN" => %{"status" => "dispatched"}},
      "queue" => []
    }

    assert {:ok, registered} = Cleanup.register_resource(state, fresh)
    assert {:ok, enriched} = Cleanup.register_resource(registered, complete)

    resource =
      enriched["assignments"]["T-CLEAN"]["cleanup_resources"]["developer:run-clean"]

    assert resource["session"] == complete["session"]
    assert resource["presentation_identity"] == fresh["presentation_identity"]

    sibling_session =
      put_in(complete, ["session", "terminal_id"], "terminal-sibling")

    assert {:error, :cleanup_resource_registration_conflict} =
             Cleanup.register_resource(registered, sibling_session)

    original =
      registered["assignments"]["T-CLEAN"]["cleanup_resources"]["developer:run-clean"]

    assert original["session"] == nil
  end

  test "unverified split ownership blocks until exact presentation enrichment" do
    verified = resource_attributes("developer", "run-clean", "dev")

    unverified =
      verified
      |> Map.put("session", nil)
      |> Map.put("presentation_identity", nil)
      |> Map.put("verification_status", "unverified")

    state = %{
      "assignments" => %{"T-CLEAN" => %{"status" => "dispatched"}},
      "queue" => []
    }

    assert {:ok, registered} = Cleanup.register_resource(state, unverified)
    assert {:ok, registered} = Cleanup.register_resource(registered, unverified)

    resource =
      registered["assignments"]["T-CLEAN"]["cleanup_resources"]["developer:run-clean"]

    assert resource["status"] == "unverified"
    assert resource["verification_status"] == "unverified"
    assert registered["assignments"]["T-CLEAN"]["cleanup_outstanding"]
    refute Cleanup.all_owned_resources_terminal?(registered)

    assert Status.status(registered)["cleanup_resources"]["T-CLEAN"]["developer:run-clean"] ==
             resource

    sibling = resource_attributes("developer", "run-clean", "sibling")

    assert {:error, :cleanup_resource_registration_conflict} =
             Cleanup.register_resource(registered, sibling)

    assert {:ok, enriched} =
             Cleanup.register_resource(registered, Map.put(verified, "session", nil))

    enriched_resource =
      enriched["assignments"]["T-CLEAN"]["cleanup_resources"]["developer:run-clean"]

    assert enriched_resource["status"] == "owned"
    assert enriched_resource["verification_status"] == "verified"
    assert enriched["assignments"]["T-CLEAN"]["cleanup_outstanding"]
    assert resource["pane_id"] == "pane-dev"
  end

  test "returns checkpoint-first intents and rebuilds projections from durable records" do
    assert {:ok, %{projection: empty_proj}} = Transition.rebuild([])

    assert {:ok, %{checkpoint: admitted, effects: []}} =
             Transition.plan(empty_proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:00Z"
             })

    assert {:ok, %{projection: proj}} = Transition.rebuild([admitted])

    assert {:ok, %{checkpoint: prompted, effects: [%{type: :deliver_prompt, run_id: "run-1"}]}} =
             Transition.plan(proj, %{
               action: :prompt,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:01Z"
             })

    assert {:ok, %{projection: prompted_proj}} = Transition.rebuild([admitted, prompted])

    assert {:ok, %{effects: [%{type: :reconcile_prompt, run_id: "run-1"}]}} =
             Transition.plan(prompted_proj, %{
               action: :prompt,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:02Z"
             })
  end

  defp admission(task_id, run_id) do
    event("assignment_admitted", %{}, task_id, run_id)
  end

  defp cleanup_event(event_name, overrides \\ %{}) do
    event(event_name, Map.merge(cleanup_attributes(), overrides))
  end

  defp cleanup_attributes do
    %{
      "task_id" => "T-CLEAN",
      "execution_id" => "run-clean",
      "role" => "developer",
      "pane_id" => "pane-owned",
      "terminal_id" => "terminal-owned",
      "session" => %{
        "source" => "agent_session",
        "value" => "session-owned",
        "terminal_id" => "terminal-owned",
        "agent" => "omp"
      },
      "agent_name" => "agent-owned",
      "presentation_identity" => %{
        "pane_id" => "pane-owned",
        "terminal_id" => "terminal-owned",
        "process_identity" => %{
          "pane_id" => "pane-owned",
          "terminal_id" => "terminal-owned",
          "shell_pid" => 303,
          "started_at" => "fixture-generation-1",
          "foreground_pid" => 404,
          "foreground_started_at" => "fixture-foreground-generation-1"
        }
      }
    }
  end

  defp resource_attributes(role, run_id, suffix) do
    pane_id = "pane-#{suffix}"
    terminal_id = "terminal-#{suffix}"

    %{
      "task_id" => "T-CLEAN",
      "execution_id" => run_id,
      "role" => role,
      "pane_id" => pane_id,
      "terminal_id" => terminal_id,
      "session" => %{
        "source" => "agent_session",
        "value" => "session-#{suffix}",
        "terminal_id" => terminal_id,
        "agent" => "omp"
      },
      "observed_session" => nil,
      "agent_name" => "agent-#{suffix}",
      "presentation_identity" => %{
        "pane_id" => pane_id,
        "terminal_id" => terminal_id,
        "process_identity" => %{
          "pane_id" => pane_id,
          "terminal_id" => terminal_id,
          "shell_pid" => 303,
          "started_at" => "shell-#{suffix}",
          "foreground_pid" => 404,
          "foreground_started_at" => "foreground-#{suffix}"
        }
      }
    }
  end

  defp pane_event(resource) do
    event(
      "pane_created",
      %{
        "execution_id" => resource["execution_id"],
        "role" => resource["role"],
        "pane_id" => resource["pane_id"],
        "agent_name" => resource["agent_name"],
        "cleanup_identity" => %{
          "name" => resource["agent_name"],
          "pane_id" => resource["pane_id"],
          "terminal_id" => resource["terminal_id"],
          "session" => resource["session"]
        },
        "presentation_identity" => resource["presentation_identity"]
      },
      resource["task_id"],
      resource["execution_id"],
      resource["role"]
    )
  end

  defp event(
         event_name,
         attributes,
         task_id \\ "T-CLEAN",
         run_id \\ "run-clean",
         role \\ "developer"
       ) do
    %{
      "schema_version" => 1,
      "event" => event_name,
      "at" => "2026-09-12T00:00:00Z",
      "task_id" => task_id,
      "run_id" => run_id,
      "role" => role,
      "attributes" => attributes,
      "evidence" => %{}
    }
  end

  test "duplicate and mismatched assignment identities fail closed" do
    assert {:ok, %{projection: empty_proj}} = Transition.rebuild([])

    assert {:ok, %{checkpoint: admitted}} =
             Transition.plan(empty_proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:00Z"
             })

    assert {:ok, %{projection: proj}} = Transition.rebuild([admitted])

    assert {:error, :duplicate_assignment} =
             Transition.plan(proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:01Z"
             })

    assert {:error, :task_identity_mismatch} =
             Transition.plan(proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-2",
               role: "developer",
               at: "2026-09-08T00:00:02Z"
             })
  end

  test "prompt identity must match the role admitted in durable state" do
    assert {:ok, %{projection: empty_proj}} = Transition.rebuild([])

    assert {:ok, %{checkpoint: admitted}} =
             Transition.plan(empty_proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:00Z"
             })

    assert {:ok, %{projection: proj}} = Transition.rebuild([admitted])
    assert proj.assignments["T1"] == {"run-1", "developer"}

    assert {:error, :role_identity_mismatch} =
             Transition.plan(proj, %{
               action: :prompt,
               task_id: "T1",
               run_id: "run-1",
               role: "reviewer",
               at: "2026-09-08T00:00:01Z"
             })
  end

  test "rebuild rejects prompt intents whose durable run or role was not admitted" do
    admitted = %{
      "schema_version" => 1,
      "event" => "assignment_admitted",
      "at" => "2026-09-08T00:00:00Z",
      "task_id" => "T1",
      "run_id" => "run-1",
      "role" => "developer",
      "attributes" => %{},
      "evidence" => %{}
    }

    prompt = %{admitted | "event" => "prompt_intent", "at" => "2026-09-08T00:00:01Z"}
    wrong_run = %{prompt | "run_id" => "run-2"}

    assert {:error, %{reason: %{reason: :run_identity_mismatch}}} =
             Transition.rebuild([admitted, wrong_run])

    wrong_role = %{prompt | "role" => "reviewer"}

    assert {:error, %{reason: %{reason: :role_identity_mismatch}}} =
             Transition.rebuild([admitted, wrong_role])
  end

  test "rebuild rejects known authority events with missing identity" do
    for event <- ~w(assignment_admitted prompt_intent) do
      incomplete = %{
        "schema_version" => 1,
        "event" => event,
        "at" => "2026-09-08T00:00:00Z",
        "attributes" => %{},
        "evidence" => %{}
      }

      assert {:error, %{reason: %{reason: :missing_authority_identity}}} =
               Transition.rebuild([incomplete])
    end
  end
end
