defmodule PramanaFoundry.Workflow.Kernel do
  @moduledoc "Pure FR-08B decision, typed transition-plan and semantic replay kernel."

  import Kernel, except: [apply: 2]
  alias PramanaFoundry.Workflow.Kernel.{Event, Plan, State}

  @commands ~w(legacy_event_append enqueue steer pause resume cancel reset propose submit_artifact submit_review request_effect record_receipt)
  @terminal ~w(integrated rejected cancelled)
  @roles ~w(developer reviewer pm check integration)

  def new, do: State.new()
  def supported_commands, do: @commands
  def bind(plan, discriminator, outputs), do: Plan.bind(plan, discriminator, outputs)

  def decide(state, command, inputs) do
    with true <- State.valid?(state), {:ok, command} <- command(command),
         {:ok, inputs} <- inputs(inputs), :ok <- expected_state(command, state),
         result <- dispatch(state, command, inputs), :ok <- validate_decision(result) do
      result
    else
      false -> {:error, :invalid_domain_state}
      {:error, _} = error -> error
      _ -> {:error, :invalid_decision}
    end
  rescue
    _ -> {:error, :invalid_domain_input}
  catch
    _, _ -> {:error, :invalid_domain_input}
  end

  def apply(state, event) do
    with true <- State.valid?(state), :ok <- Event.validate(event),
         true <- event["expected_state_revision"] == state["revision"],
         false <- event["event_id"] == state["last_event_id"],
         {:ok, next} <- reduce(state, event),
         next <- %{next | "revision" => state["revision"] + 1, "last_event_id" => event["event_id"]},
         true <- State.valid?(next) do
      {:ok, next}
    else
      false -> {:error, :event_order_or_state_invalid}
      {:error, _} = error -> error
      _ -> {:error, :invalid_semantic_transition}
    end
  rescue
    _ -> {:error, :invalid_semantic_transition}
  catch
    _, _ -> {:error, :invalid_semantic_transition}
  end

  def rebuild(events) when is_list(events) do
    Enum.reduce_while(events, {:ok, new()}, fn event, {:ok, state} ->
      case apply(state, event) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  rescue
    _ -> {:error, :invalid_event_stream}
  end
  def rebuild(_), do: {:error, :invalid_event_stream}

  # Decisions
  defp dispatch(state, %{"type" => "legacy_event_append"} = c, _i), do: result(state, c, "rejected", "legacy_jsonl_not_authoritative")
  defp dispatch(state, %{"type" => "enqueue"} = c, i), do: enqueue(state, c, i)
  defp dispatch(state, %{"type" => "pause"} = c, i), do: control(state, c, i, true, state["control"]["draining"], "running")
  defp dispatch(state, %{"type" => "resume"} = c, i) do
    case c["payload"]["operation"] do
      "workflow" -> control(state, c, i, false, state["control"]["draining"], "running")
      "clear_drain" -> control(state, c, i, state["control"]["paused"], false, "running")
      _ -> result(state, c, "rejected", "unsupported_resume_operation")
    end
  end
  defp dispatch(state, %{"type" => "steer"} = c, i), do: steer(state, c, i)
  defp dispatch(state, %{"type" => "propose"} = c, i), do: propose(state, c, i)
  defp dispatch(state, %{"type" => "request_effect"} = c, i), do: request_effect(state, c, i)
  defp dispatch(state, %{"type" => "record_receipt"} = c, i), do: receipt(state, c, i)
  defp dispatch(state, %{"type" => "submit_artifact"} = c, i), do: artifact(state, c, i)
  defp dispatch(state, %{"type" => "submit_review"} = c, i), do: review(state, c, i)
  defp dispatch(state, %{"type" => "cancel"} = c, i), do: cancel(state, c, i)
  defp dispatch(state, %{"type" => "reset"} = c, i), do: reset(state, c, i)
  defp dispatch(state, c, _i), do: result(state, c, "rejected", "unsupported_command")

  defp enqueue(state, c, i) do
    tid = target(c, "ticket_id"); oid = target(c, "objective_id")
    cond do
      not ids?([tid, oid, i["ids"]["spec_revision_id"]]) -> result(state, c, "rejected", "missing_admission_identity")
      Map.has_key?(state["tickets"], tid) -> result(state, c, "rejected", "ticket_already_exists")
      state["control"]["draining"] -> result(state, c, "blocked", "draining")
      not spec?(c["payload"]["spec"]) -> result(state, c, "rejected", "malformed_spec")
      true ->
        e = event(state, i, "ticket_admitted", 0, %{"ticket_id" => tid, "objective_id" => oid, "spec_revision_id" => i["ids"]["spec_revision_id"], "spec" => c["payload"]["spec"], "phase" => "queued", "reason" => nil})
        accepted(state, c, [read("ticket", tid, "absent")], [], [], [{"always", [e]}])
    end
  end

  defp steer(state, c, i) do
    case c["payload"]["operation"] do
      "create_objective" -> objective(state, c, i)
      "amend" -> amend(state, c, i)
      "park" -> park(state, c, i)
      "drain" -> control(state, c, i, state["control"]["paused"], true, "running")
      "stop" -> control(state, c, i, state["control"]["paused"], state["control"]["draining"], c["payload"]["status"] || "stop_requested")
      "developer_closed" -> close_developer(state, c, i)
      "start_checks" -> start_checks(state, c, i)
      "check_result" -> check_result(state, c, i)
      "reviewer_closed" -> close_reviewer(state, c, i)
      "freeze_failed" -> freeze_failed(state, c, i)
      "resume_ticket" -> resume_ticket(state, c, i)
      "base_moved" -> base_moved(state, c, i)
      "finalize_cancel" -> finalize_cancel(state, c, i)
      "block" -> result(state, c, "rejected", "public_block_requires_developer_result")
      _ -> result(state, c, "rejected", "unsupported_steering_operation")
    end
  end

  defp objective(state, c, i) do
    oid = target(c, "objective_id"); owner = i["ids"]["planning_owner_id"]
    if ids?([oid, owner]) and not Map.has_key?(state["objectives"], oid) do
      e = event(state, i, "objective_created", 0, %{"objective_id" => oid, "planning_owner_id" => owner})
      accepted(state, c, [read("objective", oid, "absent")], [], [], [{"always", [e]}])
    else
      result(state, c, "rejected", "objective_guard")
    end
  end

  defp amend(state, c, i) do
    with {:ok, t} <- ticket(state, c), true <- t["phase"] in ~w(queued blocked),
         true <- id?(i["ids"]["spec_revision_id"]) and spec?(c["payload"]["spec"]) do
      e = event(state, i, "ticket_amended", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "spec_revision_id" => i["ids"]["spec_revision_id"], "spec" => c["payload"]["spec"]})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "source_state_guard") end
  end

  defp park(state, c, i) do
    with {:ok, t} <- ticket(state, c), true <- t["phase"] in ~w(queued blocked), true <- id?(c["payload"]["reason"]) do
      e = event(state, i, "ticket_parked", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "reason" => c["payload"]["reason"], "resume_phase" => t["phase"]})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "source_state_guard") end
  end

  defp control(state, c, i, paused, draining, stop) do
    cid = i["ids"]["control_id"]
    if id?(cid) and stop in ~w(running stop_requested stop_blocked stop_completed) do
      op = op(0, "set_control", %{"control_id" => cid, "expected_revision" => state["control"]["revision"], "paused" => paused, "draining" => draining, "stop_status" => stop})
      e = event(state, i, "control_changed", state["control"]["revision"] + 1, %{"paused" => paused, "draining" => draining, "stop_status" => stop, "control_id" => cid, "control_revision" => state["control"]["revision"] + 1})
      accepted(state, c, [read("state", "workflow", state["revision"])], [op], [], [{"always", [e]}])
    else
      result(state, c, "rejected", "invalid_control")
    end
  end

  defp propose(state, c, i) do
    oid = target(c, "objective_id"); pid = i["ids"]["proposal_id"]; operation = c["payload"]["operation"]
    if ids?([oid, pid]) and Map.has_key?(state["objectives"], oid) and operation in ~w(create amend park prioritize block) do
      e = event(state, i, "pm_proposal_recorded", state["pm"] |> Map.get(pid, %{"revision" => -1}) |> Map.get("revision") |> Kernel.+(1), %{"proposal_id" => pid, "objective_id" => oid, "operation" => operation})
      accepted(state, c, [read("objective", oid, state["objectives"][oid]["revision"]), read("pm", pid, if(Map.has_key?(state["pm"], pid), do: state["pm"][pid]["revision"], else: "absent"))], [], [], [{"always", [e]}])
    else
      result(state, c, "rejected", "proposal_guard")
    end
  end

  defp request_effect(state, c, i) do
    role = c["payload"]["role"]
    cond do
      role not in @roles -> result(state, c, "rejected", "unsupported_role")
      i["observations"]["eligibility"] == "denied" -> result(state, c, "blocked", i["observations"]["reason"] || "launch_ineligible")
      state["control"]["paused"] -> result(state, c, "blocked", "paused")
      role in ~w(developer pm) and state["control"]["draining"] -> result(state, c, "blocked", "draining")
      role == "pm" -> pm_launch(state, c, i)
      true -> ticket_launch(state, c, i, role)
    end
  end

  defp ticket_launch(state, c, i, role) do
    with {:ok, t} <- ticket(state, c), false <- t["phase"] in @terminal,
         :ok <- launch_phase(t, role), true <- launch_ids?(i),
         {:ok, aid} <- attempt_identity(t, role, i["ids"]["attempt_id"]) do
      op0 = op(0, "reserve", Map.take(i["ids"], ~w(reservation_id execution_id)))
      op1 = op(1, "create_effect", Map.take(i["ids"], ~w(effect_id execution_id reservation_id)))
      binding = binding("launch_authority", 1, "launch_authority_v1", slot(role))
      type = %{"developer" => "launch_planned", "reviewer" => "review_planned", "check" => "check_planned", "integration" => "integration_planned"}[role]
      payload = launch_payload(type, t, aid, i)
      e = event(state, i, type, t["revision"] + 1, Map.put(payload, "authority", %{"binding" => "launch_authority"}))
      accepted(state, c, ticket_reads(state, t), [op0, op1], [binding], [{"admitted", [e]}])
    else
      {:error, reason} -> result(state, c, "rejected", reason)
      false -> result(state, c, "rejected", "source_state_guard")
      _ -> result(state, c, "rejected", "invalid_launch")
    end
  end

  defp pm_launch(state, c, i) do
    oid = target(c, "objective_id"); objective = state["objectives"][oid]; current = state["pm"][oid]
    cond do
      not is_map(objective) -> result(state, c, "rejected", "unknown_objective")
      is_map(current) and current["status"] in ~w(pending running unknown) -> result(state, c, "blocked", "pm_execution_outstanding")
      not launch_ids?(i) -> result(state, c, "rejected", "missing_effect_identity")
      true ->
        op0 = op(0, "reserve", Map.take(i["ids"], ~w(reservation_id execution_id)))
        op1 = op(1, "create_effect", Map.take(i["ids"], ~w(effect_id execution_id reservation_id)))
        b = binding("launch_authority", 1, "launch_authority_v1", "pm_launch_planned.authority")
        e = event(state, i, "pm_launch_planned", if(current, do: current["revision"] + 1, else: 0), %{"objective_id" => oid, "planning_owner_id" => objective["planning_owner_id"], "authority" => %{"binding" => "launch_authority"}})
        accepted(state, c, [read("objective", oid, objective["revision"]), read("pm", oid, if(current, do: current["revision"], else: "absent"))], [op0, op1], [b], [{"admitted", [e]}])
    end
  end

  defp receipt(state, c, i) do
    role = c["payload"]["role"]; outcome = c["payload"]["outcome"]
    cond do
      role not in @roles or outcome not in ~w(succeeded failed non_started unknown) -> result(state, c, "rejected", "invalid_receipt")
      not receipt_ids?(i) -> result(state, c, "rejected", "missing_receipt_identity")
      role == "pm" -> pm_receipt(state, c, i, outcome)
      true -> ticket_receipt(state, c, i, role, outcome)
    end
  end

  defp ticket_receipt(state, c, i, role, outcome) do
    with {:ok, t} <- ticket(state, c), {:ok, a} <- current_attempt(t),
         e when is_map(e) <- a["executions"][i["ids"]["execution_id"]], true <- e["role"] == role and e["status"] != "closed" do
      op = op(0, "settle_claim", Map.merge(Map.take(i["ids"], ~w(claim_id receipt_id execution_id)), %{"outcome" => outcome}))
      kind = if outcome == "non_started", do: "nonstart_settlement_v1", else: "terminal_settlement_v1"
      type = if role == "integration", do: "integration_settled", else: "launch_settled"
      b = binding("settlement", 0, kind, if(role == "integration", do: "integration_settled.settlement", else: "launch_settled.settlement"))
      alternatives = settlement_alternatives(state, role, outcome, t, a, e, i, type)
      accepted(state, c, ticket_reads(state, t), [op], [b], alternatives)
    else _ -> result(state, c, "rejected", "settlement_identity_or_source_guard") end
  end

  defp pm_receipt(state, c, i, outcome) do
    oid = target(c, "objective_id"); pm = state["pm"][oid]
    if is_map(pm) and is_map(pm["execution"]) and pm["execution"]["execution_id"] == i["ids"]["execution_id"] and pm["execution"]["status"] != "closed" do
      op = op(0, "settle_claim", Map.merge(Map.take(i["ids"], ~w(claim_id receipt_id execution_id)), %{"outcome" => outcome}))
      kind = if outcome == "non_started", do: "nonstart_settlement_v1", else: "terminal_settlement_v1"
      b = binding("settlement", 0, kind, "pm_launch_settled.settlement")
      alternatives = pm_settlement_alternatives(state, outcome, pm, i)
      accepted(state, c, [read("pm", oid, pm["revision"])], [op], [b], alternatives)
    else
      result(state, c, "rejected", "settlement_identity_or_source_guard")
    end
  end

  defp settlement_alternatives(state, role, outcome, t, a, exec, i, type) do
    base = fn disposition, discriminator ->
      payload = %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "execution_id" => exec["execution_id"], "outcome" => outcome, "disposition" => disposition, "settlement" => %{"binding" => "settlement"}}
      {discriminator, [event(state, i, type, t["revision"] + 1, payload)]}
    end
    if outcome != "non_started" do
      disposition = if outcome == "unknown", do: "hold_unknown", else: if(role == "integration" and outcome == "succeeded", do: "integrated", else: "record_terminal")
      [base.(disposition, "terminal")]
    else
      role_discriminators(role) |> Enum.map(fn {d, disposition} -> base.(disposition, d) end)
    end
  end

  defp role_discriminators("developer"), do: [{"below_infrastructure_limit", "queue_developer"}, {"infrastructure_limit_reached", "block_developer_infrastructure"}, {"paused", "block_paused"}, {"draining", "block_draining"}, {"cancelled", "cancel_pending"}, {"allocation_exhausted", "exhaust_developer"}, {"allocation_blocked", "block_developer_budget"}, {"policy_revoked", "block_policy"}, {"generation_changed", "block_generation"}]
  defp role_discriminators("reviewer"), do: [{"below_infrastructure_limit", "queue_reviewer"}, {"infrastructure_limit_reached", "block_reviewer_infrastructure"}, {"paused", "block_paused"}, {"draining", "queue_reviewer"}, {"cancelled", "cancel_pending"}, {"allocation_exhausted", "exhaust_reviewer"}, {"allocation_blocked", "block_reviewer_budget"}, {"policy_revoked", "block_policy"}, {"generation_changed", "block_generation"}]
  defp role_discriminators(role) when role in ~w(check integration), do: [{"below_infrastructure_limit", "retry_phase"}, {"infrastructure_limit_reached", "block_phase"}, {"paused", "block_paused"}, {"draining", "retry_phase"}, {"cancelled", "cancel_pending"}, {"allocation_exhausted", "exhaust_phase"}, {"allocation_blocked", "block_budget"}, {"policy_revoked", "block_policy"}, {"generation_changed", "block_generation"}]

  defp pm_settlement_alternatives(state, outcome, pm, i) do
    base = fn disposition, d -> {d, [event(state, i, "pm_launch_settled", pm["revision"] + 1, %{"objective_id" => pm["objective_id"], "outcome" => outcome, "disposition" => disposition, "settlement" => %{"binding" => "settlement"}})]} end
    if outcome != "non_started", do: [base.(if(outcome == "unknown", do: "hold_unknown", else: "record_terminal"), "terminal")], else: Enum.map([{"below_infrastructure_limit", "queue_pm"}, {"infrastructure_limit_reached", "block_pm_infrastructure"}, {"paused", "block_paused"}, {"draining", "block_draining"}, {"cancelled", "cancel_pending"}, {"allocation_exhausted", "exhaust_pm"}, {"allocation_blocked", "block_pm_budget"}, {"policy_revoked", "block_policy"}, {"generation_changed", "block_generation"}], fn {d, x} -> base.(x, d) end)
  end

  defp artifact(state, c, i) do
    result_value = c["payload"]["result"]
    with {:ok, t} <- ticket(state, c), true <- t["phase"] == "developing", {:ok, a} <- current_attempt(t),
         exec when is_map(exec) <- role_execution(a, "developer"), true <- id?(i["ids"]["observation_id"]) do
      case result_value do
        "valid" ->
          if id?(i["ids"]["candidate_id"]) do
            e = event(state, i, "artifact_frozen", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "candidate_id" => i["ids"]["candidate_id"], "observation_id" => i["ids"]["observation_id"]})
            accepted(state, c, ticket_reads(state, t), [op(0, "consume_validation", %{"observation_id" => i["ids"]["observation_id"]})], [], [{"always", [e]}])
          else result(state, c, "rejected", "missing_candidate_identity") end
        x when x in ~w(blocked partial) ->
          e = event(state, i, "artifact_blocked", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "observation_id" => i["ids"]["observation_id"], "result" => x, "reason" => c["payload"]["reason"] || "developer_#{x}"})
          accepted(state, c, ticket_reads(state, t), [op(0, "consume_validation", %{"observation_id" => i["ids"]["observation_id"]})], [], [{"always", [e]}])
        "invalid" -> result(state, c, "rejected", "invalid_submission")
        "none" -> no_result(state, c, i, t, a, exec)
        _ -> result(state, c, "rejected", "malformed_submission")
      end
    else _ -> result(state, c, "rejected", "source_state_guard") end
  end

  defp no_result(state, c, i, t, a, exec) do
    if i["observations"]["stream_status"] == "sealed" and i["observations"]["termination"] in ~w(exited timed_out) do
      result_value = if i["observations"]["termination"] == "timed_out", do: "none", else: "failed"
      e = event(state, i, "execution_observed", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "execution_id" => exec["execution_id"], "observation" => i["observations"]["termination"], "stream_status" => "sealed", "result" => result_value})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else result(state, c, "blocked", "stream_completeness_unknown") end
  end

  defp close_developer(state, c, i) do
    with {:ok, t} <- ticket(state, c), true <- t["phase"] == "awaiting_review", {:ok, a} <- current_attempt(t),
         exec when is_map(exec) <- role_execution(a, "developer"), true <- exec["result"] == "valid" and exec["stream_status"] == "sealed",
         true <- i["observations"]["verified_termination"] == true do
      e = event(state, i, "developer_closed", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "execution_id" => exec["execution_id"]})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "developer_close_guard") end
  end

  defp start_checks(state, c, i) do
    with {:ok, t} <- ticket(state, c), true <- t["phase"] == "awaiting_review", {:ok, a} <- current_attempt(t),
         true <- a["phase"] == "candidate_frozen" and a["developer_closed"] do
      e = event(state, i, "checks_started", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"]})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "checks_require_developer_close") end
  end

  defp check_result(state, c, i) do
    with {:ok, t} <- ticket(state, c), {:ok, a} <- current_attempt(t), true <- a["phase"] == "checking",
         check when is_map(check) <- a["checks"][i["ids"]["check_id"]], true <- c["payload"]["status"] in ~w(passed failed timed_out unknown) do
      disposition = case c["payload"]["status"] do "passed" -> "await_review"; "failed" -> "needs_correction"; "unknown" -> "hold_unknown"; _ -> "block_infrastructure" end
      e = event(state, i, "check_recorded", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "check_id" => check["check_id"], "status" => c["payload"]["status"], "disposition" => disposition, "reason" => c["payload"]["reason"]})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "check_result_guard") end
  end

  defp review(state, c, i) do
    verdict = c["payload"]["verdict"]
    with {:ok, t} <- ticket(state, c), true <- t["phase"] == "reviewing", {:ok, a} <- current_attempt(t),
         exec when is_map(exec) <- role_execution(a, "reviewer"), true <- exec["status"] == "running",
         true <- verdict in ~w(approved changes_requested rejected none), true <- ids?([i["ids"]["review_id"], i["ids"]["check_set_id"]]),
         true <- i["observations"]["stream_status"] in ~w(open sealed) do
      review = %{"review_id" => i["ids"]["review_id"], "candidate_id" => a["candidate_id"], "check_set_id" => i["ids"]["check_set_id"], "execution_id" => exec["execution_id"], "verdict" => verdict, "stream_status" => i["observations"]["stream_status"], "verified_closed" => false, "revision" => 0}
      e = event(state, i, "review_recorded", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "review" => review})
      accepted(state, c, ticket_reads(state, t), [op(0, "consume_validation", %{"review_id" => i["ids"]["review_id"]})], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "review_custody_guard") end
  end

  defp close_reviewer(state, c, i) do
    with {:ok, t} <- ticket(state, c), true <- t["phase"] == "reviewing", {:ok, a} <- current_attempt(t),
         review when is_map(review) <- a["review"], true <- review["stream_status"] == "sealed",
         exec when is_map(exec) <- a["executions"][review["execution_id"]], true <- exec["status"] in ~w(running closing),
         true <- i["observations"]["verified_termination"] == true do
      disposition = %{"approved" => "ready_to_integrate", "changes_requested" => "needs_correction", "rejected" => "rejected", "none" => "review_retry"}[review["verdict"]]
      e = event(state, i, "reviewer_closed", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "execution_id" => exec["execution_id"], "disposition" => disposition})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "reviewer_close_guard") end
  end

  defp freeze_failed(state, c, i), do: simple_attempt_disposition(state, c, i, "freeze_failed", ~w(developing awaiting_review), c["payload"]["disposition"], c["payload"]["reason"])
  defp base_moved(state, c, i), do: simple_attempt_disposition(state, c, i, "freeze_failed", ~w(ready_to_integrate integrating), "superseded_base", "superseded_base")

  defp simple_attempt_disposition(state, c, i, type, phases, disposition, reason) do
    with {:ok, t} <- ticket(state, c), true <- t["phase"] in phases, {:ok, a} <- current_attempt(t), true <- id?(disposition) and id?(reason) do
      e = event(state, i, type, t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "attempt_id" => a["attempt_id"], "disposition" => disposition, "reason" => reason})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "source_state_guard") end
  end

  defp resume_ticket(state, c, i) do
    with {:ok, t} <- ticket(state, c), true <- t["phase"] == "blocked", true <- is_binary(t["resume_phase"]) do
      e = event(state, i, "ticket_resumed", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "phase" => t["resume_phase"]})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "resume_guard") end
  end

  defp cancel(state, c, i) do
    with {:ok, t} <- ticket(state, c), false <- t["phase"] in @terminal do
      e = event(state, i, "cancellation_requested", t["revision"] + 1, %{"ticket_id" => t["ticket_id"]})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "terminal_ticket") end
  end

  defp finalize_cancel(state, c, i) do
    with {:ok, t} <- ticket(state, c), true <- t["cancel_status"] == "cancel_requested", true <- c["payload"]["disposition"] in ~w(cancelled integrated) do
      e = event(state, i, "cancellation_finalized", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "disposition" => c["payload"]["disposition"]})
      accepted(state, c, ticket_reads(state, t), [], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "cancellation_guard") end
  end

  defp reset(state, c, i) do
    with {:ok, t} <- ticket(state, c), true <- t["phase"] == "exhausted", true <- ids?([i["ids"]["ledger_id"]]), true <- is_integer(i["ids"]["ledger_generation"]) and i["ids"]["ledger_generation"] >= 0 do
      op = op(0, "reset_generation", Map.take(i["ids"], ~w(ledger_id ledger_generation)))
      e = event(state, i, "ticket_reset", t["revision"] + 1, %{"ticket_id" => t["ticket_id"], "ledger_id" => i["ids"]["ledger_id"], "ledger_generation" => i["ids"]["ledger_generation"]})
      accepted(state, c, ticket_reads(state, t), [op], [], [{"always", [e]}])
    else _ -> result(state, c, "rejected", "reset_guard") end
  end

  # Semantic reducer
  defp reduce(state, e) do
    case e["type"] do
      "objective_created" -> reduce_objective(state, e)
      "ticket_admitted" -> reduce_admit(state, e)
      "ticket_amended" -> update_ticket(state, e, ~w(queued blocked), &Map.merge(&1, %{"spec_revision_id" => e["payload"]["spec_revision_id"], "spec" => e["payload"]["spec"]}))
      "ticket_parked" -> update_ticket(state, e, ~w(queued blocked), &Map.merge(&1, %{"phase" => "blocked", "resume_phase" => e["payload"]["resume_phase"], "reason" => e["payload"]["reason"]}))
      "control_changed" -> reduce_control(state, e)
      "pm_proposal_recorded" -> reduce_proposal(state, e)
      "launch_planned" -> reduce_launch(state, e, "developer")
      "review_planned" -> reduce_launch(state, e, "reviewer")
      "check_planned" -> reduce_launch(state, e, "check")
      "integration_planned" -> reduce_launch(state, e, "integration")
      "pm_launch_planned" -> reduce_pm_launch(state, e)
      "launch_settled" -> reduce_settlement(state, e)
      "integration_settled" -> reduce_settlement(state, e)
      "pm_launch_settled" -> reduce_pm_settlement(state, e)
      "artifact_frozen" -> reduce_artifact_frozen(state, e)
      "artifact_blocked" -> reduce_artifact_blocked(state, e)
      "execution_observed" -> reduce_execution_observed(state, e)
      "developer_closed" -> reduce_developer_closed(state, e)
      "checks_started" -> update_attempt(state, e, fn t, a -> if a["phase"] == "candidate_frozen" and a["developer_closed"], do: {:ok, t, %{a | "phase" => "checking", "revision" => a["revision"] + 1}}, else: {:error, :checks_guard} end)
      "check_recorded" -> reduce_check_recorded(state, e)
      "review_recorded" -> reduce_review_recorded(state, e)
      "reviewer_closed" -> reduce_reviewer_closed(state, e)
      "freeze_failed" -> reduce_freeze_failed(state, e)
      "ticket_resumed" -> update_ticket(state, e, ~w(blocked), &Map.merge(&1, %{"phase" => e["payload"]["phase"], "resume_phase" => nil, "reason" => nil}))
      "ticket_reset" -> update_ticket(state, e, ~w(exhausted), &Map.merge(&1, %{"phase" => "queued", "resume_phase" => nil, "reason" => nil, "current_attempt_id" => nil}))
      "cancellation_requested" -> update_ticket(state, e, @terminal -- @terminal, &Map.put(&1, "cancel_status", "cancel_requested"), allow_any_nonterminal: true)
      "cancellation_finalized" -> reduce_cancel_final(state, e)
      _ -> {:error, :unsupported_semantic_event}
    end
  end

  defp reduce_objective(state, e) do
    p = e["payload"]

    if e["entity_revision"] == 0 and not Map.has_key?(state["objectives"], p["objective_id"]) do
      objective = %{
        "objective_id" => p["objective_id"],
        "phase" => "draft",
        "planning_owner_id" => p["planning_owner_id"],
        "revision" => 0
      }

      {:ok, put_in(state, ["objectives", p["objective_id"]], objective)}
    else
      {:error, :objective_guard}
    end
  end

  defp reduce_admit(state, e) do
    p = e["payload"]

    if e["entity_revision"] == 0 and not Map.has_key?(state["tickets"], p["ticket_id"]) do
      ticket = %{
        "ticket_id" => p["ticket_id"],
        "objective_id" => p["objective_id"],
        "phase" => p["phase"],
        "resume_phase" => nil,
        "reason" => p["reason"],
        "spec_revision_id" => p["spec_revision_id"],
        "spec" => p["spec"],
        "attempts" => %{},
        "current_attempt_id" => nil,
        "cancel_status" => nil,
        "revision" => 0
      }

      {:ok, put_in(state, ["tickets", p["ticket_id"]], ticket)}
    else
      {:error, :admission_guard}
    end
  end

  defp reduce_control(state, e) do
    p = e["payload"]
    control = state["control"]

    if e["entity_revision"] == control["revision"] + 1 do
      next = %{
        "revision" => e["entity_revision"],
        "paused" => p["paused"],
        "draining" => p["draining"],
        "stop_status" => p["stop_status"]
      }

      {:ok, Map.put(state, "control", next)}
    else
      {:error, :control_revision}
    end
  end

  defp reduce_proposal(state, e) do
    p = e["payload"]
    current = state["pm"][p["proposal_id"]]
    expected = if current, do: current["revision"] + 1, else: 0

    if e["entity_revision"] == expected do
      pm = %{
        "objective_id" => p["objective_id"],
        "planning_owner_id" => p["proposal_id"],
        "execution" => nil,
        "infrastructure" => %{"proposal" => p["operation"]},
        "status" => "closed",
        "revision" => e["entity_revision"]
      }

      {:ok, put_in(state, ["pm", p["proposal_id"]], pm)}
    else
      {:error, :proposal_revision}
    end
  end

  defp reduce_launch(state, e, role) do
    p = e["payload"]
    authority = p["authority"]

    with {:ok, ticket} <- fetch_ticket(state, p["ticket_id"]),
         true <- e["entity_revision"] == ticket["revision"] + 1,
         :ok <- launch_phase(ticket, role),
         :ok <- authority_matches?(authority, role, p["ticket_id"], p["attempt_id"]),
         {:ok, next} <- install_execution(ticket, role, p, authority) do
      {:ok, put_in(state, ["tickets", ticket["ticket_id"]], bump_ticket(next, e))}
    else
      _ -> {:error, :launch_guard}
    end
  end

  defp reduce_pm_launch(state, e) do
    p = e["payload"]
    authority = p["authority"]
    current = state["pm"][p["objective_id"]]
    expected = if current, do: current["revision"] + 1, else: 0

    if e["entity_revision"] == expected and
         authority_matches?(authority, "pm", p["objective_id"], nil) == :ok do
      pm = %{
        "objective_id" => p["objective_id"],
        "planning_owner_id" => p["planning_owner_id"],
        "execution" => execution(authority),
        "infrastructure" => %{},
        "status" => "pending",
        "revision" => e["entity_revision"]
      }

      {:ok, put_in(state, ["pm", p["objective_id"]], pm)}
    else
      {:error, :pm_launch_guard}
    end
  end

  defp reduce_settlement(state, e) do
    p = e["payload"]

    with {:ok, ticket} <- fetch_ticket(state, p["ticket_id"]),
         true <- e["entity_revision"] == ticket["revision"] + 1,
         {:ok, attempt} <- attempt(ticket, p["attempt_id"]),
         execution when is_map(execution) <- attempt["executions"][p["execution_id"]],
         :ok <- settlement_matches?(p["settlement"], execution, ticket, attempt, p["outcome"]),
         {:ok, next_ticket, next_attempt} <- settle_ticket(ticket, attempt, execution, p) do
      next = put_attempt(next_ticket, next_attempt)
      {:ok, put_in(state, ["tickets", ticket["ticket_id"]], bump_ticket(next, e))}
    else
      _ -> {:error, :settlement_guard}
    end
  end

  defp reduce_pm_settlement(state, e) do
    p = e["payload"]
    pm = state["pm"][p["objective_id"]]

    if is_map(pm) and e["entity_revision"] == pm["revision"] + 1 and
         settlement_matches?(
           p["settlement"],
           pm["execution"],
           %{"ticket_id" => pm["objective_id"]},
           %{"attempt_id" => nil},
           p["outcome"]
         ) == :ok do
      next = %{
        pm
        | "execution" => settled_execution(pm["execution"], p["outcome"]),
          "status" => pm_status(p["disposition"]),
          "revision" => e["entity_revision"],
          "infrastructure" => infra(p["settlement"])
      }

      {:ok, put_in(state, ["pm", p["objective_id"]], next)}
    else
      {:error, :pm_settlement_guard}
    end
  end

  defp reduce_artifact_frozen(state, e) do
    update_attempt(state, e, fn ticket, attempt ->
      p = e["payload"]
      execution = role_execution(attempt, "developer")

      if ticket["phase"] == "developing" and is_map(execution) and
           execution["status"] in ~w(running starting) do
        closed = %{
          execution
          | "result" => "valid",
            "stream_status" => "sealed",
            "status" => "closing",
            "revision" => execution["revision"] + 1
        }

        next_attempt =
          attempt
          |> Map.put("phase", "candidate_frozen")
          |> Map.put("candidate_id", p["candidate_id"])
          |> put_exec(closed)
          |> Map.update!("revision", &(&1 + 1))

        {:ok, %{ticket | "phase" => "awaiting_review"}, next_attempt}
      else
        {:error, :artifact_guard}
      end
    end)
  end

  defp reduce_artifact_blocked(state, e) do
    update_attempt(state, e, fn ticket, attempt ->
      execution = role_execution(attempt, "developer")

      if ticket["phase"] == "developing" and is_map(execution) do
        closed = %{
          execution
          | "result" => e["payload"]["result"],
            "stream_status" => "sealed",
            "status" => "closing",
            "revision" => execution["revision"] + 1
        }

        next_attempt = attempt |> put_exec(closed) |> terminal_attempt("blocked")
        {:ok, %{ticket | "phase" => "blocked", "reason" => e["payload"]["reason"]}, next_attempt}
      else
        {:error, :artifact_guard}
      end
    end)
  end

  defp reduce_execution_observed(state, e) do
    update_attempt(state, e, fn ticket, attempt ->
      p = e["payload"]
      execution = attempt["executions"][p["execution_id"]]

      if is_map(execution) and execution["status"] != "closed" do
        closed = %{
          execution
          | "status" => "closed",
            "stream_status" => p["stream_status"],
            "result" => p["result"],
            "verified_closed" => true,
            "revision" => execution["revision"] + 1
        }

        disposition = if p["observation"] == "timed_out", do: "timed_out", else: "failed"
        next_attempt = attempt |> put_exec(closed) |> terminal_attempt(disposition)
        {:ok, %{ticket | "phase" => "queued", "reason" => disposition}, next_attempt}
      else
        {:error, :observation_guard}
      end
    end)
  end

  defp reduce_developer_closed(state, e) do
    update_attempt(state, e, fn ticket, attempt ->
      p = e["payload"]
      execution = attempt["executions"][p["execution_id"]]

      if is_map(execution) and execution["role"] == "developer" and
           execution["result"] == "valid" and execution["stream_status"] == "sealed" and
           execution["status"] == "closing" do
        closed = %{
          execution
          | "status" => "closed",
            "verified_closed" => true,
            "revision" => execution["revision"] + 1
        }

        next_attempt =
          attempt
          |> put_exec(closed)
          |> Map.put("developer_closed", true)
          |> Map.update!("revision", &(&1 + 1))

        {:ok, ticket, next_attempt}
      else
        {:error, :close_guard}
      end
    end)
  end

  defp reduce_check_recorded(state, e) do
    update_attempt(state, e, fn ticket, attempt ->
      p = e["payload"]
      check = attempt["checks"][p["check_id"]]

      if is_map(check) do
        next_check = %{check | "status" => p["status"], "revision" => check["revision"] + 1}
        updated = put_in(attempt, ["checks", p["check_id"]], next_check)

        case p["disposition"] do
          "await_review" ->
            {:ok, %{ticket | "phase" => "awaiting_review"},
             %{updated | "phase" => "awaiting_review", "revision" => updated["revision"] + 1}}

          "needs_correction" ->
            {:ok, %{ticket | "phase" => "queued", "reason" => p["reason"]},
             terminal_attempt(updated, "needs_correction")}

          "hold_unknown" ->
            {:ok,
             %{
               ticket
               | "phase" => "blocked",
                 "resume_phase" => "awaiting_review",
                 "reason" => "check_unknown"
             }, updated}

          _ ->
            {:ok,
             %{
               ticket
               | "phase" => "blocked",
                 "resume_phase" => "awaiting_review",
                 "reason" => p["reason"]
             }, updated}
        end
      else
        {:error, :check_guard}
      end
    end)
  end

  defp reduce_review_recorded(state, e) do
    update_attempt(state, e, fn ticket, attempt ->
      review = e["payload"]["review"]
      execution = attempt["executions"][review["execution_id"]]

      if ticket["phase"] == "reviewing" and is_map(execution) and
           execution["status"] == "running" and review["candidate_id"] == attempt["candidate_id"] do
        {:ok, ticket, %{attempt | "review" => review, "revision" => attempt["revision"] + 1}}
      else
        {:error, :review_guard}
      end
    end)
  end

  defp reduce_reviewer_closed(state, e) do
    update_attempt(state, e, fn ticket, attempt ->
      p = e["payload"]
      review = attempt["review"]
      execution = attempt["executions"][p["execution_id"]]

      if is_map(review) and review["stream_status"] == "sealed" and is_map(execution) and
           execution["status"] in ~w(running closing) do
        closed = %{
          execution
          | "status" => "closed",
            "verified_closed" => true,
            "revision" => execution["revision"] + 1
        }

        closed_review = %{
          review
          | "verified_closed" => true,
            "revision" => review["revision"] + 1
        }

        updated = attempt |> put_exec(closed) |> Map.put("review", closed_review)

        case p["disposition"] do
          "ready_to_integrate" ->
            {:ok, %{ticket | "phase" => "ready_to_integrate"},
             %{
               updated
               | "phase" => "ready_to_integrate",
                 "revision" => updated["revision"] + 1
             }}

          "needs_correction" ->
            {:ok, %{ticket | "phase" => "queued", "reason" => "review_changes_requested"},
             terminal_attempt(updated, "needs_correction")}

          "rejected" ->
            {:ok, %{ticket | "phase" => "rejected"}, terminal_attempt(updated, "rejected")}

          _ ->
            {:ok, %{ticket | "phase" => "awaiting_review"},
             %{updated | "phase" => "awaiting_review", "revision" => updated["revision"] + 1}}
        end
      else
        {:error, :review_close_guard}
      end
    end)
  end

  defp reduce_freeze_failed(state, e) do
    update_attempt(state, e, fn ticket, attempt ->
      p = e["payload"]

      case p["disposition"] do
        "superseded_base" ->
          {:ok, %{ticket | "phase" => "queued", "reason" => p["reason"]},
           terminal_attempt(attempt, "superseded_base")}

        "retry" ->
          {:ok, %{ticket | "phase" => "awaiting_review", "reason" => p["reason"]}, attempt}

        _ ->
          {:ok,
           %{
             ticket
             | "phase" => "blocked",
               "resume_phase" => "awaiting_review",
               "reason" => p["reason"]
           }, attempt}
      end
    end)
  end

  defp reduce_cancel_final(state, e) do
    update_ticket(
      state,
      e,
      [],
      fn ticket ->
        ticket
        |> Map.put("phase", e["payload"]["disposition"])
        |> Map.put("cancel_status", "cancel_finalized")
      end,
      allow_any_nonterminal: true
    )
  end

  # reducer helpers
  defp install_execution(t, "developer", p, auth) do
    case t["current_attempt_id"] do
      nil ->
        attempt = new_attempt(p["attempt_id"], t, auth)

        {:ok,
         t
         |> put_attempt(attempt)
         |> Map.put("current_attempt_id", attempt["attempt_id"])
         |> Map.put("phase", "developing")}

      attempt_id ->
        attempt = t["attempts"][attempt_id]

        cond do
          attempt["phase"] == "terminal" and p["attempt_id"] != attempt_id ->
            next = new_attempt(p["attempt_id"], t, auth)

            {:ok,
             t
             |> put_attempt(next)
             |> Map.put("current_attempt_id", next["attempt_id"])
             |> Map.put("phase", "developing")}

          attempt["phase"] == "active" and
              not Map.has_key?(attempt["executions"], auth["execution_id"]) ->
            updated =
              attempt
              |> put_exec(execution(auth))
              |> Map.update!("revision", &(&1 + 1))

            {:ok, t |> put_attempt(updated) |> Map.put("phase", "developing")}

          true ->
            {:error, :attempt_identity_reuse}
        end
    end
  end

  defp install_execution(t, role, p, auth) do
    with {:ok, attempt} <- current_attempt(t),
         false <- Map.has_key?(attempt["executions"], auth["execution_id"]) do
      next_attempt =
        attempt
        |> put_exec(execution(auth))
        |> maybe_install_check(role, p, auth)
        |> Map.update!("revision", &(&1 + 1))

      next_attempt =
        case role do
          "reviewer" -> %{next_attempt | "phase" => "reviewing"}
          "integration" -> %{next_attempt | "phase" => "integrating"}
          _ -> next_attempt
        end

      next_ticket = put_attempt(t, next_attempt)

      next_ticket =
        case role do
          "reviewer" -> %{next_ticket | "phase" => "reviewing"}
          "integration" -> %{next_ticket | "phase" => "integrating"}
          "check" -> next_ticket
        end

      {:ok, next_ticket}
    else
      _ -> {:error, :execution_identity_reuse}
    end
  end

  defp maybe_install_check(attempt, "check", p, auth) do
    check = %{
      "check_id" => p["check_id"],
      "candidate_id" => attempt["candidate_id"],
      "execution_id" => auth["execution_id"],
      "status" => "pending",
      "revision" => 0
    }

    put_in(attempt, ["checks", p["check_id"]], check)
  end

  defp maybe_install_check(attempt, _role, _p, _auth), do: attempt

  defp settle_ticket(ticket, attempt, execution, p) do
    settled = settled_execution(execution, p["outcome"])

    next_attempt =
      attempt
      |> put_exec(settled)
      |> Map.put(
        "infrastructure",
        Map.put(attempt["infrastructure"], execution["role"], infra(p["settlement"]))
      )
      |> Map.update!("revision", &(&1 + 1))

    disposition = p["disposition"]

    cond do
      disposition == "hold_unknown" ->
        {:ok, %{ticket | "reason" => "#{execution["role"]}_unknown"}, next_attempt}

      disposition == "integrated" ->
        {:ok, %{ticket | "phase" => "integrated"}, terminal_attempt(next_attempt, "integrated")}

      disposition in ~w(queue_developer retry_phase) ->
        {:ok,
         %{
           ticket
           | "phase" => if(execution["role"] == "developer", do: "queued", else: ticket["phase"]),
             "resume_phase" =>
               if(execution["role"] == "developer", do: "developing", else: ticket["resume_phase"]),
             "reason" => "#{execution["role"]}_launch_non_started"
         }, next_attempt}

      disposition == "queue_reviewer" ->
        {:ok, %{ticket | "phase" => "awaiting_review", "reason" => "reviewer_launch_non_started"},
         %{next_attempt | "phase" => "awaiting_review"}}

      String.starts_with?(disposition, "block_") ->
        {:ok,
         %{
           ticket
           | "phase" => "blocked",
             "resume_phase" => resume_for(execution["role"]),
             "reason" => disposition
         }, next_attempt}

      String.starts_with?(disposition, "exhaust_") ->
        {:ok, %{ticket | "phase" => "exhausted", "reason" => disposition},
         terminal_attempt(next_attempt, "exhausted")}

      disposition == "cancel_pending" ->
        {:ok, %{ticket | "cancel_status" => "cancel_requested", "reason" => disposition},
         next_attempt}

      true ->
        {:ok, ticket, next_attempt}
    end
  end

  defp new_attempt(id, ticket, authority) do
    %{
      "attempt_id" => id,
      "phase" => "active",
      "disposition" => nil,
      "lineage" => %{
        "spec_revision_id" => ticket["spec_revision_id"],
        "policy_id" => authority["policy_id"],
        "policy_revision" => authority["policy_revision"]
      },
      "candidate_id" => nil,
      "developer_closed" => false,
      "checks" => %{},
      "review" => nil,
      "executions" => %{authority["execution_id"] => execution(authority)},
      "infrastructure" => %{},
      "revision" => 0
    }
  end

  defp execution(authority) do
    Map.merge(
      Map.take(
        authority,
        ~w(execution_id effect_id reservation_id role owner_id attempt_id predecessor_effect_id policy_id policy_revision control_id control_revision ledger_id ledger_generation infrastructure_generation)
      ),
      %{
        "status" => "pending",
        "result" => nil,
        "stream_status" => "open",
        "verified_closed" => false,
        "revision" => 0
      }
    )
  end

  defp settled_execution(execution, "unknown"),
    do: %{execution | "status" => "unknown", "revision" => execution["revision"] + 1}

  defp settled_execution(execution, "succeeded") do
    %{
      execution
      | "status" => "running",
        "result" => "succeeded",
        "revision" => execution["revision"] + 1
    }
  end

  defp settled_execution(execution, outcome) do
    %{
      execution
      | "status" => "closed",
        "result" => outcome,
        "verified_closed" => outcome == "non_started",
        "revision" => execution["revision"] + 1
    }
  end

  defp settlement_matches?(settlement, execution, ticket, attempt, outcome) do
    if is_map(settlement) and settlement["role"] == execution["role"] and
         settlement["owner_id"] == ticket["ticket_id"] and
         settlement["attempt_id"] == attempt["attempt_id"] and
         settlement["execution_id"] == execution["execution_id"] and
         settlement["effect_id"] == execution["effect_id"] and
         settlement["reservation_id"] == execution["reservation_id"] and
         settlement["predecessor_effect_id"] == execution["predecessor_effect_id"] and
         settlement["ledger_id"] == execution["ledger_id"] and
         settlement["ledger_generation"] == execution["ledger_generation"] and
         settlement["infrastructure_generation"] == execution["infrastructure_generation"] and
         settlement["outcome"] == outcome do
      :ok
    else
      {:error, :settlement_identity}
    end
  end

  defp authority_matches?(authority, role, owner, attempt) do
    if is_map(authority) and authority["role"] == role and authority["owner_id"] == owner and
         authority["attempt_id"] == attempt do
      :ok
    else
      {:error, :authority_identity}
    end
  end

  defp update_attempt(state, e, fun) do
    p = e["payload"]

    with {:ok, ticket} <- fetch_ticket(state, p["ticket_id"]),
         true <- e["entity_revision"] == ticket["revision"] + 1,
         {:ok, attempt} <- attempt(ticket, p["attempt_id"]),
         {:ok, next_ticket, next_attempt} <- fun.(ticket, attempt) do
      next = put_attempt(next_ticket, next_attempt)
      {:ok, put_in(state, ["tickets", ticket["ticket_id"]], bump_ticket(next, e))}
    else
      _ -> {:error, :attempt_transition_guard}
    end
  end

  defp update_ticket(state, e, phases, fun, opts \\ []) do
    p = e["payload"]

    with {:ok, ticket} <- fetch_ticket(state, p["ticket_id"]),
         true <- e["entity_revision"] == ticket["revision"] + 1,
         true <-
           (Keyword.get(opts, :allow_any_nonterminal, false) and ticket["phase"] not in @terminal) or
             ticket["phase"] in phases do
      {:ok, put_in(state, ["tickets", ticket["ticket_id"]], bump_ticket(fun.(ticket), e))}
    else
      _ -> {:error, :ticket_transition_guard}
    end
  end

  defp bump_ticket(ticket, e), do: %{ticket | "revision" => e["entity_revision"]}

  defp terminal_attempt(attempt, disposition),
    do: %{
      attempt
      | "phase" => "terminal",
        "disposition" => disposition,
        "revision" => attempt["revision"] + 1
    }

  defp put_attempt(ticket, attempt),
    do: put_in(ticket, ["attempts", attempt["attempt_id"]], attempt)

  defp put_exec(attempt, execution),
    do: put_in(attempt, ["executions", execution["execution_id"]], execution)

  defp attempt(ticket, id) do
    case ticket["attempts"][id] do
      nil -> {:error, :unknown_attempt}
      attempt -> {:ok, attempt}
    end
  end

  defp current_attempt(ticket), do: attempt(ticket, ticket["current_attempt_id"])

  defp fetch_ticket(state, id) do
    case state["tickets"][id] do
      nil -> {:error, :unknown_ticket}
      ticket -> {:ok, ticket}
    end
  end

  defp role_execution(attempt, role),
    do: Enum.find_value(attempt["executions"], fn {_id, execution} -> if execution["role"] == role, do: execution end)

  defp infra(settlement) do
    %{
      "generation" => settlement["infrastructure_generation"],
      "ordinal" => settlement["infrastructure_ordinal"],
      "predecessor_effect_id" => settlement["predecessor_effect_id"],
      "failure_class" => settlement["failure_class"]
    }
  end

  defp pm_status(disposition) do
    cond do
      disposition == "hold_unknown" -> "unknown"
      disposition == "queue_pm" -> "queued"
      String.starts_with?(disposition, "exhaust_") -> "exhausted"
      String.starts_with?(disposition, "block_") or disposition in ~w(cancel_pending) -> "blocked"
      true -> "closed"
    end
  end

  defp resume_for("developer"), do: "developing"
  defp resume_for("reviewer"), do: "awaiting_review"
  defp resume_for(_), do: "integrating"

  # plan/validation helpers
  defp accepted(state,c,reads,ops,bindings,alts),do:plan(state,c,"accepted",nil,reads,ops,bindings,alts)
  defp result(state,c,d,r),do:plan(state,c,d,r,[read("state","workflow",state["revision"])],[],[],[])
  defp plan(state,c,d,r,reads,ops,bindings,alts) do
    p=%{"schema_version"=>1,"command_id"=>c["command_id"],"disposition"=>d,"reason_code"=>r,"expected_domain_revision"=>state["revision"],"domain_reads"=>uniq_reads([read("state","workflow",state["revision"])|reads]),"protected_operations"=>ops,"bindings"=>bindings,"alternatives"=>Enum.map(alts,fn {disc,events}->%{"discriminator"=>disc,"events"=>events} end)};{:ok,p}
  end
  defp validate_decision({:ok,p}),do:Plan.validate(p);defp validate_decision({:error,_}),do::ok;defp validate_decision(_),do:{:error,:invalid_decision}
  defp event(state,i,type,er,payload),do:%{"schema_version"=>1,"event_id"=>i["event_id"],"type"=>type,"recorded_at"=>i["recorded_at"],"expected_state_revision"=>state["revision"],"entity_revision"=>er,"payload"=>payload}
  defp op(n,t,input),do:%{"schema_version"=>1,"ordinal"=>n,"type"=>t,"input"=>input}
  defp binding(n,o,k,s),do:%{"name"=>n,"operation_ordinal"=>o,"output_kind"=>k,"destination_slot"=>s}
  defp read(k,id,r),do:%{"kind"=>k,"entity_id"=>id,"revision"=>r}
  defp uniq_reads(rs),do:Enum.uniq_by(rs,&{&1["kind"],&1["entity_id"]})
  defp ticket_reads(state,t),do:[read("ticket",t["ticket_id"],t["revision"]),read("state","workflow",state["revision"])]
  defp launch_payload("launch_planned",t,aid,_i),do:%{"ticket_id"=>t["ticket_id"],"attempt_id"=>aid}
  defp launch_payload("review_planned",t,aid,_i),do:%{"ticket_id"=>t["ticket_id"],"attempt_id"=>aid}
  defp launch_payload("integration_planned",t,aid,_i),do:%{"ticket_id"=>t["ticket_id"],"attempt_id"=>aid}
  defp launch_payload("check_planned",t,aid,i),do:%{"ticket_id"=>t["ticket_id"],"attempt_id"=>aid,"check_id"=>i["ids"]["check_id"]}
  defp slot("developer"),do:"launch_planned.authority";defp slot("reviewer"),do:"review_planned.authority";defp slot("check"),do:"check_planned.authority";defp slot("integration"),do:"integration_planned.authority"
  defp launch_phase(t,"developer"),do:if(t["phase"]=="queued" or t["phase"]=="blocked" and t["resume_phase"]=="developing",do::ok,else:{:error,"source_state_guard"})
  defp launch_phase(t,"reviewer"),do:with {:ok,a}<-current_attempt(t),true<-t["phase"]=="awaiting_review" and a["phase"]=="awaiting_review" do :ok else _->{:error,"source_state_guard"} end
  defp launch_phase(t,"check"),do:with {:ok,a}<-current_attempt(t),true<-t["phase"]=="awaiting_review" and a["phase"]=="checking" and a["developer_closed"] do :ok else _->{:error,"source_state_guard"} end
  defp launch_phase(t,"integration"),do:if(t["phase"]=="ready_to_integrate",do::ok,else:{:error,"source_state_guard"})
  defp attempt_identity(t,"developer",id) do if id?(id) do case t["current_attempt_id"] do nil->{:ok,id};aid->a=t["attempts"][aid];if a["phase"]=="terminal",do:{:ok,id},else:if(a["phase"]=="active",do:{:ok,aid},else:{:error,"active_attempt_guard"}) end else {:error,"missing_attempt_identity"} end end
  defp attempt_identity(t,_role,_id),do:with {:ok,a}<-current_attempt(t),do:{:ok,a["attempt_id"]}
  defp ticket(state,c),do:case state["tickets"][target(c,"ticket_id")] do nil->{:error,"unknown_ticket"};%{"phase"=>p} when p in @terminal->{:error,"terminal_ticket"};t->{:ok,t} end
  defp target(c,k),do:c["target_ids"][k]
  defp expected_state(c,s),do:if(c["expected_revisions"]["state/workflow"]==s["revision"],do::ok,else:{:error,:stale_or_incomplete_domain_reads})
  defp command(c) do if plain?(c) and exact?(c,~w(schema_version command_id expected_revisions type target_ids payload)) and c["schema_version"]==1 and id?(c["command_id"]) and c["type"] in @commands and plain?(c["expected_revisions"]) and plain?(c["target_ids"]) and plain?(c["payload"]),do:{:ok,c},else:{:error,:invalid_command} end rescue _->{:error,:invalid_command} end
  defp inputs(i) do if plain?(i) and exact?(i,~w(recorded_at event_id ids observations)) and id?(i["recorded_at"]) and id?(i["event_id"]) and plain?(i["ids"]) and plain?(i["observations"]),do:{:ok,i},else:{:error,:invalid_decision_inputs} end rescue _->{:error,:invalid_decision_inputs} end
  defp spec?(s),do:plain?(s) and id?(s["title"]) and is_list(s["scope"]||[]) and Enum.all?(s["scope"]||[],&is_binary/1)
  defp launch_ids?(i),do:ids?(Enum.map(~w(execution_id effect_id reservation_id),&i["ids"][&1]))
  defp receipt_ids?(i),do:ids?(Enum.map(~w(execution_id claim_id receipt_id),&i["ids"][&1]))
  defp ids?(vs),do:Enum.all?(vs,&id?/1)
  defp exact?(m,ks),do:Enum.sort(Map.keys(m))==Enum.sort(ks)
  defp id?(v),do:is_binary(v) and v!="" and String.valid?(v)
  defp plain?(v),do:is_map(v) and not is_struct(v)
end
