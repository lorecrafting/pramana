defmodule PramanaFoundry.ManualLane.Backend do
  @moduledoc """
  T3, the manual execution backend (`docs/batch-d/THIN-LANE-DESIGN-2026-09-23.md` §3). The
  human is the adapter: Foundry issues one claimed effect per launch through `decide/3`,
  and records what the human attests as receipts. It dispatches nothing.

  Every function takes `ctx = %{gateway, capability, path, writer_epoch}`, and optionally
  `:work_packet`, the module whose `build/3` makes the packet (default
  `PramanaFoundry.WorkPacket`).

  The principal passed in is the Gateway actor, so Core records it as the effect issuer,
  lets only it settle the claim, and refuses a reviewer whose principal issued a developer
  effect of the attempt (`principal_not_independent`, a pre-intent denial).

  Every write replays first: a step whose command id is already committed is reported and
  not resubmitted. Command ids derive from state and never from a clock or counter. A
  launch id also names its principal, because Core records a refused bundle under its id:
  without the principal, a reviewer refused for independence would block the distinct
  principal's launch forever.
  """

  alias PramanaFoundry.ManualLane.Replay
  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.{Execution, Plan}

  @ids %{
    policy_id: "manual-lane",
    control_id: "manual-lane",
    ledgers: %{"developer" => "starts.developer", "reviewer" => "starts.reviewer"}
  }

  @operator "operator"
  @lane_id ~r/\A(?:ML-[A-Za-z0-9-]+)\z/
  @ingress_types ~w(ticket_admitted artifact_frozen artifact_blocked stream_sealed
                    developer_closed reviewer_closed checks_started)

  @doc "The root policy, control and ledger ids the lane's seed must create."
  def ids, do: @ids

  def state(ctx), do: Replay.state(ctx)

  @doc "Admits a lane ticket: its scope added to the policy, then `ticket_admitted`, queued."
  def admit(ctx, ticket_id, spec) do
    with :ok <- if(lane_id?(ticket_id), do: :ok, else: {:reject, :ticket_id_not_lane}),
         {:ok, _} <- allow_scope(ctx, ticket_id) do
      ingress(
        ctx,
        "#{ticket_id}/admit",
        ticket_id,
        [
          {"ticket_admitted",
           %{
             "ticket_id" => ticket_id,
             "objective_id" => nil,
             "spec_revision_id" => Plan.id(ticket_id, "spec"),
             "spec" => spec,
             "phase" => "queued",
             "reason" => nil
           }}
        ],
        @operator
      )
    end
  end

  @doc """
  Issues one effect for `role` under `principal` and returns its work packet. An open
  execution of the role already issued is rebuilt from the store instead: no relaunch.
  A committed plan that issued nothing (a block or exhaustion) returns the ticket.
  """
  def launch(ctx, ticket_id, role, principal) do
    state = Replay.state(ctx)
    ticket = state["tickets"][ticket_id]

    case open_execution(ticket, role) do
      nil -> issue(ctx, state, ticket_id, role, principal, 0)
      execution_id -> packet(ctx, ticket_id, Plan.id(launch_id(execution_id), "effect"))
    end
  end

  # `retry` counts launch ids already burned. Core records a refused bundle (a lost CAS race)
  # under its id, and any changed resubmission of that id is an `idempotency_conflict`. So a
  # conflict means a racer's launch won (rebuild its packet) or the id is burned (take the
  # next). Ids stay store-derived, and retry 0 carries no suffix.
  defp issue(ctx, state, ticket_id, role, principal, retry) do
    id =
      "#{ticket_id}/#{role}/#{role_launches(state["tickets"][ticket_id], role)}/#{principal}" <>
        if(retry == 0, do: "", else: "/retry-#{retry}")

    command = %{
      "schema_version" => 1,
      "command_id" => id,
      "type" => "plan_launch",
      "target_ids" => %{"ticket_id" => ticket_id},
      "payload" => %{"role" => role},
      "expected_revisions" => %{}
    }

    with {:ok, facts} <-
           Replay.launch_facts(
             ctx,
             @ids.policy_id,
             @ids.control_id,
             @ids.ledgers[role],
             predecessor(ctx, state["tickets"][ticket_id], role)
           ),
         {:ok, decision} <- WorkflowKernel.decide(state, command, facts) do
      case outcome(Replay.submit(ctx, decision, principal)) do
        {:ok, _result} ->
          if Enum.any?(
               decision["plan"]["protected_operations"],
               &(&1["type"] == "create_effect")
             ),
             do: packet(ctx, ticket_id, Plan.id(id, "effect")),
             else: {:ok, %{"ticket" => Replay.state(ctx)["tickets"][ticket_id]}}

        {:error, :idempotency_conflict} ->
          state = Replay.state(ctx)

          case open_execution(state["tickets"][ticket_id], role) do
            nil -> issue(ctx, state, ticket_id, role, principal, retry + 1)
            execution_id -> packet(ctx, ticket_id, Plan.id(launch_id(execution_id), "effect"))
          end

        refused ->
          refused
      end
    end
  end

  @doc "The receipt of an execution that ran: `settle_claim` succeeded, delivered."
  def deliver(ctx, ticket_id, role, principal, receipt_payload) do
    with :ok <- attested(receipt_payload, principal),
         {:ok, effect} <- current_effect(ctx, ticket_id, role, principal) do
      settle_root(ctx, ticket_id, "deliver", effect, principal, %{
        "outcome" => "succeeded",
        "proof" => "delivered",
        "payload" => receipt_payload
      })
    end
  end

  @doc "Ingress of events no decider owns yet (Q1), from a closed table of types."
  def ingress(ctx, command_id, ticket_id, events, principal) do
    cond do
      Enum.any?(events, fn {type, _} -> type not in @ingress_types end) ->
        {:reject, :ingress_type_not_allowed}

      Replay.committed?(ctx, command_id) ->
        {:ok, %{"command_id" => command_id, "idempotent" => true}}

      true ->
        command = %{
          "schema_version" => 1,
          "command_id" => command_id,
          "type" => "enqueue",
          "target_ids" => %{"ticket_id" => ticket_id},
          "payload" => %{}
        }

        events = for {type, payload} <- events, do: {type, ticket_id, payload}

        with {:ok, decision} <-
               Replay.state(ctx)
               |> Plan.unconditional(command_id, %{"events" => events})
               |> Plan.decision(command) do
          outcome(Replay.submit(ctx, decision, principal))
        end
    end
  end

  @doc """
  The reviewer's verdict on `candidate_id`: its receipt, its stream sealed, the verdict
  through `decide/3`, then its close. Each step already committed is skipped.

  A rerun of a committed review is idempotent even after its verdict moved the active
  attempt; any other review of a reviewed attempt or candidate is `review_already_recorded`.
  """
  def review(ctx, ticket_id, principal, verdict, candidate_id, receipt_payload) do
    ticket = Replay.state(ctx)["tickets"][ticket_id] || %{}

    # A committed review's receipt is committed too, and its effect may no longer be current.
    with {:ok, attempt_id, committed?} <-
           review_attempt(ctx, ticket_id, ticket, principal, verdict, candidate_id),
         execution_id = get_in(ticket, ["attempts", attempt_id, "review", "execution_id"]),
         base = %{
           "ticket_id" => ticket_id,
           "attempt_id" => attempt_id,
           "execution_id" => execution_id
         },
         step = &"#{ticket_id}/#{&1}/#{execution_id}",
         command = %{
           "schema_version" => 1,
           "command_id" => step.("submit_review"),
           "type" => "submit_review",
           "target_ids" => %{"ticket_id" => ticket_id},
           "payload" => %{
             "role" => "reviewer",
             "verdict" => verdict,
             "candidate_id" => candidate_id
           },
           "expected_revisions" => %{}
         },
         true <- is_binary(execution_id) || {:reject, :no_issued_claim},
         {:ok, _} <-
           if(committed?,
             do: {:ok, :committed},
             else: deliver(ctx, ticket_id, "reviewer", principal, receipt_payload)
           ),
         {:ok, _} <-
           ingress(
             ctx,
             step.("stream_sealed"),
             ticket_id,
             [
               {"stream_sealed", Map.put(base, "last_accepted_sequence", 0)}
             ],
             principal
           ),
         {:ok, _} <- decided(ctx, command, %{}, principal),
         {:ok, _} <-
           ingress(
             ctx,
             step.("reviewer_closed"),
             ticket_id,
             [{"reviewer_closed", base}],
             principal
           ) do
      {:ok, %{"ticket" => Replay.state(ctx)["tickets"][ticket_id]}}
    end
  end

  # The attempt a review acts on, and whether its verdict is committed. An open review on
  # the active attempt comes first, so an identical review of a later attempt is never taken
  # for a rerun. Then the committed review this one repeats: its `submit_review` command id,
  # which the Gateway dedupes, on any attempt. A committed review it does not repeat, on the
  # active attempt or the same candidate, refuses it. Otherwise the active attempt, whose
  # frozen candidate must be the one named, checked before the receipt, which is a write.
  defp review_attempt(ctx, ticket_id, ticket, principal, verdict, candidate_id) do
    active = ticket["active_attempt_id"]

    reviews =
      for {id, %{"review" => %{"execution_id" => e} = review}} <- ticket["attempts"] || %{},
          is_binary(e),
          do: {id, review, Replay.committed?(ctx, "#{ticket_id}/submit_review/#{e}")}

    same = fn {_id, review, committed?} ->
      committed? and review["verdict"] == verdict and review["candidate_id"] == candidate_id and
        reviewer(ctx, review) == principal
    end

    conflicting = fn {id, review, committed?} ->
      committed? and (id == active or review["candidate_id"] == candidate_id)
    end

    cond do
      Enum.any?(reviews, &match?({^active, _, false}, &1)) -> frozen(ticket, active, candidate_id)
      rerun = Enum.find(reviews, same) -> {:ok, elem(rerun, 0), true}
      Enum.any?(reviews, conflicting) -> {:reject, :review_already_recorded}
      true -> frozen(ticket, active, candidate_id)
    end
  end

  defp frozen(ticket, attempt_id, candidate_id) do
    if get_in(ticket, ["attempts", attempt_id, "candidate_id"]) == candidate_id,
      do: {:ok, attempt_id, false},
      else: {:reject, :candidate_mismatch}
  end

  defp reviewer(ctx, review) do
    effect_id = Plan.id(launch_id(review["execution_id"]), "effect")

    case Replay.query(ctx, %{"type" => "effect", "effect_id" => effect_id}) do
      {:ok, effect} -> effect["issuer"]
      _ -> nil
    end
  end

  @doc """
  An operator-attested settlement of the role's issued claim. `:non_started` is a proved
  non-start through `decide/3` and needs `issuer_gone` and `channel_quiet` both attested
  (FR-10 Quint finding A). `:unknown` holds units and leases, and is refused on an effect
  already settled (FR-10 finding B).
  """
  def settle(ctx, ticket_id, role, principal, :non_started, attestation) do
    with :ok <- attested(attestation, principal),
         :ok <- quiescent(attestation),
         {:ok, effect} <- current_effect(ctx, ticket_id, role, principal) do
      [claim] = effect["claims"]
      launch = launch_id(effect["execution_id"])

      command = %{
        "schema_version" => 1,
        "command_id" => "#{ticket_id}/settle_nonstart/#{effect["execution_id"]}",
        "type" => "settle_nonstart",
        "target_ids" => %{"ticket_id" => ticket_id},
        "payload" => %{"role" => role},
        "expected_revisions" => %{}
      }

      facts = %{
        "settle_claim" => %{
          "type" => "settle_claim",
          "claim_id" => claim["claim_id"],
          "receipt_id" => Plan.id(launch, "receipt"),
          "request_id" => effect["request_id"],
          "outcome" => "non_started",
          "proof" => "issuer_quiescent",
          "payload" =>
            Map.merge(attestation, %{
              "failure_class" => "operator_attested_non_start",
              "quiescence_epoch" => claim["writer_epoch"]
            })
        }
      }

      decided(ctx, command, facts, principal)
    end
  end

  def settle(ctx, ticket_id, role, principal, :unknown, attestation) do
    with :ok <- attested(attestation, principal),
         {:ok, effect} <- current_effect(ctx, ticket_id, role, principal) do
      settle_root(ctx, ticket_id, "settle_unknown", effect, principal, %{
        "outcome" => "unknown",
        "proof" => "outcome_unknown",
        "payload" => attestation
      })
    end
  end

  # ── Steps ─────────────────────────────────────────────────────────────────────

  defp decided(ctx, command, facts, principal) do
    if Replay.committed?(ctx, command["command_id"]) do
      {:ok, %{"command_id" => command["command_id"], "idempotent" => true}}
    else
      with {:ok, decision} <- WorkflowKernel.decide(Replay.state(ctx), command, facts),
           do: outcome(Replay.submit(ctx, decision, principal))
    end
  end

  # The claim's settlement as a root command; the kernel has no event for it (§3).
  defp settle_root(ctx, ticket_id, step, effect, principal, settlement) do
    id = "#{ticket_id}/#{step}/#{effect["execution_id"]}"
    [claim] = effect["claims"]

    cond do
      Replay.committed?(ctx, id) ->
        {:ok, %{"command_id" => id, "idempotent" => true}}

      effect["status"] != "issued" ->
        {:reject, :effect_already_settled}

      true ->
        operation =
          Map.merge(settlement, %{
            "type" => "settle_claim",
            "claim_id" => claim["claim_id"],
            "receipt_id" => Plan.id(launch_id(effect["execution_id"]), "receipt"),
            "request_id" => effect["request_id"]
          })

        outcome(Replay.root(ctx, principal, id, operation))
    end
  end

  defp allow_scope(ctx, ticket_id) do
    scope = "ticket:" <> ticket_id

    with {:ok, policy} <- Replay.query(ctx, %{"type" => "policy", "policy_id" => @ids.policy_id}) do
      value = policy["value"]

      if scope in value["allowed_scopes"] do
        {:ok, policy}
      else
        outcome(
          Replay.root(ctx, @operator, "#{ticket_id}/admit/policy", %{
            "type" => "set_policy",
            "policy_id" => @ids.policy_id,
            "value" => Map.update!(value, "allowed_scopes", &(&1 ++ [scope]))
          })
        )
      end
    end
  end

  # ── Reads ─────────────────────────────────────────────────────────────────────

  # The effect of the role's latest launch on the active attempt. Its issuer must be the
  # principal: Core re-checks that, but a refused command would burn the step's id.
  defp current_effect(ctx, ticket_id, role, principal) do
    ticket = Replay.state(ctx)["tickets"][ticket_id]

    with id when is_binary(id) <- predecessor(ctx, ticket, role),
         {:ok, effect} <- Replay.query(ctx, %{"type" => "effect", "effect_id" => id}),
         true <- effect["issuer"] == principal || {:reject, :receipt_provenance_mismatch} do
      {:ok, effect}
    else
      {:reject, _} = reject -> reject
      _ -> {:reject, :no_issued_claim}
    end
  end

  # The effect of the role's highest-ordinal launch on the active attempt, or nil.
  defp predecessor(ctx, ticket, role) do
    ticket
    |> role_executions(role, [ticket && ticket["active_attempt_id"]])
    |> Enum.map(&Plan.id(launch_id(&1), "effect"))
    |> Enum.map(&Replay.query(ctx, %{"type" => "effect", "effect_id" => &1}))
    |> Enum.flat_map(fn
      {:ok, effect} -> [effect]
      _ -> []
    end)
    |> Enum.max_by(& &1["operation_ordinal"], &>=/2, fn -> nil end)
    |> then(&(&1 && &1["effect_id"]))
  end

  defp open_execution(ticket, role) do
    Enum.find(role_executions(ticket, role, [ticket && ticket["active_attempt_id"]]), fn id ->
      attempt = ticket["attempts"][ticket["active_attempt_id"]]
      attempt["executions"][id].lifecycle != "closed"
    end)
  end

  # Every launch of the role on the ticket, across attempts, so an id is never reused.
  defp role_launches(ticket, role),
    do: length(role_executions(ticket, role, Map.keys((ticket || %{})["attempts"] || %{})))

  defp role_executions(nil, _role, _attempts), do: []

  defp role_executions(ticket, role, attempt_ids) do
    for attempt_id <- attempt_ids,
        attempt = ticket["attempts"][attempt_id],
        attempt != nil,
        {id, %Execution{role: ^role}} <- attempt["executions"] || %{},
        do: id
  end

  defp packet(ctx, ticket_id, effect_id) do
    with {:ok, effect} <- Replay.query(ctx, %{"type" => "effect", "effect_id" => effect_id}),
         {:ok, policy} <- Replay.query(ctx, %{"type" => "policy", "policy_id" => @ids.policy_id}) do
      builder = Map.get(ctx, :work_packet, PramanaFoundry.WorkPacket)
      ticket = Replay.state(ctx)["tickets"][ticket_id]

      with {:ok, packet} <- builder.build(ticket, effect, policy),
           do: {:ok, excluding_developers(ctx, ticket, packet)}
    end
  end

  # A reviewer packet names the attempt's developer issuers, which build/3 cannot see (the
  # kernel ticket carries no principal). Informational: Core enforces independence itself.
  defp excluding_developers(ctx, ticket, %{"role" => "reviewer", "independence" => %{}} = packet) do
    issuers =
      for execution_id <- role_executions(ticket, "developer", [ticket["active_attempt_id"]]),
          effect_id = Plan.id(launch_id(execution_id), "effect"),
          {:ok, %{"issuer" => issuer}} <-
            [Replay.query(ctx, %{"type" => "effect", "effect_id" => effect_id})],
          uniq: true,
          do: issuer

    put_in(packet, ["independence", "excluded_principals"], Enum.sort(issuers))
  end

  defp excluding_developers(_ctx, _ticket, packet), do: packet

  defp launch_id(execution_id), do: String.replace_suffix(execution_id, "/execution", "")

  # ── Refusals ──────────────────────────────────────────────────────────────────

  # A1: every human-asserted receipt says so, by whom, and what.
  defp attested(%{} = payload, principal) do
    if payload["evidence_kind"] == "operator_attestation" and
         payload["attested_by"] == principal and is_binary(payload["statement"]) and
         String.trim(payload["statement"]) != "",
       do: :ok,
       else: {:reject, :attestation_required}
  end

  defp attested(_payload, _principal), do: {:reject, :attestation_required}

  defp quiescent(attestation) do
    if attestation["issuer_gone"] === true and attestation["channel_quiet"] === true,
      do: :ok,
      else: {:reject, :quiescence_not_attested}
  end

  defp lane_id?(ticket_id), do: is_binary(ticket_id) and Regex.match?(@lane_id, ticket_id)

  defp outcome({:ok, %{"disposition" => "accepted"} = result, _how}), do: {:ok, result}

  defp outcome({:ok, %{"reason_code" => reason}, _how}) when is_binary(reason),
    do: {:reject, String.to_atom(reason)}

  defp outcome({:ok, _result, _how}), do: {:reject, :not_accepted}
  defp outcome({:error, _reason} = error), do: error
end
