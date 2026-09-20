defmodule PramanaFoundry.Workflow.Kernel do
  @moduledoc """
  Deterministic FR-08B domain decision function and sole domain event reducer.

  `decide/3` performs no I/O and requires time, identities, observations and protected
  authority facts as explicit immutable inputs. `apply/2` is used for both live state
  and replay. Protected facts are reduced to opaque bindings; this state can neither
  represent nor manufacture root balances, claims, receipts or acceptance pointers.
  """

  import Kernel, except: [apply: 2]

  alias PramanaFoundry.Workflow.Kernel.State

  @command_types ~w(legacy_event_append enqueue steer pause resume cancel reset propose submit_artifact submit_review request_effect record_receipt)
  @ticket_phases ~w(draft queued developing awaiting_review reviewing ready_to_integrate integrating integrated blocked exhausted rejected cancelled)
  @terminal_phases ~w(integrated rejected cancelled)
  @roles ~w(developer reviewer pm check integration)
  @reserved_payload_keys ~w(authority authority_facts claim_status ledger_balance policy_valid protected protected_facts receipt_valid root root_facts)
  @binding_keys ~w(policy_id policy_revision control_id control_revision ledger_id ledger_generation dimension candidate_id check_set_id review_id receipt_id claim_id)
  @protected_input_keys ~w(admission allocation candidate candidate_id check_retry check_set_id checks claim_id cleanup control control_id control_revision developer_allocation dimension draining failure_class freeze generation_change infrastructure_generation infrastructure_limit infrastructure_ordinal integration integration_retry ledger_generation ledger_id outstanding_work owned_work pm_reservation policy_id policy_revision predecessor_effect_id prior_workers receipt_id ref_update reservation resume retry review_id settlement reason)

  @guard_matrix [
    %{row: 1, source: "objective_without_spec", command: "steer:create_objective"},
    %{row: 2, source: "draft", command: "enqueue"},
    %{row: 3, source: "queued|blocked", command: "propose:amend|park"},
    %{row: 4, source: "queued", command: "request_effect:developer"},
    %{row: 5, source: "developing", command: "submit_artifact:valid"},
    %{row: 6, source: "developing|awaiting_review", command: "steer:freeze_failed"},
    %{row: 7, source: "awaiting_review", command: "steer:developer_closed"},
    %{row: 8, source: "developing", command: "submit_artifact:none"},
    %{row: 9, source: "developing", command: "submit_artifact:blocked|partial"},
    %{row: 10, source: "developing", command: "submit_artifact:invalid"},
    %{row: 11, source: "awaiting_review", command: "steer:start_checks"},
    %{row: 12, source: "checking", command: "steer:check_result:passed"},
    %{row: 13, source: "checking", command: "steer:check_result:assertion_failed"},
    %{row: 14, source: "checking", command: "steer:check_result:infrastructure"},
    %{row: 15, source: "awaiting_review", command: "request_effect:reviewer"},
    %{row: 16, source: "reviewing", command: "submit_review:approved"},
    %{row: 17, source: "reviewing", command: "submit_review:changes_requested"},
    %{row: 18, source: "reviewing", command: "submit_review:rejected"},
    %{row: 19, source: "reviewing", command: "submit_review:none"},
    %{row: 20, source: "ready_to_integrate", command: "request_effect:integration"},
    %{row: 21, source: "ready_to_integrate|integrating", command: "steer:base_moved"},
    %{row: 22, source: "integrating", command: "record_receipt:integration:succeeded"},
    %{row: 23, source: "integrating", command: "record_receipt:integration:failed|unknown"},
    %{row: 24, source: "blocked", command: "steer:resume_ticket"},
    %{row: 25, source: "exhausted", command: "reset"},
    %{row: 26, source: "integrated|rejected|cancelled", command: "ordinary_lifecycle"},
    %{row: 27, source: "nonterminal", command: "cancel"},
    %{row: 28, source: "cancel_requested", command: "steer:finalize_cancel"}
  ]

  @type decision :: map()

  @spec new() :: map()
  defdelegate new(), to: State

  @spec supported_commands() :: [String.t()]
  def supported_commands, do: @command_types

  @spec guard_matrix() :: [map()]
  def guard_matrix, do: @guard_matrix

  @spec decide(map(), map(), map()) :: {:ok, decision()} | {:error, atom()}
  def decide(state, command, inputs) do
    with true <- State.valid?(state),
         {:ok, command} <- command(command),
         {:ok, inputs} <- inputs(inputs),
         true <- no_reserved_payload?(command["payload"]) do
      dispatch(state, command, inputs)
    else
      false -> {:error, :invalid_domain_input}
      {:error, _reason} = error -> error
    end
  end

  @spec apply(map(), map()) :: {:ok, map()} | {:error, atom()}
  def apply(state, event) do
    with true <- State.valid?(state),
         {:ok, event} <- event(event),
         {:ok, next} <- apply_changes(state, event["changes"]),
         next <- Map.put(next, "last_event_id", event["event_id"]),
         true <- State.valid?(next) do
      {:ok, next}
    else
      false -> {:error, :invalid_domain_state}
      {:error, _reason} = error -> error
    end
  end

  @spec rebuild([map()]) :: {:ok, map()} | {:error, atom()}
  def rebuild(events) when is_list(events),
    do: Enum.reduce_while(events, {:ok, new()}, &rebuild_event/2)

  def rebuild(_events), do: {:error, :invalid_event_stream}

  defp rebuild_event(event, {:ok, state}) do
    case apply(state, event) do
      {:ok, next} -> {:cont, {:ok, next}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp dispatch(_state, %{"type" => "legacy_event_append"}, _inputs),
    do: rejected("legacy_jsonl_not_authoritative")

  defp dispatch(state, %{"type" => "pause"} = command, inputs),
    do: control(state, command, inputs, "paused", true, "workflow_paused")

  defp dispatch(state, %{"type" => "resume"} = command, inputs) do
    case command["payload"]["operation"] do
      "clear_drain" -> control(state, command, inputs, "draining", false, "drain_cleared")
      "workflow" -> control(state, command, inputs, "paused", false, "workflow_resumed")
      _ -> rejected("unsupported_resume_operation")
    end
  end

  defp dispatch(state, %{"type" => "enqueue"} = command, inputs),
    do: enqueue(state, command, inputs)

  defp dispatch(state, %{"type" => "steer"} = command, inputs),
    do: steer(state, command, inputs)

  defp dispatch(state, %{"type" => "propose"} = command, inputs),
    do: propose(state, command, inputs)

  defp dispatch(state, %{"type" => "request_effect"} = command, inputs),
    do: request_effect(state, command, inputs)

  defp dispatch(state, %{"type" => "submit_artifact"} = command, inputs),
    do: submit_artifact(state, command, inputs)

  defp dispatch(state, %{"type" => "submit_review"} = command, inputs),
    do: submit_review(state, command, inputs)

  defp dispatch(state, %{"type" => "record_receipt"} = command, inputs),
    do: record_receipt(state, command, inputs)

  defp dispatch(state, %{"type" => "cancel"} = command, inputs),
    do: cancel(state, command, inputs)

  defp dispatch(state, %{"type" => "reset"} = command, inputs),
    do: reset(state, command, inputs)

  defp dispatch(_state, _command, _inputs), do: rejected("unsupported_command")

  # R4 rows 1-3: objectives, common admission and PM evidence.
  defp enqueue(state, command, inputs) do
    ticket_id = target(command, "ticket_id")
    payload = command["payload"]
    facts = inputs["protected"]

    cond do
      not identity?(ticket_id) or not identity?(target(command, "objective_id")) or
          not identity?(inputs["ids"]["spec_revision_id"]) ->
        rejected("missing_admission_identity")

      Map.has_key?(state["tickets"], ticket_id) ->
        rejected("ticket_already_exists")

      state["control"]["draining"] ->
        blocked("draining")

      facts["admission"] not in ["eligible", "blocked"] ->
        rejected("missing_admission_fact")

      not valid_spec?(payload["spec"]) ->
        rejected("malformed_spec")

      true ->
        phase = if facts["admission"] == "eligible", do: "queued", else: "blocked"

        ticket = %{
          "ticket_id" => ticket_id,
          "objective_id" => target(command, "objective_id"),
          "phase" => phase,
          "resume_phase" => if(phase == "blocked", do: "queued", else: nil),
          "reason" =>
            if(phase == "blocked", do: facts["reason"] || "admission_blocked", else: nil),
          "spec_revision_id" => inputs["ids"]["spec_revision_id"],
          "spec" => payload["spec"],
          "attempt" => nil,
          "prior_attempts" => [],
          "cancel_status" => nil,
          "authority_bindings" => bindings(facts),
          "history" => []
        }

        accepted(inputs, "ticket_admitted", [change("ticket", ticket_id, ticket)])
    end
  end

  defp steer(state, command, inputs) do
    operation = command["payload"]["operation"]

    case operation do
      "create_objective" -> create_objective(state, command, inputs)
      "amend" -> amend_or_park(state, command, inputs, :amend)
      "park" -> amend_or_park(state, command, inputs, :park)
      "block" -> public_block(state, command, inputs)
      "resume_ticket" -> resume_ticket(state, command, inputs)
      "developer_closed" -> developer_closed(state, command, inputs)
      "freeze_failed" -> freeze_failed(state, command, inputs)
      "start_checks" -> start_checks(state, command, inputs)
      "check_result" -> check_result(state, command, inputs)
      "reviewer_closed" -> reviewer_closed(state, command, inputs)
      "base_moved" -> base_moved(state, command, inputs)
      "finalize_cancel" -> finalize_cancel(state, command, inputs)
      "drain" -> control(state, command, inputs, "draining", true, "drain_started")
      "stop" -> stop(state, command, inputs)
      _ -> rejected("unsupported_steering_operation")
    end
  end

  defp create_objective(state, command, inputs) do
    objective_id = target(command, "objective_id")

    cond do
      not identity?(objective_id) or not identity?(inputs["ids"]["planning_owner_id"]) ->
        rejected("missing_objective_identity")

      Map.has_key?(state["objectives"], objective_id) ->
        rejected("objective_already_exists")

      inputs["protected"]["pm_reservation"] != "reserved" ->
        blocked("pm_budget")

      true ->
        objective = %{
          "objective_id" => objective_id,
          "phase" => "draft",
          "planning_owner_id" => inputs["ids"]["planning_owner_id"],
          "authority_bindings" => bindings(inputs["protected"])
        }

        accepted(inputs, "objective_created", [change("objective", objective_id, objective)])
    end
  end

  defp amend_or_park(state, command, inputs, operation) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         true <- ticket["phase"] in ~w(queued blocked) do
      next =
        case operation do
          :amend ->
            case inputs["ids"]["spec_revision_id"] do
              id when is_binary(id) and id != "" ->
                ticket
                |> Map.put("spec_revision_id", id)
                |> Map.put("spec", command["payload"]["spec"])

              _ ->
                nil
            end

          :park ->
            ticket
            |> Map.put("phase", "blocked")
            |> Map.put("resume_phase", ticket["phase"])
            |> Map.put("reason", command["payload"]["reason"] || "parked")
        end

      if is_map(next) and (operation == :park or valid_spec?(next["spec"])) do
        accepted(inputs, "ticket_#{operation}ed", [change("ticket", ticket_id, next)])
      else
        rejected("malformed_spec")
      end
    else
      false -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  defp propose(state, command, inputs) do
    objective_id = target(command, "objective_id")
    proposal_id = inputs["ids"]["proposal_id"]
    operation = command["payload"]["operation"]

    cond do
      not identity?(objective_id) or not identity?(proposal_id) ->
        rejected("missing_proposal_identity")

      operation not in ~w(create amend park prioritize block) ->
        rejected("unsupported_proposal")

      not Map.has_key?(state["objectives"], objective_id) ->
        rejected("unknown_objective")

      true ->
        proposal = %{
          "proposal_id" => proposal_id,
          "objective_id" => objective_id,
          "operation" => operation,
          "status" => "evidence_only",
          "recorded_at" => inputs["recorded_at"]
        }

        accepted(inputs, "pm_proposal_recorded", [change("pm", proposal_id, proposal)])
    end
  end

  # R4 rows 4, 11, 15 and 20 plus R4a pre-intent denial.
  defp request_effect(state, command, inputs) do
    role = command["payload"]["role"]
    outcome = inputs["observation"]["outcome"]

    if role not in @roles do
      rejected("unsupported_role")
    else
      case role do
        "pm" -> request_pm_launch(state, command, inputs, outcome)
        _ -> request_ticket_effect(state, command, inputs, role, outcome)
      end
    end
  end

  defp request_pm_launch(state, command, inputs, "pre_intent_denied") do
    objective_id = target(command, "objective_id")

    if Map.has_key?(state["objectives"], objective_id),
      do: blocked(inputs["observation"]["reason"] || "launch_ineligible"),
      else: rejected("unknown_objective")
  end

  defp request_pm_launch(state, command, inputs, "admitted") do
    objective_id = target(command, "objective_id")
    objective = state["objectives"][objective_id]

    cond do
      is_nil(objective) ->
        rejected("unknown_objective")

      state["control"]["paused"] ->
        blocked("paused")

      state["control"]["draining"] ->
        blocked("draining")

      get_in(state, ["pm", objective_id, "status"]) in ~w(pending unknown) ->
        blocked("pm_execution_outstanding")

      not effect_ids?(inputs) ->
        rejected("missing_effect_identity")

      inputs["protected"]["reservation"] != "reserved" ->
        blocked("pm_budget")

      true ->
        pm = execution(inputs, "pm", objective_id, nil)
        accepted(inputs, "pm_launch_requested", [change("pm", objective_id, pm)])
    end
  end

  defp request_pm_launch(_state, _command, _inputs, _outcome),
    do: rejected("invalid_admission_outcome")

  defp request_ticket_effect(state, command, inputs, role, outcome) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         :ok <- phase_guard(ticket, role) do
      cond do
        outcome == "pre_intent_denied" ->
          blocked(inputs["observation"]["reason"] || "launch_ineligible")

        outcome != "admitted" ->
          rejected("invalid_admission_outcome")

        state["control"]["paused"] ->
          blocked("paused")

        state["control"]["draining"] and role == "developer" ->
          blocked("draining")

        ticket["cancel_status"] == "cancel_requested" ->
          blocked("cancel_requested")

        not effect_ids?(inputs) ->
          rejected("missing_effect_identity")

        role == "developer" and is_nil(ticket["attempt"]) and
            not identity?(inputs["ids"]["attempt_id"]) ->
          rejected("missing_attempt_identity")

        inputs["protected"]["reservation"] != "reserved" ->
          blocked("#{role}_budget")

        true ->
          admit_effect(ticket_id, ticket, role, inputs)
      end
    else
      {:error, reason} -> rejected(reason)
    end
  end

  defp admit_effect(ticket_id, ticket, "developer", inputs) do
    attempt =
      case ticket["attempt"] do
        %{"phase" => "active", "resume_phase" => "developing"} = retained -> retained
        _ -> new_attempt(inputs, ticket)
      end

    attempt =
      put_execution(attempt, execution(inputs, "developer", ticket_id, attempt["attempt_id"]))

    next =
      ticket
      |> Map.put("phase", "developing")
      |> Map.put("resume_phase", nil)
      |> Map.put("reason", nil)
      |> Map.put("attempt", attempt)

    accepted(inputs, "developer_launch_requested", [change("ticket", ticket_id, next)])
  end

  defp admit_effect(ticket_id, ticket, "reviewer", inputs) do
    attempt =
      ticket["attempt"]
      |> put_execution(execution(inputs, "reviewer", ticket_id, ticket["attempt"]["attempt_id"]))
      |> Map.put("phase", "reviewing")

    next = ticket |> Map.put("phase", "reviewing") |> Map.put("attempt", attempt)
    accepted(inputs, "reviewer_launch_requested", [change("ticket", ticket_id, next)])
  end

  defp admit_effect(ticket_id, ticket, role, inputs) when role in ~w(check integration) do
    attempt =
      ticket["attempt"]
      |> put_execution(execution(inputs, role, ticket_id, ticket["attempt"]["attempt_id"]))
      |> Map.put("phase", if(role == "check", do: "checking", else: "integrating"))

    phase = if role == "check", do: "awaiting_review", else: "integrating"
    next = ticket |> Map.put("phase", phase) |> Map.put("attempt", attempt)
    accepted(inputs, "#{role}_launch_requested", [change("ticket", ticket_id, next)])
  end

  # R4 rows 5, 9 and 10. The public blocked/partial result is an accepted
  # lifecycle transition; malformed input is a durable rejection with no event.
  defp submit_artifact(state, command, inputs) do
    result = command["payload"]["result"]

    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         true <- ticket["phase"] == "developing",
         true <- identity?(inputs["ids"]["observation_id"]) do
      case result do
        "valid" ->
          freeze_candidate(ticket_id, ticket, inputs)

        verdict when verdict in ~w(blocked partial) ->
          block_from_result(ticket_id, ticket, inputs, verdict)

        "invalid" ->
          rejected("invalid_submission")

        "none" ->
          execution_without_result(ticket_id, ticket, inputs)

        _ ->
          rejected("malformed_submission")
      end
    else
      false -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  defp freeze_candidate(ticket_id, ticket, inputs) do
    candidate_id = inputs["ids"]["candidate_id"]

    if identity?(candidate_id) and inputs["protected"]["candidate"] == "frozen" do
      attempt =
        ticket["attempt"]
        |> Map.put("phase", "candidate_frozen")
        |> Map.put("candidate_id", candidate_id)
        |> Map.put("productive_sealed", true)

      next = ticket |> Map.put("phase", "awaiting_review") |> Map.put("attempt", attempt)
      accepted(inputs, "candidate_frozen", [change("ticket", ticket_id, next)])
    else
      rejected("candidate_not_root_verified")
    end
  end

  defp block_from_result(ticket_id, ticket, inputs, verdict) do
    attempt = terminal_attempt(ticket["attempt"], "blocked")

    next =
      ticket
      |> Map.put("phase", "blocked")
      |> Map.put("resume_phase", nil)
      |> Map.put("reason", "developer_#{verdict}")
      |> Map.put("attempt", attempt)

    accepted(inputs, "developer_#{verdict}", [change("ticket", ticket_id, next)])
  end

  defp execution_without_result(ticket_id, ticket, inputs) do
    observation = inputs["observation"]

    if observation["stream"] == "sealed" and observation["termination"] in ~w(exited timed_out) do
      disposition = if observation["termination"] == "timed_out", do: "timed_out", else: "failed"
      attempt = terminal_attempt(ticket["attempt"], disposition)

      next =
        if inputs["protected"]["retry"] == "eligible" do
          ticket
          |> Map.put("phase", "queued")
          |> Map.put("reason", disposition)
          |> Map.put("attempt", attempt)
        else
          ticket
          |> Map.put("phase", "exhausted")
          |> Map.put("reason", "developer_budget")
          |> Map.put("attempt", %{attempt | "disposition" => "exhausted"})
        end

      accepted(inputs, "developer_#{disposition}", [change("ticket", ticket_id, next)])
    else
      blocked("stream_completeness_unknown")
    end
  end

  # R4 rows 12-19: check/review exact-candidate custody and overwrite guards.
  defp start_checks(state, command, inputs) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         true <- ticket["phase"] == "awaiting_review",
         %{"phase" => "candidate_frozen", "candidate_id" => candidate_id} = attempt <-
           ticket["attempt"],
         true <- inputs["protected"]["candidate_id"] == candidate_id do
      next_attempt = attempt |> Map.put("phase", "checking") |> Map.put("checks", %{})
      next = Map.put(ticket, "attempt", next_attempt)
      accepted(inputs, "checks_started", [change("ticket", ticket_id, next)])
    else
      false -> rejected("source_state_guard")
      nil -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  defp check_result(state, command, inputs) do
    verdict = command["payload"]["verdict"]

    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         %{"phase" => "checking"} = attempt <- ticket["attempt"] do
      check_result_decision(ticket_id, ticket, attempt, verdict, inputs)
    else
      nil -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  defp check_result_decision(ticket_id, ticket, attempt, "passed", inputs) do
    if inputs["protected"]["checks"] == "complete" do
      next_attempt =
        attempt
        |> Map.put("phase", "awaiting_review")
        |> Map.put("check_set_id", inputs["protected"]["check_set_id"])

      next = ticket |> Map.put("phase", "awaiting_review") |> Map.put("attempt", next_attempt)
      accepted(inputs, "checks_passed", [change("ticket", ticket_id, next)])
    else
      rejected("checks_not_root_verified")
    end
  end

  defp check_result_decision(ticket_id, ticket, attempt, "assertion_failed", inputs) do
    next_attempt = terminal_attempt(attempt, "needs_correction")

    {phase, reason} =
      cond do
        inputs["protected"]["developer_allocation"] != "eligible" ->
          {"exhausted", "developer_budget"}

        inputs["protected"]["draining"] == true ->
          {"blocked", "draining"}

        true ->
          {"queued", "check_assertion_failed"}
      end

    next =
      ticket
      |> Map.put("phase", phase)
      |> Map.put("reason", reason)
      |> Map.put("attempt", next_attempt)

    accepted(inputs, "checks_failed", [change("ticket", ticket_id, next)])
  end

  defp check_result_decision(ticket_id, ticket, attempt, verdict, inputs)
       when verdict in ~w(infrastructure_failed timed_out unknown) do
    reason = if verdict == "unknown", do: "check_unknown", else: "check_infrastructure"

    phase =
      if inputs["protected"]["check_retry"] == "eligible" and verdict != "unknown",
        do: "awaiting_review",
        else: "blocked"

    next_attempt = Map.put(attempt, "phase", "checking")

    next =
      ticket
      |> Map.put("phase", phase)
      |> Map.put("resume_phase", "awaiting_review")
      |> Map.put("reason", reason)
      |> Map.put("attempt", next_attempt)

    accepted(inputs, "check_#{verdict}", [change("ticket", ticket_id, next)])
  end

  defp check_result_decision(_ticket_id, _ticket, _attempt, _verdict, _inputs),
    do: rejected("invalid_check_verdict")

  defp submit_review(state, command, inputs) do
    verdict = command["payload"]["verdict"]

    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         true <- ticket["phase"] == "reviewing",
         attempt when is_map(attempt) <- ticket["attempt"],
         true <- identity?(inputs["ids"]["review_id"]),
         true <- inputs["protected"]["candidate_id"] == attempt["candidate_id"] do
      review_decision(ticket_id, ticket, attempt, verdict, inputs)
    else
      false -> rejected("source_state_guard")
      nil -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  defp review_decision(ticket_id, ticket, attempt, "approved", inputs) do
    next_attempt =
      attempt
      |> Map.put("review_verdict", "approved")
      |> Map.put("review_id", inputs["ids"]["review_id"])

    next = Map.put(ticket, "attempt", next_attempt)
    accepted(inputs, "review_approved", [change("ticket", ticket_id, next)])
  end

  defp review_decision(ticket_id, ticket, attempt, "changes_requested", inputs) do
    next_attempt =
      terminal_attempt(attempt, "needs_correction")
      |> Map.put("review_id", inputs["ids"]["review_id"])

    phase = if inputs["protected"]["draining"] == true, do: "blocked", else: "queued"
    reason = if phase == "blocked", do: "draining", else: "review_changes_requested"

    next =
      ticket
      |> Map.put("phase", phase)
      |> Map.put("reason", reason)
      |> Map.put("attempt", next_attempt)

    accepted(inputs, "review_changes_requested", [change("ticket", ticket_id, next)])
  end

  defp review_decision(ticket_id, ticket, attempt, "rejected", inputs) do
    next_attempt =
      terminal_attempt(attempt, "rejected") |> Map.put("review_id", inputs["ids"]["review_id"])

    next = ticket |> Map.put("phase", "rejected") |> Map.put("attempt", next_attempt)
    accepted(inputs, "review_rejected", [change("ticket", ticket_id, next)])
  end

  defp review_decision(_ticket_id, _ticket, _attempt, "none", inputs) do
    if inputs["observation"]["stream"] == "sealed",
      do: blocked("review_retry_required"),
      else: blocked("review_stream_open")
  end

  defp review_decision(_ticket_id, _ticket, _attempt, _verdict, _inputs),
    do: rejected("malformed_review")

  defp reviewer_closed(state, command, inputs) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         true <- ticket["phase"] == "reviewing",
         %{"review_verdict" => "approved"} = attempt <- ticket["attempt"],
         true <- inputs["observation"]["termination"] == "verified_closed" do
      next_attempt = Map.put(attempt, "phase", "ready_to_integrate")
      next = ticket |> Map.put("phase", "ready_to_integrate") |> Map.put("attempt", next_attempt)
      accepted(inputs, "reviewer_closed", [change("ticket", ticket_id, next)])
    else
      false -> rejected("source_state_guard")
      nil -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  # R4a plus integration receipts. Protected settlement truth is required as input
  # and only an immutable reference is retained in domain state.
  defp record_receipt(state, command, inputs) do
    role = command["payload"]["role"]
    outcome = command["payload"]["outcome"]

    cond do
      role not in @roles ->
        rejected("unsupported_role")

      outcome not in ~w(succeeded failed non_started unknown) ->
        rejected("invalid_receipt_outcome")

      not receipt_ids?(inputs) ->
        rejected("missing_receipt_identity")

      inputs["protected"]["settlement"] != outcome ->
        rejected("receipt_not_root_verified")

      role == "pm" ->
        pm_receipt(state, command, inputs, outcome)

      true ->
        ticket_receipt(state, command, inputs, role, outcome)
    end
  end

  defp ticket_receipt(state, command, inputs, role, outcome) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         attempt when is_map(attempt) <- ticket["attempt"],
         execution when is_map(execution) <-
           find_execution(attempt, inputs["ids"]["execution_id"], role),
         true <- execution["status"] != "closed" do
      launch_receipt_decision(ticket_id, ticket, attempt, execution, role, outcome, inputs)
    else
      false -> rejected("execution_already_settled")
      nil -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  defp launch_receipt_decision(ticket_id, ticket, attempt, execution, role, "unknown", inputs) do
    updated =
      Map.merge(execution, %{
        "status" => "unknown",
        "settlement_binding" => bindings(inputs["protected"])
      })

    next_attempt = replace_execution(attempt, updated)

    next =
      ticket |> Map.put("reason", "#{role}_launch_unknown") |> Map.put("attempt", next_attempt)

    accepted(inputs, "#{role}_launch_unknown", [change("ticket", ticket_id, next)])
  end

  defp launch_receipt_decision(ticket_id, ticket, attempt, execution, role, "non_started", inputs) do
    ordinal = inputs["protected"]["infrastructure_ordinal"]
    limit = inputs["protected"]["infrastructure_limit"]
    allocation = inputs["protected"]["allocation"]

    if positive_integer?(ordinal) and positive_integer?(limit) and
         allocation in ~w(eligible exhausted blocked) do
      updated =
        Map.merge(execution, %{
          "status" => "closed",
          "result" => "non_started",
          "settlement_binding" => bindings(inputs["protected"])
        })

      next_attempt = attempt |> replace_execution(updated) |> put_infrastructure(role, inputs)

      {phase, resume_phase, reason, final_attempt} =
        nonstart_outcome(role, next_attempt, ordinal, limit, allocation, ticket)

      next =
        ticket
        |> Map.put("phase", phase)
        |> Map.put("resume_phase", resume_phase)
        |> Map.put("reason", reason)
        |> Map.put("attempt", final_attempt)

      accepted(inputs, "#{role}_launch_non_started", [change("ticket", ticket_id, next)])
    else
      rejected("invalid_non_start_settlement")
    end
  end

  defp launch_receipt_decision(ticket_id, ticket, attempt, execution, role, outcome, inputs)
       when outcome in ~w(succeeded failed) do
    case {role, outcome} do
      {"integration", "succeeded"} ->
        integrate_success(ticket_id, ticket, attempt, execution, inputs)

      {"integration", "failed"} ->
        integration_failed(ticket_id, ticket, attempt, execution, inputs)

      _ ->
        updated =
          Map.merge(execution, %{
            "status" => if(outcome == "succeeded", do: "running", else: "closed"),
            "result" => outcome,
            "settlement_binding" => bindings(inputs["protected"])
          })

        next = Map.put(ticket, "attempt", replace_execution(attempt, updated))
        accepted(inputs, "#{role}_launch_#{outcome}", [change("ticket", ticket_id, next)])
    end
  end

  defp integration_failed(ticket_id, ticket, attempt, execution, inputs) do
    updated =
      Map.merge(execution, %{
        "status" => "closed",
        "result" => "failed",
        "settlement_binding" => bindings(inputs["protected"])
      })

    {phase, resume_phase, reason} =
      case inputs["protected"]["integration_retry"] do
        "eligible" -> {"integrating", nil, "integration_retry"}
        _ -> {"blocked", "integrating", "integration_failure"}
      end

    next =
      ticket
      |> Map.put("phase", phase)
      |> Map.put("resume_phase", resume_phase)
      |> Map.put("reason", reason)
      |> Map.put("attempt", replace_execution(attempt, updated))

    accepted(inputs, "integration_failed", [change("ticket", ticket_id, next)])
  end

  defp integrate_success(ticket_id, ticket, attempt, execution, inputs) do
    if inputs["protected"]["ref_update"] == "succeeded" and
         inputs["protected"]["prior_workers"] == "closed" do
      updated =
        Map.merge(execution, %{
          "status" => "closed",
          "result" => "succeeded",
          "settlement_binding" => bindings(inputs["protected"])
        })

      next_attempt = attempt |> replace_execution(updated) |> terminal_attempt("integrated")
      next = ticket |> Map.put("phase", "integrated") |> Map.put("attempt", next_attempt)
      accepted(inputs, "ticket_integrated", [change("ticket", ticket_id, next)])
    else
      blocked("integration_prerequisites_open")
    end
  end

  defp nonstart_outcome("developer", attempt, ordinal, limit, allocation, _ticket) do
    cond do
      allocation == "exhausted" ->
        {"exhausted", nil, "developer_budget", terminal_attempt(attempt, "exhausted")}

      allocation == "blocked" ->
        {"blocked", "developing", "developer_budget",
         Map.put(attempt, "resume_phase", "developing")}

      ordinal >= limit ->
        {"blocked", "developing", "developer_launch_infrastructure",
         Map.put(attempt, "resume_phase", "developing")}

      true ->
        {"queued", "developing", "developer_launch_non_started",
         Map.put(attempt, "resume_phase", "developing")}
    end
  end

  defp nonstart_outcome("reviewer", attempt, ordinal, limit, allocation, _ticket) do
    cond do
      allocation == "exhausted" ->
        {"blocked", "awaiting_review", "reviewer_budget",
         Map.put(attempt, "phase", "awaiting_review")}

      allocation == "blocked" ->
        {"blocked", "awaiting_review", "reviewer_budget",
         Map.put(attempt, "phase", "awaiting_review")}

      ordinal >= limit ->
        {"blocked", "awaiting_review", "reviewer_launch_infrastructure",
         Map.put(attempt, "phase", "awaiting_review")}

      true ->
        {"awaiting_review", nil, "reviewer_launch_non_started",
         Map.put(attempt, "phase", "awaiting_review")}
    end
  end

  defp nonstart_outcome(role, attempt, _ordinal, _limit, _allocation, ticket)
       when role in ~w(check integration) do
    {ticket["phase"], ticket["resume_phase"], "#{role}_launch_non_started", attempt}
  end

  defp pm_receipt(state, command, inputs, outcome) do
    objective_id = target(command, "objective_id")
    owner = state["pm"][objective_id]

    cond do
      not is_map(owner) ->
        rejected("source_state_guard")

      owner["execution_id"] != inputs["ids"]["execution_id"] ->
        rejected("execution_identity_mismatch")

      outcome == "unknown" ->
        next =
          owner
          |> Map.put("status", "unknown")
          |> Map.put("settlement_binding", bindings(inputs["protected"]))

        accepted(inputs, "pm_launch_unknown", [change("pm", objective_id, next)])

      outcome == "non_started" ->
        ordinal = inputs["protected"]["infrastructure_ordinal"]
        limit = inputs["protected"]["infrastructure_limit"]

        if positive_integer?(ordinal) and positive_integer?(limit) do
          status = if ordinal >= limit, do: "blocked", else: "queued"

          reason =
            if ordinal >= limit, do: "pm_launch_infrastructure", else: "pm_launch_non_started"

          next =
            owner
            |> Map.put("status", status)
            |> Map.put("reason", reason)
            |> Map.put("infrastructure", infrastructure("pm", inputs))
            |> Map.put("settlement_binding", bindings(inputs["protected"]))

          accepted(inputs, "pm_launch_non_started", [change("pm", objective_id, next)])
        else
          rejected("invalid_non_start_settlement")
        end

      true ->
        next =
          owner
          |> Map.put("status", outcome)
          |> Map.put("settlement_binding", bindings(inputs["protected"]))

        accepted(inputs, "pm_launch_#{outcome}", [change("pm", objective_id, next)])
    end
  end

  # R4 rows 20-23.
  defp base_moved(state, command, inputs) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         true <- ticket["phase"] in ~w(ready_to_integrate integrating) do
      attempt = terminal_attempt(ticket["attempt"], "superseded_base")

      phase =
        if inputs["protected"]["developer_allocation"] == "eligible",
          do: "queued",
          else: "exhausted"

      next =
        ticket
        |> Map.put("phase", phase)
        |> Map.put("reason", "superseded_base")
        |> Map.put("attempt", attempt)

      accepted(inputs, "base_superseded", [change("ticket", ticket_id, next)])
    else
      false -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  # R4 rows 24-28 and global control behavior.
  defp public_block(state, command, inputs) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         false <- ticket["phase"] in @terminal_phases do
      attempt =
        if is_map(ticket["attempt"]),
          do: terminal_attempt(ticket["attempt"], "blocked"),
          else: nil

      next =
        ticket
        |> Map.put("phase", "blocked")
        |> Map.put("resume_phase", nil)
        |> Map.put("reason", command["payload"]["reason"] || "operator_blocked")
        |> Map.put("attempt", attempt)

      accepted(inputs, "ticket_blocked", [change("ticket", ticket_id, next)])
    else
      true -> rejected("terminal_ticket")
      {:error, reason} -> rejected(reason)
    end
  end

  defp resume_ticket(state, command, inputs) do
    with {:ok, ticket_id, %{"phase" => "blocked"} = ticket} <- mutable_ticket(state, command),
         resume_phase when resume_phase in @ticket_phases <- ticket["resume_phase"],
         "eligible" <- inputs["protected"]["resume"] do
      next =
        ticket
        |> Map.put("phase", resume_phase)
        |> Map.put("resume_phase", nil)
        |> Map.put("reason", nil)
        |> Map.put("authority_bindings", bindings(inputs["protected"]))

      accepted(inputs, "ticket_resumed", [change("ticket", ticket_id, next)])
    else
      nil -> rejected("missing_resume_phase")
      false -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
      _ -> blocked("resume_ineligible")
    end
  end

  defp cancel(state, command, inputs) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         false <- ticket["phase"] in @terminal_phases do
      next =
        ticket
        |> Map.put("cancel_status", "cancel_requested")
        |> Map.put("authority_bindings", bindings(inputs["protected"]))

      accepted(inputs, "cancellation_requested", [change("ticket", ticket_id, next)])
    else
      true -> rejected("terminal_ticket")
      {:error, reason} -> rejected(reason)
    end
  end

  defp finalize_cancel(state, command, inputs) do
    with {:ok, ticket_id, %{"cancel_status" => "cancel_requested"} = ticket} <-
           mutable_ticket(state, command),
         "terminal" <- inputs["protected"]["owned_work"],
         "reconciled" <- inputs["protected"]["cleanup"] do
      {phase, reason} =
        if inputs["protected"]["integration"] == "succeeded",
          do: {"integrated", "cancelled_after_integration"},
          else: {"cancelled", nil}

      attempt =
        if is_map(ticket["attempt"]), do: terminal_attempt(ticket["attempt"], phase), else: nil

      next =
        ticket
        |> Map.put("phase", phase)
        |> Map.put("reason", reason)
        |> Map.put("cancel_status", "cancel_finalized")
        |> Map.put("attempt", attempt)

      accepted(inputs, "cancellation_finalized", [change("ticket", ticket_id, next)])
    else
      {:error, reason} -> rejected(reason)
      _ -> blocked("cancellation_reconciliation_pending")
    end
  end

  defp reset(state, command, inputs) do
    with {:ok, ticket_id, %{"phase" => "exhausted"} = ticket} <- mutable_ticket(state, command),
         true <- inputs["protected"]["generation_change"] == "granted",
         generation when is_integer(generation) and generation >= 0 <-
           inputs["protected"]["ledger_generation"] do
      prior_attempts =
        if is_map(ticket["attempt"]),
          do: ticket["prior_attempts"] ++ [ticket["attempt"]],
          else: ticket["prior_attempts"]

      next =
        ticket
        |> Map.put("phase", "queued")
        |> Map.put("reason", nil)
        |> Map.put("attempt", nil)
        |> Map.put("prior_attempts", prior_attempts)
        |> Map.put("authority_bindings", bindings(inputs["protected"]))

      accepted(inputs, "ticket_generation_reset", [change("ticket", ticket_id, next)])
    else
      false -> rejected("reset_not_authorized")
      nil -> rejected("reset_not_authorized")
      {:error, reason} -> rejected(reason)
      _ -> rejected("invalid_generation_change")
    end
  end

  defp control(state, _command, inputs, field, value, event_type) do
    if inputs["protected"]["control"] == "committed" do
      control =
        state["control"]
        |> Map.put(field, value)
        |> Map.put("generation", state["control"]["generation"] + 1)

      accepted(inputs, event_type, [change("control", "global", control)])
    else
      rejected("control_not_root_verified")
    end
  end

  defp stop(state, _command, inputs) do
    if inputs["protected"]["control"] != "committed" do
      rejected("control_not_root_verified")
    else
      {status, reason} =
        case inputs["protected"]["outstanding_work"] do
          "none" -> {"stop_completed", nil}
          "unknown" -> {"stop_blocked", "unknown_work"}
          _ -> {"stop_requested", "outstanding_work"}
        end

      control =
        state["control"]
        |> Map.put("stop_status", status)
        |> Map.put("generation", state["control"]["generation"] + 1)

      accepted(inputs, "workflow_stop", [change("control", "global", control)], reason)
    end
  end

  defp developer_closed(state, command, inputs) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         true <- ticket["phase"] == "awaiting_review",
         %{"candidate_id" => candidate_id} <- ticket["attempt"],
         true <- identity?(candidate_id),
         true <- inputs["observation"]["termination"] == "verified_closed" do
      accepted(inputs, "developer_closed", [change("ticket", ticket_id, ticket)])
    else
      false -> rejected("source_state_guard")
      nil -> rejected("source_state_guard")
      {:error, reason} -> rejected(reason)
    end
  end

  defp freeze_failed(state, command, inputs) do
    with {:ok, ticket_id, ticket} <- mutable_ticket(state, command),
         true <- ticket["phase"] in ~w(developing awaiting_review),
         verdict when verdict in ~w(retry blocked unknown) <- inputs["protected"]["freeze"] do
      {phase, reason} =
        case verdict do
          "retry" -> {"awaiting_review", "freeze_retry"}
          "blocked" -> {"blocked", "freeze_failure"}
          "unknown" -> {"blocked", "freeze_unknown"}
        end

      next =
        ticket
        |> Map.put("phase", phase)
        |> Map.put("resume_phase", "awaiting_review")
        |> Map.put("reason", reason)

      accepted(inputs, "freeze_#{verdict}", [change("ticket", ticket_id, next)])
    else
      false -> rejected("source_state_guard")
      nil -> rejected("freeze_not_root_verified")
      {:error, reason} -> rejected(reason)
      _ -> rejected("freeze_not_root_verified")
    end
  end

  defp phase_guard(ticket, "developer") do
    if ticket["phase"] == "queued" or
         (ticket["phase"] == "blocked" and ticket["resume_phase"] == "developing"),
       do: :ok,
       else: {:error, "source_state_guard"}
  end

  defp phase_guard(ticket, "reviewer") do
    if ticket["phase"] == "awaiting_review" and is_map(ticket["attempt"]) and
         ticket["attempt"]["phase"] == "awaiting_review",
       do: :ok,
       else: {:error, "source_state_guard"}
  end

  defp phase_guard(ticket, "check") do
    if ticket["phase"] == "awaiting_review" and is_map(ticket["attempt"]) and
         ticket["attempt"]["phase"] == "candidate_frozen",
       do: :ok,
       else: {:error, "source_state_guard"}
  end

  defp phase_guard(ticket, "integration") do
    if ticket["phase"] == "ready_to_integrate",
      do: :ok,
      else: {:error, "source_state_guard"}
  end

  defp new_attempt(inputs, ticket) do
    %{
      "attempt_id" => inputs["ids"]["attempt_id"],
      "phase" => "active",
      "disposition" => nil,
      "resume_phase" => nil,
      "lineage" => %{
        "spec_revision_id" => ticket["spec_revision_id"],
        "policy_id" => inputs["protected"]["policy_id"],
        "policy_revision" => inputs["protected"]["policy_revision"]
      },
      "candidate_id" => nil,
      "executions" => %{},
      "infrastructure" => %{}
    }
  end

  defp execution(inputs, role, owner_id, attempt_id) do
    %{
      "execution_id" => inputs["ids"]["execution_id"],
      "effect_id" => inputs["ids"]["effect_id"],
      "reservation_id" => inputs["ids"]["reservation_id"],
      "role" => role,
      "owner_id" => owner_id,
      "attempt_id" => attempt_id,
      "status" => "pending",
      "result" => nil,
      "recorded_at" => inputs["recorded_at"],
      "authority_bindings" => bindings(inputs["protected"])
    }
  end

  defp put_execution(attempt, execution),
    do: put_in(attempt, ["executions", execution["execution_id"]], execution)

  defp find_execution(attempt, execution_id, role) do
    case get_in(attempt, ["executions", execution_id]) do
      %{"role" => ^role} = execution -> execution
      _ -> nil
    end
  end

  defp replace_execution(attempt, execution),
    do: put_in(attempt, ["executions", execution["execution_id"]], execution)

  defp put_infrastructure(attempt, role, inputs),
    do: put_in(attempt, ["infrastructure", role], infrastructure(role, inputs))

  defp infrastructure(role, inputs) do
    %{
      "role" => role,
      "generation" => inputs["protected"]["infrastructure_generation"],
      "ordinal" => inputs["protected"]["infrastructure_ordinal"],
      "limit" => inputs["protected"]["infrastructure_limit"],
      "predecessor_effect_id" => inputs["protected"]["predecessor_effect_id"],
      "failure_class" => inputs["protected"]["failure_class"]
    }
  end

  defp terminal_attempt(attempt, disposition),
    do: attempt |> Map.put("phase", "terminal") |> Map.put("disposition", disposition)

  defp command(command) when is_map(command) and not is_struct(command) do
    required = ~w(schema_version command_id type target_ids payload)

    if Map.keys(command) |> Enum.sort() == Enum.sort(required) and
         command["schema_version"] == 1 and identity?(command["command_id"]) and
         command["type"] in @command_types and plain_map?(command["target_ids"]) and
         plain_map?(command["payload"]),
       do: {:ok, command},
       else: {:error, :invalid_command}
  end

  defp command(_command), do: {:error, :invalid_command}

  defp inputs(inputs) when is_map(inputs) and not is_struct(inputs) do
    required = ~w(recorded_at event_id ids observation protected)

    if Map.keys(inputs) |> Enum.sort() == Enum.sort(required) and
         identity?(inputs["recorded_at"]) and identity?(inputs["event_id"]) and
         plain_map?(inputs["ids"]) and plain_map?(inputs["observation"]) and
         plain_map?(inputs["protected"]) and
         Enum.all?(Map.keys(inputs["protected"]), &(&1 in @protected_input_keys)),
       do: {:ok, inputs},
       else: {:error, :invalid_decision_inputs}
  end

  defp inputs(_inputs), do: {:error, :invalid_decision_inputs}

  defp event(event) when is_map(event) and not is_struct(event) do
    required = ~w(schema_version event_id type recorded_at changes)

    if Map.keys(event) |> Enum.sort() == Enum.sort(required) and event["schema_version"] == 1 and
         identity?(event["event_id"]) and identity?(event["type"]) and
         identity?(event["recorded_at"]) and is_list(event["changes"]) and
         Enum.all?(event["changes"], &valid_change?/1),
       do: {:ok, event},
       else: {:error, :invalid_domain_event}
  end

  defp event(_event), do: {:error, :invalid_domain_event}

  defp valid_change?(%{"kind" => kind, "id" => id, "value" => value} = change)
       when kind in ~w(control objective ticket pm) and is_binary(id) and is_map(value),
       do: Map.keys(change) |> Enum.sort() == ~w(id kind value) and no_root_state?(value)

  defp valid_change?(_change), do: false

  defp apply_changes(state, changes) do
    Enum.reduce_while(changes, {:ok, state}, fn change, {:ok, acc} ->
      case change do
        %{"kind" => "control", "id" => "global", "value" => value} ->
          {:cont, {:ok, Map.put(acc, "control", value)}}

        %{"kind" => "objective", "id" => id, "value" => value} ->
          {:cont, {:ok, put_in(acc, ["objectives", id], value)}}

        %{"kind" => "ticket", "id" => id, "value" => value} ->
          if value["phase"] in @ticket_phases and value["ticket_id"] == id,
            do: {:cont, {:ok, put_in(acc, ["tickets", id], value)}},
            else: {:halt, {:error, :invalid_ticket_change}}

        %{"kind" => "pm", "id" => id, "value" => value} ->
          {:cont, {:ok, put_in(acc, ["pm", id], value)}}

        _ ->
          {:halt, {:error, :invalid_domain_change}}
      end
    end)
  end

  defp accepted(inputs, type, changes, reason \\ nil) do
    event = %{
      "schema_version" => 1,
      "event_id" => inputs["event_id"],
      "type" => type,
      "recorded_at" => inputs["recorded_at"],
      "changes" => changes
    }

    {:ok,
     %{
       "schema_version" => 1,
       "disposition" => "accepted",
       "reason_code" => reason,
       "events" => [event]
     }}
  end

  defp rejected(reason),
    do:
      {:ok,
       %{
         "schema_version" => 1,
         "disposition" => "rejected",
         "reason_code" => reason,
         "events" => []
       }}

  defp blocked(reason),
    do:
      {:ok,
       %{
         "schema_version" => 1,
         "disposition" => "blocked",
         "reason_code" => reason,
         "events" => []
       }}

  defp change(kind, id, value), do: %{"kind" => kind, "id" => id, "value" => value}
  defp target(command, key), do: command["target_ids"][key]

  defp mutable_ticket(state, command) do
    ticket_id = target(command, "ticket_id")

    case state["tickets"][ticket_id] do
      nil -> {:error, "unknown_ticket"}
      %{"phase" => phase} when phase in @terminal_phases -> {:error, "terminal_ticket"}
      ticket -> {:ok, ticket_id, ticket}
    end
  end

  defp bindings(facts) do
    facts
    |> Map.take(@binding_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp effect_ids?(inputs),
    do: Enum.all?(~w(execution_id effect_id reservation_id), &identity?(inputs["ids"][&1]))

  defp receipt_ids?(inputs),
    do: Enum.all?(~w(execution_id claim_id receipt_id), &identity?(inputs["ids"][&1]))

  defp valid_spec?(spec),
    do: plain_map?(spec) and identity?(spec["title"]) and is_list(spec["scope"] || [])

  defp no_reserved_payload?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, nested} ->
      key not in @reserved_payload_keys and no_reserved_payload?(nested)
    end)
  end

  defp no_reserved_payload?(value) when is_list(value),
    do: Enum.all?(value, &no_reserved_payload?/1)

  defp no_reserved_payload?(_value), do: true

  defp no_root_state?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested} ->
      key not in ~w(root root_facts protected protected_facts ledger_balance claim_status receipt_valid accepted_ref) and
        no_root_state?(nested)
    end)
  end

  defp no_root_state?(value) when is_list(value), do: Enum.all?(value, &no_root_state?/1)
  defp no_root_state?(_value), do: true

  defp plain_map?(value), do: is_map(value) and not is_struct(value)
  defp identity?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp positive_integer?(value), do: is_integer(value) and value > 0
end
