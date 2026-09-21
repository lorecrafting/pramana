defmodule PramanaFoundry.Test.R4Rows do
  @moduledoc """
  The R4 and R4a transition rows, as data, parsed from the contract itself.

  Two independent reviews blocked this kernel with the same shape of finding: a guard
  refuses the reported counterexample while the row it claims to implement stays
  unexpressible. Hand-writing one guard per event from a prose table cannot distinguish
  those two things, because nothing in the process ever asks whether a row can be driven.

  So the rows become executable. This module holds only each row's **verbatim from-state
  cell** as its key; the text is parsed out of `docs/WORKFLOW-CONTRACT.md` at test time
  rather than copied here, so the inventory cannot silently drift from the contract. Edit a
  row in the contract and the lookup fails, naming the row.

  `PramanaFoundry.Workflow.R4CoverageTest` pairs each row with a scenario that drives it
  through the kernel and asserts its outcome. A row with no scenario is a failure, not a
  gap for a reviewer to find later.
  """

  @contract Path.join([__DIR__, "..", "..", "docs", "WORKFLOW-CONTRACT.md"])
  @external_resource @contract

  # Ordered as the contract orders them. The atom is a handle for scenarios to refer to;
  # the string is the authority and must match a row's from-cell exactly.
  @r4 [
    {:objective_steering, "Objective without admitted spec; broad steering"},
    {:admission, "draft; specific spec or valid PM create"},
    {:amend_or_park, "queued/blocked; PM amend/park"},
    {:launch,
     "queued; dependencies/resources/profile/reservation eligible; no pause/drain/cancel"},
    {:freeze_success, "developing; success artifact validates and freezes"},
    {:freeze_failure, "developing; freeze/import infrastructure failure before valid candidate"},
    {:developer_exit_after_freeze, "candidate_frozen; developer exit/timeout/abnormal exit"},
    {:no_valid_candidate,
     "developing; sealed stream has no valid candidate, verified exit/timeout"},
    {:blocked_result, "developing; valid blocked/partial result"},
    {:malformed_submission, "any open submission phase; malformed result"},
    {:checks_start, "candidate_frozen; developer closed, check capacity eligible"},
    {:checks_passed, "checking; all mandatory check receipts passed"},
    {:check_assertion_failed, "checking; actual check assertion fails"},
    {:check_infrastructure_failed, "checking; tool/infrastructure failure or timeout"},
    {:review_start, "awaiting_review; check receipts valid and reviewer capacity available"},
    {:verdict_approved, "reviewing; valid approved exact-candidate verdict"},
    {:verdict_correction, "reviewing; correction verdict"},
    {:verdict_rejected, "reviewing; rejected verdict"},
    {:reviewer_crash, "reviewing; sealed stream no valid verdict and reviewer crash/timeout"},
    {:integration_start, "ready_to_integrate; current base/evidence/policy valid"},
    {:base_moved, "ready_to_integrate/integrating; accepted base moved before issuance"},
    {:integration_success,
     "integrating; successful ref receipt and prior role/check workers closed"},
    {:integration_failure, "integrating; proved no ref change, command infrastructure failed"},
    {:resume, "blocked; explicit resume or recorded dependency/resource recovery"},
    {:reset, "exhausted; authenticated reset grants eligible units and explicitly resumes"},
    {:terminal_rejection,
     "integrated/rejected/cancelled; ordinary launch/result/completion command"},
    {:cancel_requested, "nonterminal ticket; cancel requested"},
    {:cancel_finalized,
     "cancel_requested; every owned session AND non-session claim terminal, cleanup reconciled"}
  ]

  @r4a [
    {:nonstart_developer, "Developer, active attempt before any valid result"},
    {:nonstart_reviewer, "Reviewer, frozen candidate awaiting review"},
    {:nonstart_pm, "PM planning execution"},
    {:nonstart_worker, "Check, freeze/import, build, integration or activation worker"}
  ]

  @doc "Every declared row handle, in contract order."
  def ids, do: Enum.map(@r4, &elem(&1, 0)) ++ Enum.map(@r4a, &elem(&1, 0))

  def r4_ids, do: Enum.map(@r4, &elem(&1, 0))
  def r4a_ids, do: Enum.map(@r4a, &elem(&1, 0))

  @doc "The from-state cell this handle claims, as declared here."
  def declared_from(id) do
    case List.keyfind(@r4, id, 0) || List.keyfind(@r4a, id, 0) do
      {^id, from} -> from
      nil -> nil
    end
  end

  # The contract holds many two-column tables - entity states, reservation transitions,
  # R1 ordering. Only these two are transition rows, identified by their header cell.
  @r4_header "From-state / input / guard"
  @r4a_header "Domain owner when launch settles `non_started`"

  @doc """
  The rows actually present in the contract, as `{from, outcome}` pairs.

  Only R4's transition table and R4a's domain-owner table are read, located by their
  header cells so a table added elsewhere in the contract cannot silently join them.
  """
  def contract_rows do
    @contract
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&cells/1)
    |> Enum.reduce({false, []}, &collect/2)
    |> elem(1)
    |> Enum.reverse()
  end

  defp collect([header, _], {_inside, rows}) when header in [@r4_header, @r4a_header],
    do: {true, rows}

  defp collect([from, outcome], {true, rows}) do
    cond do
      String.starts_with?(from, "---") -> {true, rows}
      from == "" -> {true, rows}
      true -> {true, [{from, outcome} | rows]}
    end
  end

  defp collect(_line, {_inside, rows}), do: {false, rows}

  defp cells(line) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, "|") do
      trimmed |> String.trim("|") |> String.split("|") |> Enum.map(&String.trim/1)
    else
      [nil]
    end
  end

  @doc "The outcome cell the contract states for this handle, or nil if the row is gone."
  def outcome(id) do
    from = declared_from(id)

    case Enum.find(contract_rows(), fn {f, _} -> f == from end) do
      {_, outcome} -> outcome
      nil -> nil
    end
  end
end
