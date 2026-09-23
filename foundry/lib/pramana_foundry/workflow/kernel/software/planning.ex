defmodule PramanaFoundry.Workflow.Kernel.Software.Planning do
  @moduledoc """
  Software workflow: the objective and its PM planning - proposals and PM launches.
  """

  import PramanaFoundry.Workflow.Kernel.Executions, only: [consume_infrastructure_ordinal: 2]
  alias PramanaFoundry.Workflow.Kernel.State

  # R4: "Objective without admitted spec; broad steering".
  def do_transition("objective_created", :absent, event, _state) do
    payload = event["payload"]

    {:ok,
     %{
       "objective_id" => payload["objective_id"],
       "planning_owner_id" => payload["planning_owner_id"],
       "proposals" => %{},
       "infrastructure" => State.infrastructure(State.objective_roles())
     }}
  end

  # R4: "PM proposal is evidence, not authority" — recorded, never admitting a ticket.
  def do_transition("pm_proposal_recorded", objective, event, _state) do
    payload = event["payload"]

    if Map.has_key?(objective["proposals"], payload["proposal_id"]) do
      {:error, :duplicate_proposal}
    else
      proposal = %{"proposal_id" => payload["proposal_id"], "operation" => payload["operation"]}
      {:ok, put_in(objective, ["proposals", payload["proposal_id"]], proposal)}
    end
  end

  # R4a PM planning row. The planning owner is kept and no proposal is inferred; the
  # objective carries no phase to move.
  def do_transition(type, objective, _event, _state)
      when type == "pm_launch_planned",
      do: {:ok, objective}

  # R4a's PM row: "Below the PM limit, return to its PM queue; at the limit or without
  # current allocation, block as pm_launch_infrastructure or pm_budget." The limit is the
  # objective's own, which is why the objective carries infrastructure at all.
  def do_transition("pm_launch_settled", objective, _event, _state),
    do: {:ok, consume_infrastructure_ordinal(objective, "pm")}
end
