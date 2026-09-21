defmodule PramanaFoundry.Workflow.KernelTest do
  @moduledoc """
  Subcommit 1 of the FR-08B kernel correction: the pure state and event contract.

  The first describe block reproduces the counterexamples of the independent pure-kernel
  review (`docs/fr-08/fr08b-pure-kernel-review.md`, candidate `a00decc`) and asserts the
  corrected behaviour, so each stays a regression control rather than a one-time argument.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.{Event, State}

  # ── Builders ───────────────────────────────────────────────────────────────────────

  defp event(type, entity_id, revision, sequence, payload) do
    {:ok, kind} = Event.entity_kind(type)

    %{
      "schema_version" => 1,
      "event_id" => "evt-#{type}-#{sequence}",
      "type" => type,
      "sequence" => sequence,
      "entity_kind" => kind,
      "entity_id" => entity_id,
      "entity_revision" => revision,
      "payload" => payload
    }
  end

  defp authority(execution_id) do
    %{
      "schema_version" => 1,
      "effect_id" => "eff-#{execution_id}",
      "role" => "developer",
      "work_owner" => "own-1",
      "ticket_id" => "T1",
      "attempt_id" => "A1",
      "execution_id" => execution_id,
      "policy_id" => "pol-1",
      "policy_revision" => 0,
      "control_id" => "ctl-1",
      "control_revision" => 0,
      "predecessor_effect_id" => nil,
      "infrastructure_generation" => 0
    }
  end

  # Applies events in order, asserting each one is accepted. Sequence and entity revision
  # are tracked here so a test states its lifecycle rather than its bookkeeping. The
  # starting sequence is threaded explicitly, because durable sequence is strictly
  # increasing across the whole log: a helper that restarted it at zero would be building
  # histories the reducer is right to reject.
  defp drive({state, sequence}, specs) do
    Enum.reduce(specs, {state, sequence}, fn {type, entity_id, payload}, {state, sequence} ->
      sequence = sequence + 1
      revision = revision_of(state, type, entity_id)
      built = event(type, entity_id, revision, sequence, payload)

      case WorkflowKernel.apply(state, built) do
        {:ok, next} ->
          assert State.valid?(next), "#{type} produced a state its own validator rejects"
          {next, sequence}

        {:error, reason} ->
          flunk("#{type} rejected as #{inspect(reason)}")
      end
    end)
  end

  defp revision_of(state, type, entity_id) do
    {:ok, kind} = Event.entity_kind(type)

    case kind do
      "control" -> state["control"]["revision"]
      "ticket" -> get_in(state, ["tickets", entity_id, "revision"]) || 0
      "objective" -> get_in(state, ["objectives", entity_id, "revision"]) || 0
    end
  end

  defp admitted do
    drive({State.new(), 0}, [
      {"ticket_admitted", "T1",
       %{
         "ticket_id" => "T1",
         "objective_id" => nil,
         "spec_revision_id" => "spec-1",
         "spec" => %{},
         "phase" => "queued",
         "reason" => nil
       }}
    ])
  end

  # Drives a ticket to a frozen candidate with the developer closed and checks started.
  defp checking do
    drive(admitted(), [
      {"launch_planned", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
      {"artifact_frozen", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "observation_id" => "obs-1",
         "sealed_generation" => "gen-1"
       }},
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "X1",
         "last_accepted_sequence" => 7
       }},
      {"developer_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}},
      {"checks_started", "T1", %{"ticket_id" => "T1", "attempt_id" => "A1"}}
    ])
  end

  # ── The reviewed candidate's counterexamples ───────────────────────────────────────

  describe "B1 — apply/2 is a guarded reducer, not a snapshot installer" do
    test "an unknown event type cannot create an integrated ticket from empty state" do
      # The reviewed candidate accepted any nonempty type and merged generic changes, so
      # this exact event produced an integrated ticket with no candidate, checks, review,
      # claim or ref receipt.
      forged =
        event("ticket_admitted", "T1", 0, 1, %{
          "ticket_id" => "T1",
          "objective_id" => nil,
          "spec_revision_id" => "spec-1",
          "spec" => %{},
          "phase" => "integrated",
          "reason" => nil
        })

      assert {:error, :invalid_admission_phase} = WorkflowKernel.apply(State.new(), forged)

      unknown = %{forged | "type" => "ticket_integrated"}
      assert {:error, :invalid_semantic_event} = WorkflowKernel.apply(State.new(), unknown)
    end

    test "no event outside the closed vocabulary reaches a merge" do
      for type <- ["", "integrate", "ticket_admitted ", "TICKET_ADMITTED", "__struct__"] do
        forged = event("ticket_admitted", "T1", 0, 1, %{}) |> Map.put("type", type)
        assert {:error, :invalid_semantic_event} = WorkflowKernel.apply(State.new(), forged)
      end
    end

    test "an integrated ticket is reachable only through its lifecycle" do
      {state, _} = full_lifecycle()
      assert state["tickets"]["T1"]["phase"] == "integrated"

      attempt = state["tickets"]["T1"]["attempts"]["A1"]
      assert attempt["disposition"] == "integrated"
      assert attempt["candidate_id"] == "cand-1"
      assert attempt["review"]["verdict"] == "approved"
      assert attempt["checks"]["C1"]["status"] == "passed"
    end

    test "an older event applied after a newer one is rejected, not installed" do
      {state, sequence} = admitted()

      stale =
        event("ticket_amended", "T1", state["tickets"]["T1"]["revision"], sequence, %{
          "ticket_id" => "T1",
          "spec_revision_id" => "spec-2",
          "spec" => %{}
        })

      assert {:error, :out_of_order_event} = WorkflowKernel.apply(state, stale)
    end

    test "a stale entity revision is rejected even when the sequence advances" do
      {state, sequence} = admitted()

      stale =
        event("ticket_amended", "T1", 0, sequence + 1, %{
          "ticket_id" => "T1",
          "spec_revision_id" => "spec-2",
          "spec" => %{}
        })

      assert state["tickets"]["T1"]["revision"] == 1
      assert {:error, :stale_entity_revision} = WorkflowKernel.apply(state, stale)
    end

    test "a redelivery of the event an entity last applied is an idempotent no-op" do
      {state, sequence} = admitted()

      redelivered =
        event("ticket_admitted", "T1", 0, sequence, %{
          "ticket_id" => "T1",
          "objective_id" => nil,
          "spec_revision_id" => "spec-1",
          "spec" => %{},
          "phase" => "queued",
          "reason" => nil
        })

      assert {:ok, ^state} = WorkflowKernel.apply(state, redelivered)
    end

    test "valid?/1 rejects the malformed nested state that made decide/3 raise" do
      # The reviewed candidate's validator checked outer containers and four control
      # fields, so this state passed and then raised inside a source guard.
      assert State.valid?(State.new())
      refute State.valid?(put_in(State.new(), ["tickets"], %{"T1" => 7}))
      refute State.valid?(put_in(State.new(), ["tickets"], %{"T1" => %{"phase" => "queued"}}))
    end

    test "valid?/1 rejects additional protected-looking top-level facts" do
      refute State.valid?(Map.put(State.new(), "root_policy", %{"limit" => 99}))
      refute State.valid?(Map.put(State.new(), "ledgers", %{}))
    end

    test "a map key that disagrees with the identifier it holds is invalid" do
      {state, _} = admitted()
      ticket = state["tickets"]["T1"]
      refute State.valid?(put_in(state, ["tickets"], %{"T2" => ticket}))
    end

    test "apply/2 is total over every state valid?/1 accepts" do
      {lifecycle, _} = full_lifecycle()
      {mid, _} = checking()
      {early, _} = admitted()

      states = [State.new(), early, mid, lifecycle]

      events =
        for type <- Event.types() do
          {:ok, keys} = Event.payload_keys(type)
          {:ok, kind} = Event.entity_kind(type)
          entity_id = if kind == "control", do: "control", else: "T1"
          payload = Map.new(keys, fn key -> {key, hostile_value(key)} end)
          event(type, entity_id, 0, 1, payload)
        end

      for state <- states, built <- events do
        result = WorkflowKernel.apply(state, built)

        assert match?({:ok, _}, result) or match?({:error, _}, result),
               "#{built["type"]} raised or returned an untagged value"
      end
    end

    defp hostile_value("ticket_id"), do: "T1"
    defp hostile_value("objective_id"), do: "T1"
    defp hostile_value(key) when key in ~w(attempt_id), do: "A1"
    defp hostile_value(_key), do: %{"unexpected" => [1, nil, %{}]}
  end

  describe "B2 — custody per the R4 rows" do
    test "checks cannot start without verified developer closure" do
      {state, sequence} =
        drive(admitted(), [
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
          {"artifact_frozen", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "candidate_id" => "cand-1",
             "observation_id" => "obs-1",
             "sealed_generation" => "gen-1"
           }}
        ])

      premature =
        event("checks_started", "T1", state["tickets"]["T1"]["revision"], sequence + 10, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1"
        })

      assert {:error, :developer_not_closed} = WorkflowKernel.apply(state, premature)
    end

    test "developer closure requires the input stream to be sealed first" do
      {state, sequence} =
        drive(admitted(), [
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
          {"artifact_frozen", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "candidate_id" => "cand-1",
             "observation_id" => "obs-1",
             "sealed_generation" => "gen-1"
           }}
        ])

      unsealed =
        event("developer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1"
        })

      assert {:error, :stream_not_sealed} = WorkflowKernel.apply(state, unsealed)
    end

    test "a review verdict is refused before the reviewer stream is sealed" do
      {state, sequence} = reviewing()

      premature =
        event("review_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "candidate_id" => "cand-1",
          "verdict" => "approved"
        })

      assert {:error, :reviewer_stream_not_sealed} = WorkflowKernel.apply(state, premature)
    end

    test "a verdict naming another candidate is refused" do
      {state, sequence} =
        drive(reviewing(), [
          {"stream_sealed", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "R1",
             "last_accepted_sequence" => 3
           }}
        ])

      wrong =
        event("review_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 20, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "candidate_id" => "cand-other",
          "verdict" => "approved"
        })

      assert {:error, :verdict_names_another_candidate} = WorkflowKernel.apply(state, wrong)
    end

    test "a failed candidate cannot reach review" do
      {state, sequence} =
        drive(checking(), [
          {"check_planned", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "check_id" => "C1",
             "authority" => authority("K1")
           }},
          {"check_recorded", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "check_id" => "C1",
             "status" => "failed",
             "reason_code" => "assertion_failed"
           }}
        ])

      attempt = state["tickets"]["T1"]["attempts"]["A1"]
      assert attempt["phase"] == "checking", "a failed check must not advance to review"

      premature =
        event("review_planned", "T1", state["tickets"]["T1"]["revision"], sequence + 20, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => authority("R1")
        })

      assert {:error, :wrong_attempt_phase} = WorkflowKernel.apply(state, premature)
    end

    test "integration cannot record a ref receipt while a check worker is still open" do
      # R4: "successful ref receipt and prior role/check workers closed". This is the gap
      # the enumeration missed: it named closure events for the developer and the reviewer
      # and none for the check, build and integration workers, so the integration row was
      # unreachable until worker_closed existed.
      {state, sequence} =
        drive(reviewing(), [
          {"stream_sealed", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "R1",
             "last_accepted_sequence" => 3
           }},
          {"review_recorded", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "candidate_id" => "cand-1",
             "verdict" => "approved"
           }},
          {"reviewer_closed", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}},
          {"integration_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("I1")}}
        ])

      premature =
        event("integration_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "I1",
          "outcome" => "ref_created",
          "ref_receipt_id" => "ref-1"
        })

      assert {:error, :workers_not_closed} = WorkflowKernel.apply(state, premature)
    end

    test "an ordinary observation cannot close an execution" do
      {state, sequence} = checking()

      forged =
        event("execution_observed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1",
          "observation" => "process exited",
          "lifecycle" => "closed"
        })

      # X1 is already closed by this point, and closure is terminal, so the stronger guard
      # answers first. Both refusals are correct; the point is that no observation reopens
      # or closes an execution.
      assert {:error, :execution_already_closed} = WorkflowKernel.apply(state, forged)

      open =
        event("execution_observed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "K1",
          "observation" => "process exited",
          "lifecycle" => "closed"
        })

      assert {:error, :unknown_execution} = WorkflowKernel.apply(state, open)
    end

    test "worker_closed refuses an execution that is not a worker" do
      {state, sequence} = checking()

      forged =
        event("worker_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1"
        })

      assert {:error, :not_a_worker_execution} = WorkflowKernel.apply(state, forged)
    end

    test "settling an attempt retains it as a prior attempt with all its evidence" do
      {state, _} = full_lifecycle()
      ticket = state["tickets"]["T1"]

      assert ticket["active_attempt_id"] == nil
      assert ticket["prior_attempt_ids"] == ["A1"]
      assert Map.has_key?(ticket["attempts"], "A1")
      assert map_size(ticket["attempts"]["A1"]["executions"]) == 4
    end

    test "a launch cannot overwrite an attempt that already exists" do
      {state, sequence} = checking()

      reused =
        event("launch_planned", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => authority("X2")
        })

      # Refused on the phase guard before identity is even considered; the ticket is not
      # queued while a candidate is under check.
      assert {:error, :wrong_source_phase} = WorkflowKernel.apply(state, reused)
    end
  end

  describe "R4a settlement keeps the attempt and consumes an ordinal" do
    test "a developer non-start returns the ticket to queued with the same attempt" do
      {state, _} =
        drive(admitted(), [
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
          {"launch_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "X1",
             "settlement" => %{"schema_version" => 1}
           }}
        ])

      ticket = state["tickets"]["T1"]
      assert ticket["phase"] == "queued"
      assert ticket["resume_phase"] == "developing"
      assert ticket["reason"] == "developer_launch_non_started"
      assert ticket["active_attempt_id"] == "A1"
      assert ticket["attempts"]["A1"]["phase"] == "active"
      assert ticket["infrastructure"]["ordinal"] == 1
      assert ticket["attempts"]["A1"]["executions"]["X1"]["lifecycle"] == "closed"
    end

    test "a reviewer non-start returns the same frozen candidate to awaiting_review" do
      {state, _} =
        drive(reviewing(), [
          {"review_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "R1",
             "settlement" => %{"schema_version" => 1}
           }}
        ])

      ticket = state["tickets"]["T1"]
      assert ticket["phase"] == "awaiting_review"
      assert ticket["attempts"]["A1"]["phase"] == "awaiting_review"
      assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
      assert ticket["infrastructure"]["ordinal"] == 1
    end
  end

  describe "the control entity is a singleton, orthogonal to ticket phase" do
    test "control changes apply to the fixed control identifier" do
      {state, _} =
        drive({State.new(), 0}, [
          {"control_changed", "control",
           %{
             "paused" => true,
             "draining" => false,
             "stop_status" => "running",
             "control" => %{
               "schema_version" => 1,
               "control_id" => "ctl-1",
               "control_revision" => 4
             }
           }}
        ])

      assert state["control"]["paused"]
      assert state["control"]["control_revision"] == 4
    end

    test "a control event addressed to any other identifier is refused" do
      forged =
        event("control_changed", "control", 0, 1, %{
          "paused" => true,
          "draining" => false,
          "stop_status" => "running",
          "control" => %{"schema_version" => 1, "control_id" => "ctl-1", "control_revision" => 1}
        })
        |> Map.put("entity_id", "T1")

      assert {:error, :invalid_control_entity} = WorkflowKernel.apply(State.new(), forged)
    end

    test "a caller-shaped control fact cannot stand in for the protected one" do
      forged =
        event("control_changed", "control", 0, 1, %{
          "paused" => true,
          "draining" => false,
          "stop_status" => "running",
          "control" => %{"control_id" => "ctl-1", "control_revision" => 1}
        })

      assert {:error, :invalid_control_fact} = WorkflowKernel.apply(State.new(), forged)
    end
  end

  describe "the event vocabulary is closed and exactly covered" do
    test "every type has an exact payload key set and an entity kind" do
      for type <- Event.types() do
        assert {:ok, keys} = Event.payload_keys(type)
        assert keys == Enum.uniq(keys)
        assert {:ok, kind} = Event.entity_kind(type)
        assert kind in ~w(ticket objective control)
      end
    end

    test "the kernel covers every durable lifecycle type, and 22 are not yet durable" do
      # The kernel's vocabulary must be a superset of the durable one, or a type the store
      # already accepts would have no reducer. The converse gap is the extension FR-08B
      # still owes: these 22 names cannot be persisted until RecordCodec's lifecycle set
      # grows, which gates subcommit 2. Asserting the exact number keeps that extension a
      # deliberate act rather than something discovered when a write fails.
      durable = PramanaFoundry.DurableStore.RecordCodec.lifecycle_event_types()

      assert durable -- Event.types() == [],
             "a durable lifecycle type has no reducer clause"

      assert length(Event.types() -- durable) == 22
    end

    test "a payload missing or gaining one key is rejected" do
      base = %{
        "ticket_id" => "T1",
        "objective_id" => nil,
        "spec_revision_id" => "spec-1",
        "spec" => %{},
        "phase" => "queued",
        "reason" => nil
      }

      assert :ok = Event.validate(event("ticket_admitted", "T1", 0, 1, base))

      assert {:error, :invalid_semantic_event} =
               Event.validate(event("ticket_admitted", "T1", 0, 1, Map.delete(base, "reason")))

      assert {:error, :invalid_semantic_event} =
               Event.validate(event("ticket_admitted", "T1", 0, 1, Map.put(base, "extra", 1)))
    end

    test "a template admits a binding marker where a bound event carries a fact" do
      planned =
        event("launch_planned", "T1", 0, 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => %{"binding" => "authority"}
        })

      assert :ok = Event.validate(planned, template: true)
      assert {:error, :invalid_semantic_event} = Event.validate(planned)
    end

    test "a marker-shaped value with an extra key is not a marker" do
      planned =
        event("launch_planned", "T1", 0, 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => %{"binding" => "authority", "value" => "forged"}
        })

      assert {:error, :invalid_semantic_event} = Event.validate(planned, template: true)
    end
  end

  # ── Longer lifecycles used by several tests ────────────────────────────────────────

  defp reviewing do
    drive(checking(), [
      {"check_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "authority" => authority("K1")
       }},
      {"check_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "status" => "passed",
         "reason_code" => nil
       }},
      {"review_planned", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("R1")}}
    ])
  end

  defp full_lifecycle do
    drive(reviewing(), [
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "R1",
         "last_accepted_sequence" => 3
       }},
      {"review_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "verdict" => "approved"
       }},
      {"reviewer_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}},
      {"worker_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "K1"}},
      {"integration_planned", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("I1")}},
      {"integration_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "I1",
         "outcome" => "ref_created",
         "ref_receipt_id" => "ref-1"
       }},
      {"attempt_settled", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "disposition" => "integrated",
         "reason_code" => nil,
         "settlement" => %{"schema_version" => 1}
       }}
    ])
  end
end
