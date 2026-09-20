defmodule PramanaFoundry.Workflow.Kernel.State do
  @moduledoc """
  Versioned, pure domain state for the FR-08B workflow reducer.

  Root authority is deliberately absent. The maps under `authority_bindings` contain
  identifiers and revisions only; policy, control, claim, receipt and ledger truth
  remains owned by the protected store.
  """

  @spec new() :: map()
  def new do
    %{
      "schema_version" => 1,
      "control" => %{
        "paused" => false,
        "draining" => false,
        "stop_status" => "running",
        "generation" => 0
      },
      "objectives" => %{},
      "tickets" => %{},
      "pm" => %{},
      "last_event_id" => nil
    }
  end

  @spec valid?(term()) :: boolean()
  def valid?(%{
        "schema_version" => 1,
        "control" => control,
        "objectives" => objectives,
        "tickets" => tickets,
        "pm" => pm,
        "last_event_id" => last_event_id
      })
      when is_map(control) and is_map(objectives) and is_map(tickets) and is_map(pm) and
             (is_binary(last_event_id) or is_nil(last_event_id)) do
    Map.keys(control) |> Enum.sort() ==
      ~w(draining generation paused stop_status) and
      is_boolean(control["paused"]) and is_boolean(control["draining"]) and
      control["stop_status"] in ~w(running stop_requested stop_blocked stop_completed) and
      is_integer(control["generation"]) and control["generation"] >= 0
  end

  def valid?(_state), do: false
end
