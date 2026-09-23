defmodule PramanaFoundry.Workflow.Kernel.Executions do
  @moduledoc """
  Execution lifecycle: open and plan executions, observe, seal and close them, settle
  a proved non-start, and consume infrastructure ordinals. Generic across roles.
  """

  import PramanaFoundry.Workflow.Kernel.Control,
    only: [require_no_pending_cancel: 1, require_not_draining: 1, require_not_paused: 1]

  import PramanaFoundry.Workflow.Kernel.Shared,
    only: [
      active_attempt: 1,
      attempt: 2,
      require_active_attempt: 2,
      require_attempt: 2,
      require_phase: 2,
      update_active_attempt: 2,
      update_attempt: 3
    ]

  alias PramanaFoundry.Workflow.Kernel.{Execution, State}

  # R4: "queued; dependencies/resources/profile/reservation eligible; no pause/drain/cancel"
  # — a fresh attempt unless R4a retained a resumable one, then its launch intent, then
  # developing. The three control conjuncts (R4.04.f3) are one guard each, so each refusal
  # is pinned to its own atom.
  def do_transition("launch_planned", ticket, event, state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(queued developing)),
         :ok <- require_no_open_developer(ticket),
         :ok <- require_cleanup_complete(ticket),
         :ok <- require_not_paused(state["control"]),
         :ok <- require_not_draining(state["control"]),
         :ok <- require_no_pending_cancel(ticket),
         {:ok, ticket} <- open_attempt(ticket, payload["attempt_id"]),
         {:ok, ticket} <- add_execution(ticket, payload, "developer") do
      {:ok, Map.put(ticket, "phase", "developing")}
    end
  end

  # R4a developer row: keep the same nonterminal attempt, return developing → queued with
  # resume_phase developing, close the execution, consume one infrastructure ordinal.
  def do_transition("launch_settled", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(developing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         {:ok, ticket} <-
           close_execution(ticket, payload["attempt_id"], payload["execution_id"], ~w(developer)) do
      {:ok,
       ticket
       |> Map.put("phase", "queued")
       |> Map.put("resume_phase", "developing")
       |> Map.put("reason", "developer_launch_non_started")
       |> consume_infrastructure_ordinal("developer")}
    end
  end

  # R4: "candidate_frozen; developer exit/timeout/abnormal exit" — cleanup observation
  # only. The frozen candidate is preserved and no attempt fails, which is the custody rule
  # the reviewed candidate broke.
  def do_transition("execution_observed", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_not_closed(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_open_lifecycle(payload["lifecycle"]) do
      {:ok,
       update_attempt(ticket, payload["attempt_id"], fn attempt ->
         update_in(attempt, ["executions", payload["execution_id"]], fn %Execution{} = e ->
           %{e | lifecycle: payload["lifecycle"]}
         end)
       end)}
    end
  end

  # R4a: "On exit, the broker seals that execution's input stream with its last accepted
  # sequence." Sealing is once-only, so a second seal is refused rather than overwriting.
  def do_transition("stream_sealed", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_unsealed(ticket, payload["attempt_id"], payload["execution_id"]) do
      {:ok,
       update_attempt(ticket, payload["attempt_id"], fn attempt ->
         update_in(attempt, ["executions", payload["execution_id"]], fn %Execution{} = e ->
           %{e | sealed_sequence: payload["last_accepted_sequence"]}
         end)
       end)}
    end
  end

  # R4: "kernel requests developer close through broker immediately". Closure is a durable
  # fact about a sealed execution, not an event carrying the unchanged ticket — B2's first
  # named defect. What R4 conditions closure on is the sealed stream, not the phase: rows 8
  # and 9 close the developer after a valid blocked/partial result and after a sealed
  # stream with no candidate at all, and a candidate_frozen guard made both unexpressible.
  def do_transition("developer_closed", ticket, event, _state) do
    payload = event["payload"]

    # The role check below is redone by close_execution; require_execution is not
    # redundant, because require_sealed indexes into the execution and would raise on one
    # that is absent.
    with :ok <- require_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_sealed(ticket, payload["attempt_id"], payload["execution_id"]) do
      close_execution(ticket, payload["attempt_id"], payload["execution_id"], ~w(developer))
    end
  end

  # R4 rows 11, 13 and 22 all require worker closure: "queue fresh developer after all
  # check workers close", "bounded new check-run reservation after cleanup", and
  # "successful ref receipt and prior role/check workers closed". Nothing could express it
  # until now — the enumeration named closure events for the developer and the reviewer and
  # missed the check, build and integration workers, which `require_workers_closed/1` then
  # caught by making the integration row unreachable.
  #
  # The kernel records this closure rather than verifying it. R4 requires verified process
  # or session termination, which is a protected reconciliation fact owned by FR-10; the
  # link from a check execution to its receipt that would let the kernel demand a recorded
  # status first belongs with subcommit 4's check/build/integration workers.
  def do_transition("worker_closed", ticket, event, _state) do
    payload = event["payload"]

    # `close_execution/4` checks the execution exists and holds one of the roles it is
    # given, so repeating both here was two guards deep enough to look like defence and
    # shallow enough to prove nothing - the mutation sweep reported require_worker_role as
    # surviving even with a test aimed squarely at it, because its sibling caught the same
    # case.
    with :ok <- require_attempt(ticket, payload["attempt_id"]) do
      close_execution(
        ticket,
        payload["attempt_id"],
        payload["execution_id"],
        ~w(check build integration)
      )
    end
  end

  # R4a: "Create a fresh attempt unless R4a retained a resumable developer attempt". A
  # retained attempt is reused; an identifier that already names a *different* attempt is
  # refused rather than overwriting one, which is how the reviewed candidate lost evidence.
  # R4: "Create a fresh attempt **unless R4a retained a resumable developer attempt**", and
  # R4a: "Keep the **same** nonterminal attempt". A launch naming a new id while one was
  # retained left the old attempt nonterminal, absent from prior_attempt_ids and owned by
  # nothing - the validator permits that shape, and the prober always reused the active id,
  # so neither could see it.
  defp open_attempt(ticket, attempt_id) do
    cond do
      ticket["active_attempt_id"] == attempt_id and not is_nil(attempt_id) ->
        {:ok, ticket}

      not is_nil(ticket["active_attempt_id"]) ->
        {:error, :retained_attempt_must_be_reused}

      Map.has_key?(ticket["attempts"], attempt_id) ->
        {:error, :attempt_already_exists}

      true ->
        attempt = %{
          "attempt_id" => attempt_id,
          "phase" => "active",
          "disposition" => nil,
          "reason_code" => nil,
          "candidate_id" => nil,
          "sealed_generation" => nil,
          "ref_receipt_id" => nil,
          "executions" => %{},
          "checks" => %{},
          "review" => nil,
          "policy_empty_checks" => false,
          "rejected_submissions" => 0
        }

        {:ok,
         ticket
         |> put_in(["attempts", attempt_id], attempt)
         |> Map.put("active_attempt_id", attempt_id)}
    end
  end

  def add_execution(ticket, payload, role) do
    execution_id = payload["authority"]["execution_id"]

    cond do
      not is_binary(execution_id) or execution_id == "" ->
        {:error, :invalid_execution_identity}

      Map.has_key?(active_attempt(ticket)["executions"], execution_id) ->
        {:error, :execution_already_exists}

      true ->
        execution = %Execution{
          execution_id: execution_id,
          role: role,
          lifecycle: "pending",
          result: nil,
          sealed_sequence: nil
        }

        {:ok, update_active_attempt(ticket, &put_in(&1, ["executions", execution_id], execution))}
    end
  end

  # R4a: a proved non-start "closes the execution". Every *_settled row calls this, which
  # is why each carries an execution_id. Only launch_settled did before, so reviewer,
  # check, build and integration executions stayed open with nothing able to close them -
  # reviewer_closed requires the reviewing phase, so a settled reviewer execution was
  # unclosable forever, and R4's "prior role/check workers closed" could never hold.
  def close_execution(ticket, attempt_id, execution_id, roles) do
    with :ok <- require_execution(ticket, attempt_id, execution_id),
         :ok <- require_execution_role(ticket, attempt_id, execution_id, roles),
         :ok <- require_not_closed(ticket, attempt_id, execution_id) do
      {:ok,
       update_attempt(
         ticket,
         attempt_id,
         fn a -> update_in(a, ["executions", execution_id], &%{&1 | lifecycle: "closed"}) end
       )}
    end
  end

  # R4a: "The durable infrastructure ordinal consumes that allowance even though a proved
  # non-start refunds the process-start unit." The allowance is per role and work owner, so
  # a reviewer non-start must not spend the developer's. One counter per ticket was the
  # state-shape defect behind finding 12: decide/3 cannot evaluate "below the infrastructure
  # limit" for a role whose consumption it cannot see.
  def consume_infrastructure_ordinal(owner, role),
    do: update_in(owner, ["infrastructure", "ordinals", role], &(&1 + 1))

  # The one predicate behind both `:executions_not_closed` and `:cleanup_incomplete`. It was
  # written twice, and EVIDENCE-TOOLS.md records the consequence: rule 5 pins each refusal
  # test to its own atom, so two tests read as covering two rules while exercising identical
  # logic, and rule 4's partial generalisation -- the most repeated defect shape here, at six
  # occurrences -- was pre-loaded. The atoms stay distinct because the contract rows do; only
  # the rule is shared, so it can no longer be changed in one place and not the other.
  def open_executions(ticket) do
    for {_aid, attempt} <- ticket["attempts"],
        {execution_id, %Execution{} = execution} <- executions(attempt),
        execution.lifecycle != "closed",
        do: execution_id
  end

  @doc "An attempt's executions, keyed by execution id. Empty for an absent attempt."
  @spec executions(map()) :: %{optional(String.t()) => Execution.t()}
  def executions(attempt), do: attempt["executions"] || %{}

  @doc "One execution of an attempt, or nil. Bind the result as `%Execution{}` to read it."
  @spec execution(map(), term()) :: Execution.t() | nil
  def execution(attempt, execution_id), do: executions(attempt)[execution_id]

  def require_execution(ticket, attempt_id, execution_id),
    do:
      if(Map.has_key?(executions(attempt(ticket, attempt_id)), execution_id),
        do: :ok,
        else: {:error, :unknown_execution}
      )

  def require_sealed(ticket, attempt_id, execution_id) do
    if match?(
         %Execution{sealed_sequence: sequence} when is_integer(sequence),
         execution(attempt(ticket, attempt_id), execution_id)
       ),
       do: :ok,
       else: {:error, :stream_not_sealed}
  end

  defp require_unsealed(ticket, attempt_id, execution_id) do
    case execution(attempt(ticket, attempt_id), execution_id) do
      %Execution{sealed_sequence: sequence} when not is_nil(sequence) ->
        {:error, :stream_already_sealed}

      _absent_or_unsealed ->
        :ok
    end
  end

  # R4a binds every settlement and closure to the execution it names: "Close **only the
  # failed reviewer execution**". Correction 8 of 202b8e4 applied that to reviewer_closed
  # and not to review_settled, which is why the latter could close a check execution and
  # leak the reviewer's. The binding is therefore one rule over the vocabulary rather than
  # a guard attached to whichever event a walk happened to reach.
  defp require_execution_role(ticket, attempt_id, execution_id, roles) do
    role =
      case execution(attempt(ticket, attempt_id), execution_id) do
        %Execution{role: role} -> role
        nil -> nil
      end

    if role in roles, do: :ok, else: {:error, :wrong_execution_role}
  end

  # R4a returns a developer non-start to `queued` with `resume_phase: developing` and keeps
  # the attempt. Resuming therefore lands the ticket in `developing` holding an attempt
  # whose only developer execution is the closed non-start, and a retry could not be
  # launched from there - the ticket was stranded, and artifact_frozen was then accepted
  # for a developer that had never run. A launch is legal from either phase, so long as no
  # developer is already running: that is what "bounded developer retry" needs, and what
  # stops a second developer being launched beside a live one.
  defp require_no_open_developer(ticket) do
    if open_role_executions(ticket, "developer") == [],
      do: :ok,
      else: {:error, :developer_already_running}
  end

  @doc "The ids of the active attempt's executions of `role` that are not closed."
  @spec open_role_executions(map() | nil, String.t()) :: [String.t()]
  def open_role_executions(ticket, role) do
    for {execution_id, %Execution{role: ^role} = execution} <-
          executions(active_attempt(ticket || %{})),
        execution.lifecycle != "closed",
        do: execution_id
  end

  # Three R4 rows order a fresh developer after cleanup, in three phrasings of one rule:
  # "after cleanup queue fresh bounded attempt", "queue fresh developer **after all check
  # workers close**", and "close/seal reviewer, **then** queued fresh developer". None was
  # a guard, and `require_no_open_developer/1` reads only the active attempt, so its stated
  # purpose held within one attempt while a new attempt could launch beside a live reviewer
  # or check worker of the attempt just settled.
  #
  # `unknown` blocks too, per R4: "If cleanup is unknown, block affected work and retain
  # capacity". Only `closed` is cleanup.
  defp require_cleanup_complete(ticket) do
    if open_executions(ticket) == [], do: :ok, else: {:error, :cleanup_incomplete}
  end

  # Closure is terminal for an execution. Refusing only a `closed` *target* was not
  # enough: an observation could reopen an execution that developer_closed or
  # reviewer_closed had already closed, which undoes exactly the custody B2 asks for and
  # left R4's integration row unsatisfiable, since "prior role/check workers closed" could
  # be falsified after the fact. Found by a seeded reachability walk, which kept arriving
  # at `integrating` with a developer and reviewer execution back in `running`.
  defp require_not_closed(ticket, attempt_id, execution_id) do
    if match?(
         %Execution{lifecycle: "closed"},
         execution(attempt(ticket, attempt_id), execution_id)
       ),
       do: {:error, :execution_already_closed},
       else: :ok
  end

  # R4: "closed requires verified process/session termination or proved non-start". An
  # ordinary observation is neither, so `execution_observed` may move an execution through
  # every lifecycle except the one that ends it. Closure has its own guarded events, which
  # is the generalisation of B2's finding that `reviewer_closed` trusted an observation
  # string.
  defp require_open_lifecycle(lifecycle) do
    if lifecycle in (State.execution_lifecycles() -- ["closed"]),
      do: :ok,
      else: {:error, :invalid_execution_lifecycle}
  end
end
