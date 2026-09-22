defmodule PramanaFoundry.Workflow.Kernel.State do
  @moduledoc """
  Versioned, pure domain state for the FR-08B workflow reducer.

  Root authority is deliberately absent. Identifiers and revisions appear here; policy,
  control, claim, receipt and ledger truth remain owned by the protected store, and the
  kernel may not restate them.

  `well_formed?/1` is **total over what the reducer reads**. The reviewed candidate's
  validator checked the outer containers and four control fields, so a ticket whose value
  was an integer passed it and then raised inside a source guard — the public decision
  function was not total over the state its own validator declared valid. That was
  blocker B1's second half. Every nested value the reducer touches is therefore validated
  here, against the closed vocabularies R4 defines, and a map's key must equal the
  identifier its own value carries so that addressing one entity cannot mutate another.

  ## Two validators, and why only one of them refuses

  `well_formed?/1` is a **shape** validator and `apply/2` refuses any state it rejects - on
  input as `:invalid_state`, and since 2026-09-22 on its own committed output as
  `:malformed_post_state` (kernel property 6), so an accepted state is well-formed by
  construction. `invariant?/1` is the **relational** oracle — whether the facts in an accepted state are
  mutually coherent — and `apply/2` does not call it. A test harness asserts it after every
  accepted transition instead (EV-3). Having the reducer refuse a violating post-state is a
  behaviour change on a gate-validated kernel and needs its own review; it is deferred until
  the assert-only form has run clean for a full subcommit.

  The split is not a taxonomy. `valid_attempt_order?/1`'s last conjunct — the active attempt
  is not terminal — is relational by any reading and stays on the refusing side anyway,
  because measurement said so. Dropping it and re-running the bounded search from every
  corrupted state (3,358 distinct, depth 6): **0 of 243,643 proposals returned
  `:kernel_raised`**, so the totality property above survives the move and the argument for
  keeping it there was false. But 43,497 transitions were then accepted, and 753 of them
  produced a state `invariant?/1` calls **clean** — every one an `attempt_settled`, of which
  **406 overwrite a settled disposition** (338 `exhausted`, 60 `blocked`, 4 `failed`, 4
  `timed_out`, all to `cancelled`) against R4's "Attempt disposition | Set once on terminal".
  An assert-only oracle reports; only `well_formed?/1` refuses, so the conjunct stays. The
  same measurement then deleted `invariant?/1`'s own `terminal_custody` clause, which
  restated this conjunct and could fire only where the validator already refuses — leaving
  this the sole check on the class rather than one of two.
  """

  # R4 "Entity | States / terminal boundary".
  @ticket_phases ~w(draft queued developing awaiting_review reviewing ready_to_integrate
                    integrating integrated blocked exhausted rejected cancelled)
  @attempt_phases ~w(active candidate_frozen checking awaiting_review reviewing
                     ready_to_integrate integrating terminal)
  @dispositions ~w(integrated needs_correction failed timed_out blocked exhausted rejected
                   cancelled superseded_base)
  @execution_lifecycles ~w(pending starting running closing closed unknown)
  @execution_results ~w(valid blocked partial invalid none)
  @check_statuses ~w(pending running passed failed timed_out unknown cancelled)
  @stop_statuses ~w(running stop_requested stop_blocked stop_completed)
  @verdicts ~w(approved correction rejected)
  @roles ~w(developer reviewer pm check build integration)

  # R4a: "Protected policy sets a finite launch_non_start_limit per role and work owner",
  # and every proved non-start records (role, work_owner, ..., infrastructure_attempt_ordinal).
  # One counter per ticket made a reviewer non-start consume the developer's allowance, and
  # left the PM limit unrepresentable because objectives carried no infrastructure at all.
  # The work owner holds one ordinal per role it can own; the generation stays per owner,
  # because R4a's policy reset creates a new generation for the owner, not for one role.
  @ticket_roles ~w(developer reviewer check build integration)
  @objective_roles ~w(pm)

  @state_keys ~w(schema_version control objectives tickets last_sequence last_event_id)
  @control_keys ~w(paused draining stop_status generation control_id control_revision
                   revision last_event_id)
  @objective_keys ~w(objective_id planning_owner_id proposals infrastructure revision
                     last_event_id)
  @proposal_keys ~w(proposal_id operation)
  @ticket_keys ~w(ticket_id objective_id spec_revision_id spec phase reason resume_phase
                  cancel_requested attempts active_attempt_id prior_attempt_ids
                  infrastructure revision last_event_id)
  @infrastructure_keys ~w(ordinals generation)
  @attempt_keys ~w(attempt_id phase disposition reason_code candidate_id sealed_generation
                   ref_receipt_id executions checks review policy_empty_checks
                   rejected_submissions)
  @execution_keys ~w(execution_id role lifecycle result sealed_sequence)
  @check_keys ~w(check_id status reason_code)
  @review_keys ~w(candidate_id verdict execution_id)

  def ticket_phases, do: @ticket_phases
  def attempt_phases, do: @attempt_phases
  def dispositions, do: @dispositions
  def execution_lifecycles, do: @execution_lifecycles
  def execution_results, do: @execution_results
  def check_statuses, do: @check_statuses
  def verdicts, do: @verdicts
  def roles, do: @roles
  def ticket_roles, do: @ticket_roles
  def objective_roles, do: @objective_roles

  @doc "A fresh per-role infrastructure record for a work owner of the given roles."
  @spec infrastructure([String.t()]) :: map()
  def infrastructure(roles),
    do: %{"generation" => 0, "ordinals" => Map.new(roles, &{&1, 0})}

  @spec new() :: map()
  def new do
    %{
      "schema_version" => 1,
      "control" => %{
        "paused" => false,
        "draining" => false,
        "stop_status" => "running",
        "generation" => 0,
        "control_id" => nil,
        "control_revision" => 0,
        "revision" => 0,
        "last_event_id" => nil
      },
      "objectives" => %{},
      "tickets" => %{},
      "last_sequence" => nil,
      "last_event_id" => nil
    }
  end

  @spec well_formed?(term()) :: boolean()
  def well_formed?(state) do
    plain_map?(state) and exact_keys?(state, @state_keys) and state["schema_version"] == 1 and
      valid_control?(state["control"]) and
      valid_collection?(state["objectives"], "objective_id", &valid_objective?/1) and
      valid_collection?(state["tickets"], "ticket_id", &valid_ticket?/1) and
      optional_nonnegative_integer?(state["last_sequence"]) and
      optional_identifier?(state["last_event_id"])
  rescue
    _ -> false
  end

  # Every entity map is keyed by the identifier its own value carries. Without this an
  # event naming one identifier could be applied under another key, and replay would
  # reconstruct a different entity than the live path mutated.
  defp valid_collection?(collection, id_key, valid?) do
    plain_map?(collection) and
      Enum.all?(collection, fn {key, value} ->
        is_binary(key) and plain_map?(value) and value[id_key] == key and valid?.(value)
      end)
  end

  defp valid_control?(control) do
    plain_map?(control) and exact_keys?(control, @control_keys) and
      is_boolean(control["paused"]) and is_boolean(control["draining"]) and
      control["stop_status"] in @stop_statuses and
      nonnegative_integer?(control["generation"]) and
      optional_identifier?(control["control_id"]) and
      nonnegative_integer?(control["control_revision"]) and
      nonnegative_integer?(control["revision"]) and
      optional_identifier?(control["last_event_id"])
  end

  defp valid_objective?(objective) do
    exact_keys?(objective, @objective_keys) and identifier?(objective["objective_id"]) and
      identifier?(objective["planning_owner_id"]) and
      valid_collection?(objective["proposals"], "proposal_id", &valid_proposal?/1) and
      valid_infrastructure?(objective["infrastructure"], @objective_roles) and
      nonnegative_integer?(objective["revision"]) and
      optional_identifier?(objective["last_event_id"])
  end

  defp valid_proposal?(proposal) do
    exact_keys?(proposal, @proposal_keys) and identifier?(proposal["proposal_id"]) and
      identifier?(proposal["operation"])
  end

  defp valid_ticket?(ticket) do
    exact_keys?(ticket, @ticket_keys) and identifier?(ticket["ticket_id"]) and
      optional_identifier?(ticket["objective_id"]) and
      identifier?(ticket["spec_revision_id"]) and plain_map?(ticket["spec"]) and
      ticket["phase"] in @ticket_phases and optional_identifier?(ticket["reason"]) and
      (is_nil(ticket["resume_phase"]) or ticket["resume_phase"] in @ticket_phases) and
      is_boolean(ticket["cancel_requested"]) and
      valid_collection?(ticket["attempts"], "attempt_id", &valid_attempt?/1) and
      optional_identifier?(ticket["active_attempt_id"]) and
      valid_attempt_order?(ticket) and
      valid_infrastructure?(ticket["infrastructure"], @ticket_roles) and
      nonnegative_integer?(ticket["revision"]) and
      optional_identifier?(ticket["last_event_id"])
  end

  # R4a keeps the same nonterminal attempt across a proved non-start, and R4 requires
  # prior attempts to be retained rather than replaced. Both are only meaningful if every
  # named attempt exists, the active one is nonterminal, and the two sets are disjoint —
  # the reviewed candidate lost reviewer executions and terminal evidence precisely by
  # replacing an attempt that nothing else still referenced.
  #
  # The last conjunct is relational, not shape, and EV-3 proposed moving it to
  # `invariant?/1`. It stays because measurement refused the move, not because the
  # taxonomy does — see "Two validators" above. It is the only thing refusing 406
  # disposition overwrites of an already-settled attempt, and the oracle calls every one
  # of the resulting states clean.
  defp valid_attempt_order?(ticket) do
    attempts = ticket["attempts"]
    prior = ticket["prior_attempt_ids"]
    active = ticket["active_attempt_id"]

    is_list(prior) and Enum.all?(prior, &identifier?/1) and
      length(Enum.uniq(prior)) == length(prior) and
      Enum.all?(prior, &Map.has_key?(attempts, &1)) and
      active not in prior and
      (is_nil(active) or
         (Map.has_key?(attempts, active) and attempts[active]["phase"] != "terminal"))
  end

  # The ordinal map is exact over the owner's roles, not merely a map of integers: a
  # missing role would make "below the limit" unanswerable for it, and an extra one would
  # let a role consume an allowance R4a never gave it.
  defp valid_infrastructure?(infrastructure, roles) do
    plain_map?(infrastructure) and exact_keys?(infrastructure, @infrastructure_keys) and
      nonnegative_integer?(infrastructure["generation"]) and
      plain_map?(infrastructure["ordinals"]) and
      exact_keys?(infrastructure["ordinals"], roles) and
      Enum.all?(Map.values(infrastructure["ordinals"]), &nonnegative_integer?/1)
  end

  defp valid_attempt?(attempt) do
    exact_keys?(attempt, @attempt_keys) and identifier?(attempt["attempt_id"]) and
      attempt["phase"] in @attempt_phases and valid_disposition?(attempt) and
      optional_identifier?(attempt["reason_code"]) and
      optional_identifier?(attempt["candidate_id"]) and
      optional_identifier?(attempt["sealed_generation"]) and
      optional_identifier?(attempt["ref_receipt_id"]) and
      valid_collection?(attempt["executions"], "execution_id", &valid_execution?/1) and
      valid_collection?(attempt["checks"], "check_id", &valid_check?/1) and
      is_boolean(attempt["policy_empty_checks"]) and
      nonnegative_integer?(attempt["rejected_submissions"]) and
      (is_nil(attempt["review"]) or valid_review?(attempt["review"]))
  end

  # R4: "Attempt disposition | Set once on terminal". A disposition on a nonterminal
  # attempt, or a terminal attempt without one, is not a state the reducer may produce, so
  # it is not one the validator may accept either.
  defp valid_disposition?(%{"phase" => "terminal"} = attempt),
    do: attempt["disposition"] in @dispositions

  defp valid_disposition?(attempt), do: is_nil(attempt["disposition"])

  defp valid_execution?(execution) do
    exact_keys?(execution, @execution_keys) and identifier?(execution["execution_id"]) and
      execution["role"] in @roles and
      execution["lifecycle"] in @execution_lifecycles and
      (is_nil(execution["result"]) or execution["result"] in @execution_results) and
      optional_nonnegative_integer?(execution["sealed_sequence"])
  end

  defp valid_check?(check) do
    exact_keys?(check, @check_keys) and identifier?(check["check_id"]) and
      check["status"] in @check_statuses and optional_identifier?(check["reason_code"])
  end

  defp valid_review?(review) do
    plain_map?(review) and exact_keys?(review, @review_keys) and
      identifier?(review["candidate_id"]) and
      (is_nil(review["verdict"]) or review["verdict"] in @verdicts) and
      optional_identifier?(review["execution_id"])
  end

  defp plain_map?(value), do: is_map(value) and not is_struct(value)
  defp exact_keys?(map, keys), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp identifier?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp optional_identifier?(value), do: is_nil(value) or identifier?(value)
  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0
  defp optional_nonnegative_integer?(value), do: is_nil(value) or nonnegative_integer?(value)

  # ── The relational layer ───────────────────────────────────────────────────────────

  @doc """
  Every relational violation in `state`, as human-readable strings. `[]` means all hold.

  Distinct from `well_formed?/1`, which checks shapes: this asks whether the facts in an
  accepted state are mutually *coherent*. Both independent reviewers of subcommit 1 arrived
  at the need for it separately, from opposite directions, and it is the one thing none of
  the five existing evidence mechanisms could do.

  The demonstration is the stale-resume defect. The exhaustive search **reached the bad
  state** — a `developing` ticket whose attempt had already frozen its candidate, seven
  events from empty, three such states at depth 7. It did exactly its job. Nothing then
  called the state illegal, because every oracle in the suite answered a question about one
  transition — was this event admitted, or refused, and with which atom — and none answered
  whether the resulting facts cohere. `well_formed?/1` accepted the bad state without
  complaint, correctly, because nothing about it is malformed.

  This also catches a class the guard mutation sweep **structurally cannot**. The sweep
  neutralises conditions. A transition can have every guard perfectly exercised and still
  write the wrong phase, fail to clear stale metadata, overwrite evidence, or keep a pointer
  it should have dropped — all in the effect body, which no mutation of a guard will ever
  perturb.

  Returns all violations rather than the first: a transition that corrupts one relation
  often corrupts several, and the set is the diagnosis.

  ## What this is not

  It is not a proof. Asserting these over the states a bounded search reaches says they were
  not falsified within that bound, using a proposal set that is itself hand-written. The
  stronger form each wants is inductive — true of `new/0`, preserved by every accepted
  transition — at which point the search stops being the argument. Where an invariant has
  that argument available, it is written beside it.
  """
  @spec violations(map()) :: [String.t()]
  def violations(state) do
    state
    |> measure()
    |> Enum.flat_map(fn {_family, {_held?, violations}} -> violations end)
  end

  @doc """
  Per-family `{precondition_held?, violations}` for `state`.

  Rule 2's denominator, taken from the same code that produces the violations rather than
  from a second encoding of each precondition — which is the shape that let the proposer and
  the reducer be tuned against each other. `held?` is per state, not per ticket, so these
  numbers are directly comparable with EV-5's table over the bounded search.

  A family that is never `held?` across a whole run is reporting zero violations out of zero
  witnesses, which is rule 1's vacuous mechanism with a number attached. `receipt_custody`
  was exactly that at the search's own bound: 0 of 58,324.
  """
  @spec measure(map()) :: %{atom() => {boolean(), [String.t()]}}
  def measure(state) do
    state["tickets"]
    |> Kernel.||(%{})
    |> Enum.map(fn {_ticket_id, ticket} -> ticket_measure(ticket) end)
    |> Enum.reduce(Map.new(invariant_families(), &{&1, {false, []}}), fn measured, acc ->
      Map.merge(acc, measured, fn _family, {held?, vs}, {held2?, vs2} ->
        {held? or held2?, vs ++ vs2}
      end)
    end)
  end

  @doc """
  Whether every relation holds. `apply/2` does **not** call this — see the module doc.
  """
  @spec invariant?(map()) :: boolean()
  def invariant?(state), do: violations(state) == []

  defp ticket_measure(ticket) do
    id = ticket["ticket_id"]
    active = ticket["attempts"][ticket["active_attempt_id"]]

    %{
      phase_agreement_nil: phase_agreement_nil(id, ticket, active),
      phase_agreement_attempt: phase_agreement_attempt(id, ticket, active),
      resume_target: resume_target(id, ticket),
      candidate_custody: candidate_custody(id, ticket),
      receipt_custody: receipt_custody(id, ticket)
    }
  end

  # Each family returns `{precondition_held?, violations}`. Splitting the precondition from
  # the property is what makes a vacuous family visible: without it "0 violations" and "never
  # once evaluated" are the same number.
  defp scan(collection, precondition, violation) do
    Enum.reduce(collection || %{}, {false, []}, fn {key, value}, {held?, violations} ->
      if precondition.(value) do
        case violation.(key, value) do
          nil -> {true, violations}
          reasons -> {true, violations ++ List.wrap(reasons)}
        end
      else
        {held?, violations}
      end
    end)
  end

  @doc """
  The invariant families, in the order `violations/1` evaluates them.

  Public because the count is a proof obligation: the red controls assert one fixture per
  family and assert this list's length, so a family added without a control fails rather
  than joining silently.
  """
  @spec invariant_families() :: [atom()]
  def invariant_families,
    do: ~w(phase_agreement_nil phase_agreement_attempt resume_target candidate_custody
           receipt_custody)a

  # The invariant the stale-resume defect broke, and the one that makes three
  # `require_attempt_phase(~w(active))` sites redundant.
  #
  # Inductive argument, which is why this is more than an enumeration: `launch_planned` is
  # the only transition that sets a ticket to `developing`, and it does so with the attempt
  # `active`; `artifact_frozen`, `artifact_blocked` and the settlements all move the ticket
  # off `developing` in the same step that they move the attempt off `active`; and
  # `ticket_unblocked` returns the ticket to its stored resume target, which since the
  # honesty fix can only be a phase the ticket actually occupied while holding that attempt.
  @legal_pairs %{
    "developing" => ~w(active),
    "awaiting_review" => ~w(candidate_frozen checking awaiting_review),
    "reviewing" => ~w(reviewing),
    "ready_to_integrate" => ~w(ready_to_integrate),
    "integrating" => ~w(integrating)
  }

  # A working phase with no active attempt is a ticket nothing can move — UNLESS a cancel is
  # pending, which is R4's own exception and not a weakening of this invariant.
  #
  # `WORKFLOW-CONTRACT.md:490`: "nonterminal ticket; cancel requested | Set orthogonal
  # control, cancel pending/unissued effects, request owned interrupts; **hold
  # phase/evidence while issued effects reconcile**". So `apply_terminal_phase` returning the
  # ticket unchanged for `cancelled` (`kernel.ex:1042-1043`) is the row being obeyed: the
  # ticket holds its working phase until row :491's `cancellation_finalized` moves it.
  #
  # This clause shipped without the exception and was therefore wrong on every state it ever
  # judged. Measured at depth 7 from empty: **1,002 of 58,324 reachable states** held its
  # precondition and **all 1,002 violated it** — it was never once satisfied. All 1,002 have
  # `cancel_requested` set and every attempt terminal-cancelled; 0 have no pending cancel.
  # The claim "a ticket nothing can move" was falsified directly rather than argued, and the
  # denominators below are stated per set because they were measured over different ones.
  # Over the **190 at depth 6**: 0 are stuck, each admits at least 4 accepted successors, only
  # 4 admit `cancellation_finalized` immediately, the atom refusing it on the other 186 is
  # `:executions_not_closed` (`require_all_executions_closed/1`, `kernel.ex:1302`) — row :491's
  # "every owned session AND non-session claim terminal" — and of the 35 that cannot reach a
  # terminal ticket phase within 3 further events, 35 do within 5. Over the **1,002 at depth 7**:
  # 0 are stuck and each admits at least 4 accepted successors. The within-5 result is NOT
  # claimed for the 1,002; it was measured over the 190 only.
  #
  # `:cleanup_incomplete` is not part of this: EV-5's first pass read it out of the union of
  # every refusal from these states and attributed it to finalisation, but it comes from
  # `launch_planned` (`require_cleanup_complete/1`, `kernel.ex:1691`). Corrected by review.
  #
  # The precondition is a working phase with no active attempt. The cancel is part of the
  # PROPERTY, not the precondition, which is why EV-5's 1,002-of-1,002 and this clause's
  # current 0 violations share one denominator rather than the exception silently shrinking
  # it. An exception written into the precondition would have hidden its own effect.
  defp phase_agreement_nil(id, ticket, nil) do
    if ticket["phase"] in Map.keys(@legal_pairs) do
      if ticket["cancel_requested"],
        do: {true, []},
        else:
          {true,
           ["#{id}: ticket is #{ticket["phase"]} with no active attempt and no pending cancel"]}
    else
      {false, []}
    end
  end

  defp phase_agreement_nil(_id, _ticket, _attempt), do: {false, []}

  defp phase_agreement_attempt(_id, _ticket, nil), do: {false, []}

  defp phase_agreement_attempt(id, ticket, attempt) do
    case Map.fetch(@legal_pairs, ticket["phase"]) do
      {:ok, legal} ->
        if attempt["phase"] in legal,
          do: {true, []},
          else:
            {true,
             [
               "#{id}: ticket #{ticket["phase"]} with attempt #{attempt["phase"]} " <>
                 "(legal: #{Enum.join(legal, ", ")})"
             ]}

      :error ->
        {false, []}
    end
  end

  # `blocked` must hold a target it can resume to. The converse — that no other phase may
  # hold one — is deliberately NOT asserted, and the reason is worth more than the check.
  #
  # `artifact_frozen` advances the ticket to `awaiting_review` and leaves the `developing`
  # target that `launch_settled` stored. That residue is real, and it is half of what
  # produced the livelock: before the honesty guard was scoped by phase, a block could name
  # the stale value and the unblock would act on it. The fix chosen by both reviewers was
  # the single guard, because clearing the target at every advancing transition is N edits
  # over a vocabulary and partial generalisation across a vocabulary is the defect shape
  # this subcommit has now produced six times.
  #
  # So the stale value still exists and is now inert. Asserting it away here would be this
  # oracle inventing an obligation neither the contract nor the review states, and would
  # fail against the kernel as it stands. Clearing on advance is the stronger fix and is
  # recorded for review rather than smuggled in as an invariant.
  defp resume_target(id, ticket) do
    cond do
      ticket["phase"] != "blocked" -> {false, []}
      is_nil(ticket["resume_phase"]) -> {true, ["#{id}: blocked with no resume target"]}
      true -> {true, []}
    end
  end

  # R4 makes a frozen candidate immutable and retained. An attempt that has one may not go
  # back to a phase that would produce another.
  defp candidate_custody(id, ticket) do
    scan(
      ticket["attempts"],
      &(not is_nil(&1["candidate_id"])),
      fn attempt_id, attempt ->
        if attempt["phase"] == "active",
          do: "#{id}/#{attempt_id}: holds candidate #{attempt["candidate_id"]} while active"
      end
    )
  end

  # R4's integration row: "Exit notifications cannot overwrite this." A ref receipt decides
  # the disposition, so an attempt holding one may not be terminal as anything else.
  #
  # `cancelled` was licensed here and should not have been, which the review of EV-5 caught:
  # `require_receipt_for_integration/2` (`kernel.ex:1531-1535`) refuses **every** non-integrated
  # settlement of a receipt-holding attempt with `:ref_receipt_admits_only_integrated`, and
  # `kernel_test.exs:841-855` pins that atom. Contract row :491 agrees — "If integration
  # occurred: integrated and `cancel_finalized(after_integration)`" — so a cancel that races an
  # integration ends `integrated`, never `cancelled`. So the allowance was an oracle hole
  # permitting a state the kernel forbids, not the contract's own exception. EV-5's first pass
  # cited it as corroboration for the cancel exception in `phase_agreement/3`; that citation was
  # wrong and is withdrawn. The exception there stands on row :490 alone, which is enough.
  #
  # **Unwitnessed** (rule 3): 0 of 58,324 states at depth 7 hold this clause's precondition, so
  # neither the old form nor this one has ever been exercised by the exhaustive search. A ref
  # receipt sits roughly a dozen events from empty. The kernel guard and its unit test are what
  # currently carry this row; this clause is the relational statement of it, not its evidence.
  defp receipt_custody(id, ticket) do
    scan(
      ticket["attempts"],
      &(is_binary(&1["ref_receipt_id"]) and &1["phase"] == "terminal"),
      fn attempt_id, attempt ->
        if attempt["disposition"] != "integrated",
          do: "#{id}/#{attempt_id}: holds a ref receipt but settled #{attempt["disposition"]}"
      end
    )
  end

  # `terminal_custody` used to live here: "a terminal attempt carries a disposition and is
  # not the active one". It is deleted rather than kept, and the measurement is the reason.
  #
  # Both halves are refused by `well_formed?/1` before any oracle sees the state —
  # "terminal with no disposition" by `valid_disposition?/1` and "terminal but still active"
  # by `valid_attempt_order?/1`'s last conjunct. Enumerated, not argued: over the 3,358
  # terminal attempts reachable at depth 6, corrupted each way, the clause fired on all
  # 6,716 and the validator accepted **0** of them; and 0 reachable states both violate it
  # and pass the validator. So it could never have the failing fixture rule 1 requires, and
  # it was reporting 0 violations out of 6,716 preconditioned states by construction rather
  # than by the kernel being right. That is a worse vacuity than `receipt_custody`'s, which
  # at least has no witnesses to mislead with.
  #
  # This corrects a comment written earlier in the same change, which called the duplication
  # deliberate and claimed deleting either side would lose something. It would not: the
  # oracle half can only fire where the validator already refuses. Rule 4, and the EV-5
  # precedent — a correct, green duplicate is exactly what makes a dead encoding look
  # corroborated.
end
