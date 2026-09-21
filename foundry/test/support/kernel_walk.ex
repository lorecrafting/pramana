defmodule PramanaFoundry.Test.KernelWalk do
  alias PramanaFoundry.Workflow.Kernel.State

  @moduledoc """
  A reachability-driven generator for the FR-08B domain kernel.

  Table-driven tests sample the R4 row product; this walks it. At each step it proposes
  every event R4 makes conceivable from the current state, shuffles them under a fixed
  seed, and applies the first the kernel accepts — recording both what stuck and what was
  refused.

  **The proposals are derived from R4's rows, never from the reducer's guards.** A
  generator built from the implementation can only reproduce it: it would proposes exactly
  what the kernel accepts and could never reveal a contract row the kernel cannot reach.
  That reachability gap is the defect class this repository keeps finding by hand —
  `launch_authority_v1` with no producer, `review_settled` with no slot, `worker_closed`
  with no event — each caught late by a reviewer or by an implementation guard. Coverage
  computed from an independent proposer turns it into a test.

  Determinism is a requirement, not a convenience: every walk is seeded, so a
  counterexample is a seed plus a step count, replayable exactly under the repository's
  seed-pinned evidence model.
  """

  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.Event

  @default_tickets ~w(T1 T2 T3)
  @objective "O1"

  # Events that end a lifecycle, demoted probabilistically rather than absolutely.
  #
  # Both extremes fail. Ranking them only within their own coverage tier let an unseen
  # attempt_settled beat the already-seen stream_sealed the reviewer execution needed, so
  # every attempt died in `reviewing`. Sorting them behind every non-terminating candidate
  # instead meant they never fired at all, because control_changed and the PM rows are
  # always acceptable, so the walk is never actually stuck. A lifecycle that cannot end is
  # as unexplored as one that ends immediately.
  @terminating ~w(attempt_settled cancellation_requested cancellation_finalized)

  # Acceptable from almost any state, so they crowd out lifecycle progress if left alone.
  @background ~w(control_changed objective_created pm_proposal_recorded
                 pm_launch_planned pm_launch_settled)

  defstruct state: nil,
            sequence: 0,
            accepted: [],
            rejected: [],
            counter: 0,
            tickets: [],
            sequential: false,
            terminating_period: 7,
            background_period: 11

  @doc """
  Walks up to `steps` accepted events from `state` under `seed`.

  Returns the struct with the final state, the accepted event log in order, and every
  {type, reason} rejection observed along the way.
  """
  def walk(state, seed, steps, opts \\ []) do
    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 3})

    run(
      %__MODULE__{
        state: state,
        tickets: Keyword.get(opts, :tickets, @default_tickets),
        sequential: Keyword.get(opts, :sequential, false),
        terminating_period: Keyword.get(opts, :terminating_period, 7),
        background_period: Keyword.get(opts, :background_period, 11)
      },
      steps
    )
  end

  @doc """
  A walk configured for depth rather than breadth: one ticket, and the demoted tiers
  admitted far more rarely.

  Reachability and invariant checking want opposite configurations. Invariants want many
  short interleaved lifecycles; reachability wants one lifecycle driven as far as it goes,
  because the deepest rows sit behind a long prerequisite chain that broad exploration
  keeps interrupting.
  """
  # R4: "New work requires explicit admission linked to predecessor". A deep walk drives
  # one ticket at a time, but it must be able to admit a *successor* once that ticket is
  # terminal. Without this every deep walk died with its single ticket - twenty of
  # twenty-five ended cancelled and five rejected - and then idled its remaining hundreds
  # of steps on background events. That, not a depth limit, is why the integration rows
  # were never reached, and raising the step budget made it worse rather than better.
  def deep(state, seed, steps) do
    walk(state, seed, steps,
      tickets: ~w(T1 T2 T3 T4 T5),
      sequential: true,
      terminating_period: 40,
      background_period: 40
    )
  end

  defp run(walk, 0), do: walk

  defp run(walk, steps) do
    case advance(walk, ordered(walk)) do
      {:ok, walk} -> run(walk, steps - 1)
      :stuck -> walk
    end
  end

  # Coverage-guided rather than uniform: types never yet accepted go first, then
  # non-terminating ones, then random under the seed. Uniform shuffling drowned in the
  # events that are legitimately repeatable - one walk accepted control_changed 88 times
  # and never reached the check, review or integration rows at all.
  #
  # The first key is "seen at all", not "seen least". Ranking by count pushed genuinely
  # recurring prerequisites to the back: stream_sealed had to fire again for the reviewer
  # execution, but its count from the developer execution buried it, so the reviewer
  # stream was never sealed and the verdict rows stayed unreachable.
  defp ordered(walk) do
    seen = Enum.frequencies(Enum.map(walk.accepted, &label/1))

    walk
    |> candidates()
    |> Enum.sort_by(fn {type, _id, _payload} = candidate ->
      {demotion(walk, type), if(Map.has_key?(seen, label(candidate)), do: 1, else: 0),
       :rand.uniform()}
    end)
  end

  # Applies proposals until one is accepted. A rejection is data, not a failure: it is how
  # the walk records which rows the kernel refuses from this state.
  defp advance(_walk, []), do: :stuck

  defp advance(walk, [{type, entity_id, payload} | rest]) do
    sequence = walk.sequence + 1
    event = build(walk, type, entity_id, payload, sequence)

    case WorkflowKernel.apply(walk.state, event) do
      {:ok, next} when next != walk.state ->
        {:ok,
         %{
           walk
           | state: next,
             sequence: sequence,
             accepted: walk.accepted ++ [event],
             counter: walk.counter + 1
         }}

      {:ok, _unchanged} ->
        advance(%{walk | rejected: [{type, :idempotent_no_op} | walk.rejected]}, rest)

      {:error, reason} ->
        advance(%{walk | rejected: [{type, reason} | walk.rejected]}, rest)
    end
  end

  defp build(walk, type, entity_id, payload, sequence) do
    {:ok, kind} = Event.entity_kind(type)

    %{
      "schema_version" => 1,
      "event_id" => "evt-#{sequence}-#{type}",
      "type" => type,
      "sequence" => sequence,
      "entity_kind" => kind,
      "entity_id" => entity_id,
      "entity_revision" => revision(walk.state, kind, entity_id),
      "payload" => payload
    }
  end

  @doc """
  The coverage target a proposal or accepted event belongs to.

  R4's rows are *variants* - approved versus rejected verdict, passed versus failed check,
  nine terminal dispositions - so coverage keyed on the bare event type treats a row as
  covered the moment any one of its variants fires. That is how the deepest rows stayed
  unreachable: one walk in twenty-five ever reached `integrating`, because getting there
  needed the approved verdict specifically and the type was already marked seen.
  """
  def label(%{"type" => type, "payload" => payload}), do: label({type, nil, payload})

  def label({type, _entity_id, payload}) do
    case type do
      "review_recorded" -> "review_recorded:" <> to_string(payload["verdict"])
      "attempt_settled" -> "attempt_settled:" <> to_string(payload["disposition"])
      "check_recorded" -> "check_recorded:" <> to_string(payload["status"])
      "integration_recorded" -> "integration_recorded:" <> to_string(payload["outcome"])
      "ticket_admitted" -> "ticket_admitted:" <> to_string(payload["phase"])
      "freeze_failed" -> "freeze_failed:" <> to_string(payload["disposition"])
      "cancellation_finalized" -> "cancellation_finalized:" <> to_string(payload["disposition"])
      "execution_observed" -> "execution_observed:" <> to_string(payload["lifecycle"])
      other -> other
    end
  end

  @doc """
  Every variant label R4 distinguishes, derived from the contract's own vocabularies.

  Declared rather than collected from what the prober happens to propose: a variant nobody
  proposes must fail the reachability assertion, not vanish from it. Two confirmed blockers
  lived in exactly that blind spot.

  One exclusion, and it is a contract claim open to review: `execution_observed:closed` is
  absent because R4 says a `closed` lifecycle "requires verified process/session termination
  or proved non-start", so closure has its own guarded events and an observation may never
  produce it.
  """
  def variants do
    Enum.sort(
      for({d, _} <- [{nil, nil}], do: d) ++
        Enum.map(State.dispositions(), &"attempt_settled:#{&1}") ++
        Enum.map(State.verdicts(), &"review_recorded:#{&1}") ++
        Enum.map(State.check_statuses(), &"check_recorded:#{&1}") ++
        Enum.map(
          ~w(ref_created no_ref_change infrastructure_failed),
          &"integration_recorded:#{&1}"
        ) ++
        Enum.map(~w(queued blocked), &"ticket_admitted:#{&1}") ++
        Enum.map(~w(retry blocked unknown), &"freeze_failed:#{&1}") ++
        Enum.map(~w(cancelled after_integration), &"cancellation_finalized:#{&1}") ++
        Enum.map(State.execution_lifecycles() -- ["closed"], &"execution_observed:#{&1}")
    )
    |> Enum.reject(&is_nil/1)
  end

  # Two demoted tiers, each admitted on its own period. The decision is per step, not per
  # candidate: rolling a probability per candidate multiplied, since attempt_settled offers
  # nine dispositions, and nine rolls at p=0.85 let one through three steps in four.
  #
  # Background events are demoted for the same reason terminating ones are, from the
  # opposite direction. control_changed and the PM rows are acceptable from almost every
  # state, so left at full priority they win most steps and the ticket lifecycle advances
  # only in the gaps. With three tickets competing that was enough to put the integration
  # rows out of reach: one seed in forty reached integration_planned at all, on step 403.
  defp demotion(walk, type) do
    cond do
      type in @terminating -> tier(walk.counter, walk.terminating_period, 2)
      type in @background -> tier(walk.counter, walk.background_period, 1)
      true -> 0
    end
  end

  defp tier(counter, period, rank), do: if(rem(counter, period) == 0, do: 0, else: rank)

  defp revision(state, "control", _id), do: state["control"]["revision"]
  defp revision(state, "ticket", id), do: get_in(state, ["tickets", id, "revision"]) || 0
  defp revision(state, "objective", id), do: get_in(state, ["objectives", id, "revision"]) || 0

  # ── Proposals, one group per R4 row family ─────────────────────────────────────────

  @doc "Every event R4 makes conceivable from this state, regardless of kernel guards."
  def candidates(walk) do
    state = walk.state

    control(walk) ++
      objective(state) ++
      Enum.flat_map(admissible(walk), fn id ->
        ticket = state["tickets"][id]
        ticket_level(id, ticket) ++ attempt_level(id, ticket)
      end)
  end

  # A sequential walk keeps one live ticket at a time, which is what makes it deep, but it
  # may admit the next id once the current one is terminal. A broad walk interleaves all of
  # its ids from the start, which is what makes it broad.
  defp admissible(%{sequential: false} = walk), do: walk.tickets

  defp admissible(%{sequential: true} = walk) do
    live = Enum.filter(walk.tickets, &live_ticket?(walk.state, &1))

    case live do
      [] -> Enum.take(Enum.filter(walk.tickets, &is_nil(walk.state["tickets"][&1])), 1)
      ids -> ids
    end
  end

  defp live_ticket?(state, id) do
    case state["tickets"][id] do
      nil -> false
      ticket -> ticket["phase"] not in ~w(integrated rejected cancelled)
    end
  end

  defp control(walk) do
    n = walk.counter

    [
      {"control_changed", "control",
       %{
         "paused" => rem(n, 3) == 0,
         "draining" => rem(n, 5) == 0,
         "stop_status" =>
           Enum.at(~w(running stop_requested stop_blocked stop_completed), rem(n, 4)),
         "control" => %{
           "schema_version" => 1,
           "control_id" => "ctl-1",
           "control_revision" => n
         }
       }}
    ]
  end

  defp objective(state) do
    base = [
      {"objective_created", @objective,
       %{"objective_id" => @objective, "planning_owner_id" => "pm-1"}}
    ]

    if state["objectives"][@objective] do
      base ++
        [
          {"pm_proposal_recorded", @objective,
           %{
             "proposal_id" => "prop-#{map_size(state["objectives"][@objective]["proposals"])}",
             "objective_id" => @objective,
             "operation" => "create"
           }},
          {"pm_launch_planned", @objective,
           %{
             "objective_id" => @objective,
             "planning_owner_id" => "pm-1",
             "authority" => authority(@objective, "PM1", "pm")
           }},
          {"pm_launch_settled", @objective,
           %{"objective_id" => @objective, "settlement" => settlement()}}
        ]
    else
      base
    end
  end

  defp ticket_level(tid, nil) do
    for phase <- ~w(queued blocked) do
      {"ticket_admitted", tid,
       %{
         "ticket_id" => tid,
         "objective_id" => nil,
         "spec_revision_id" => "spec-1",
         "spec" => %{},
         "phase" => phase,
         "reason" => nil
       }}
    end
  end

  defp ticket_level(tid, ticket) do
    [
      {"ticket_amended", tid,
       %{"ticket_id" => tid, "spec_revision_id" => "spec-2", "spec" => %{}}},
      # Proposals come from R4, never from the state the kernel happens to be in. Deriving
      # this from the ticket's current phase was the confirmed circularity: the kernel's
      # require_honest_resume_target then accepted whatever the prober offered, and the two
      # agreed on `resume_phase: blocked` - a ticket blocked with no reason and no target,
      # which R4's resume row ("return to stored resume_phase") forbids. R4's park row
      # blocks queued or blocked work, and the phase it promises to return to is a phase
      # work can actually resume at.
      {"ticket_parked", tid,
       %{"ticket_id" => tid, "reason" => "dependency", "resume_phase" => "queued"}},
      {"ticket_parked", tid,
       %{"ticket_id" => tid, "reason" => "dependency", "resume_phase" => "developing"}},
      {"ticket_resumed", tid, %{"ticket_id" => tid, "phase" => ticket["resume_phase"]}},
      {"ticket_reset", tid, %{"ticket_id" => tid, "generation" => reset_fact()}},
      {"cancellation_requested", tid, %{"ticket_id" => tid}},
      {"cancellation_finalized", tid, %{"ticket_id" => tid, "disposition" => "cancelled"}},
      # Never proposed before. R4's cancel row is a conditional and this is its other
      # branch; the kernel accepted it from an empty ticket and produced an integrated
      # ticket with no attempt at all - blocker B1's headline counterexample, invisible to
      # a walk that only ever offered the first branch.
      {"cancellation_finalized", tid,
       %{"ticket_id" => tid, "disposition" => "after_integration"}},
      {"launch_planned", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => next_attempt(tid, ticket),
         "authority" => authority(tid, "X#{map_size(ticket["attempts"])}", "developer")
       }}
    ]
  end

  # Everything that names an attempt. Proposed against the active attempt when there is
  # one, because R4's rows are written about the attempt that owns the work.
  defp attempt_level(_tid, nil), do: []

  defp attempt_level(_tid, %{"active_attempt_id" => nil}), do: []

  defp attempt_level(tid, ticket) do
    attempt = ticket["attempts"][ticket["active_attempt_id"]]
    id = attempt["attempt_id"]
    executions = Map.keys(attempt["executions"])
    checks = Map.keys(attempt["checks"])
    candidate = attempt["candidate_id"] || "cand-1"

    settle(tid, id) ++
      artifacts(tid, id, candidate) ++
      per_execution(tid, id, executions) ++
      per_check(tid, id, checks) ++
      checkwork(tid, id, attempt, checks) ++
      reviewwork(tid, id, attempt, candidate) ++
      integration(tid, id, attempt["executions"])
  end

  defp settle(tid, id) do
    for disposition <- ~w(integrated needs_correction failed timed_out blocked exhausted
                          rejected cancelled superseded_base) do
      {"attempt_settled", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "disposition" => disposition,
         "reason_code" => nil,
         "settlement" => settlement()
       }}
    end
  end

  defp artifacts(tid, id, candidate) do
    [
      {"artifact_frozen", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "candidate_id" => candidate,
         "observation_id" => "obs-1",
         "sealed_generation" => "gen-1"
       }},
      {"artifact_blocked", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "observation_id" => "obs-2",
         "result" => "partial",
         "reason" => "partial_result"
       }},
      {"freeze_failed", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "disposition" => "blocked",
         "reason" => "freeze_failure"
       }},
      {"freeze_failed", tid,
       %{"ticket_id" => tid, "attempt_id" => id, "disposition" => "retry", "reason" => nil}},
      {"freeze_failed", tid,
       %{"ticket_id" => tid, "attempt_id" => id, "disposition" => "unknown", "reason" => nil}},
      {"submission_rejected", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "observation_id" => "obs-3",
         "reason" => "malformed"
       }}
    ]
  end

  defp per_execution(tid, id, executions) do
    for execution <- executions,
        proposal <- [
          {"stream_sealed",
           %{
             "ticket_id" => tid,
             "attempt_id" => id,
             "execution_id" => execution,
             "last_accepted_sequence" => 5
           }},
          {"developer_closed",
           %{"ticket_id" => tid, "attempt_id" => id, "execution_id" => execution}},
          {"worker_closed",
           %{"ticket_id" => tid, "attempt_id" => id, "execution_id" => execution}},
          {"reviewer_closed",
           %{"ticket_id" => tid, "attempt_id" => id, "execution_id" => execution}},
          # R4's execution lifecycle vocabulary, not a hand-picked subset of it - listing
          # values by hand is how `unknown` came to be missing, and require_workers_closed
          # wrongly counted it as closed. `closed` is excluded because R4 gives closure its
          # own guarded events: an observation may never produce it.
          {"execution_observed",
           %{
             "ticket_id" => tid,
             "attempt_id" => id,
             "execution_id" => execution,
             "observation" => "pending",
             "lifecycle" => "pending"
           }},
          {"execution_observed",
           %{
             "ticket_id" => tid,
             "attempt_id" => id,
             "execution_id" => execution,
             "observation" => "starting",
             "lifecycle" => "starting"
           }},
          {"execution_observed",
           %{
             "ticket_id" => tid,
             "attempt_id" => id,
             "execution_id" => execution,
             "observation" => "running",
             "lifecycle" => "running"
           }},
          {"execution_observed",
           %{
             "ticket_id" => tid,
             "attempt_id" => id,
             "execution_id" => execution,
             "observation" => "closing",
             "lifecycle" => "closing"
           }},
          {"execution_observed",
           %{
             "ticket_id" => tid,
             "attempt_id" => id,
             "execution_id" => execution,
             "observation" => "unknown",
             "lifecycle" => "unknown"
           }},
          {"launch_settled",
           %{
             "ticket_id" => tid,
             "attempt_id" => id,
             "execution_id" => execution,
             "settlement" => settlement()
           }}
        ] do
      {type, payload} = proposal
      {type, tid, payload}
    end
  end

  defp per_check(tid, id, checks) do
    for check <- checks,
        status <- State.check_statuses() do
      {"check_recorded", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "check_id" => check,
         "status" => status,
         "reason_code" => nil
       }}
    end
  end

  defp checkwork(tid, id, attempt, checks) do
    [
      {"checks_started", tid, %{"ticket_id" => tid, "attempt_id" => id, "policy_empty" => false}},
      # R4: "checks with explicit policy-empty set follow same guarded transition".
      {"checks_started", tid, %{"ticket_id" => tid, "attempt_id" => id, "policy_empty" => true}},
      {"check_planned", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "check_id" => "C#{length(checks)}",
         "authority" => authority(tid, "K#{length(checks)}", "check")
       }},
      {"check_settled", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "check_id" => List.first(checks) || "C0",
         "execution_id" => role_execution(attempt, "check"),
         "settlement" => settlement()
       }},
      {"build_planned", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "build_id" => "B0",
         "authority" => authority(tid, "BX#{map_size(attempt["executions"])}", "build")
       }},
      {"build_settled", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "build_id" => "B0",
         "execution_id" => role_execution(attempt, "build"),
         "settlement" => settlement()
       }}
    ]
  end

  defp reviewwork(tid, id, attempt, candidate) do
    [
      {"review_planned", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "authority" => authority(tid, "R#{map_size(attempt["executions"])}", "reviewer")
       }},
      {"review_settled", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "execution_id" =>
           (attempt["review"] || %{})["execution_id"] || role_execution(attempt, "reviewer"),
         "settlement" => settlement()
       }}
    ] ++
      for verdict <- ~w(approved correction rejected) do
        {"review_recorded", tid,
         %{
           "ticket_id" => tid,
           "attempt_id" => id,
           "candidate_id" => candidate,
           "verdict" => verdict
         }}
      end
  end

  defp integration(tid, id, executions) do
    # R4's integration row names the integration execution's own receipt. Proposing an
    # arbitrary execution id here left the row permanently unreachable, which the
    # coverage assertion reported as a missing contract row rather than a weak prober.
    integration_id =
      executions
      |> Enum.find(fn {_id, execution} -> execution["role"] == "integration" end)
      |> case do
        {found, _execution} -> found
        nil -> "I0"
      end

    [
      {"integration_planned", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "authority" => authority(tid, "I#{map_size(executions)}", "integration")
       }},
      {"integration_settled", tid,
       %{
         "ticket_id" => tid,
         "attempt_id" => id,
         "execution_id" => integration_id,
         "settlement" => settlement()
       }}
    ] ++
      for outcome <- ~w(ref_created no_ref_change infrastructure_failed) do
        {"integration_recorded", tid,
         %{
           "ticket_id" => tid,
           "attempt_id" => id,
           "execution_id" => integration_id,
           "outcome" => outcome,
           "ref_receipt_id" => "ref-1"
         }}
      end
  end

  defp next_attempt(tid, ticket),
    do: ticket["active_attempt_id"] || "#{tid}-A#{map_size(ticket["attempts"])}"

  # Protected facts are shaped as the codec shapes them. The kernel only checks shape and
  # copies identity, so a fixture is honest here in a way it would not be for the gateway.
  def authority(tid, execution_id, role) do
    %{
      "schema_version" => 1,
      "effect_id" => "eff-#{execution_id}",
      "role" => role,
      "work_owner" => "own-1",
      "ticket_id" => tid,
      "attempt_id" => "A0",
      "execution_id" => execution_id,
      "policy_id" => "pol-1",
      "policy_revision" => 0,
      "control_id" => "ctl-1",
      "control_revision" => 0,
      "predecessor_effect_id" => nil,
      "infrastructure_generation" => 0
    }
  end

  # The execution a settlement names must be an OPEN one of that role's: closure is
  # terminal, so naming a stale closed execution settles nothing and the row is refused.
  defp role_execution(attempt, role) do
    attempt["executions"]
    |> Enum.find(fn {_id, execution} ->
      execution["role"] == role and execution["lifecycle"] != "closed"
    end)
    |> case do
      {id, _execution} -> id
      nil -> "absent"
    end
  end

  defp settlement, do: %{"schema_version" => 1}
  defp reset_fact, do: %{"schema_version" => 1}
end
