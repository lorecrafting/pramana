defmodule PramanaFoundry.Workflow.Kernel.Control do
  @moduledoc """
  The control entity (pause, drain, stop status) and the control refusals the
  `*_planned` handlers of every family call: paused, draining, pending cancel.
  """

  # R4 Control entity: orthogonal pause/drain flags and a stop status, never ticket phases.
  def do_transition("control_changed", control, event, _state) do
    payload = event["payload"]

    with :ok <- require_boolean(payload["paused"]),
         :ok <- require_boolean(payload["draining"]),
         :ok <- require_stop_status(payload["stop_status"]),
         :ok <- require_control_fact(payload["control"]) do
      {:ok,
       control
       |> Map.put("paused", payload["paused"])
       |> Map.put("draining", payload["draining"])
       |> Map.put("stop_status", payload["stop_status"])
       |> Map.put("control_id", payload["control"]["control_id"])
       |> Map.put("control_revision", payload["control"]["control_revision"])}
    end
  end

  # R4.27.o1: "cancel pending/unissued effects", and R4a: cancel "never retries". One rule
  # for every ticket-scoped `*_planned` - launch, check, build, review, integration - called
  # from each handler rather than copied into it (EVIDENCE-TOOLS rule 4). No `*_planned`
  # handler is exempt: settling, closing and finalising a cancelled ticket are all
  # `*_settled`/`*_closed`/`cancellation_finalized`, none of which plans an effect.
  # `pm_launch_planned` is objective-scoped and an objective carries no cancel.
  # `kernel_test.exs` derives the handler set from `Event.types/0` and fails on one this
  # misses.
  def require_no_pending_cancel(ticket),
    do: if(ticket["cancel_requested"], do: {:error, :cancel_pending}, else: :ok)

  # R4.04.f3 "no pause/drain". Developer issue only: under the approved B3 readings (Q2) pause
  # binds no other role in the reducer, and drain's closed list is "developer and PM
  # replacement launches"; PM is deferred. The flags are the reducer-owned control entity's -
  # the protected layer has no pause or drain.
  def require_not_paused(control),
    do: if(control["paused"], do: {:error, :control_paused}, else: :ok)

  def require_not_draining(control),
    do: if(control["draining"], do: {:error, :control_draining}, else: :ok)

  def require_boolean(value),
    do: if(is_boolean(value), do: :ok, else: {:error, :invalid_control_flag})

  defp require_stop_status(status) do
    if status in ~w(running stop_requested stop_blocked stop_completed),
      do: :ok,
      else: {:error, :invalid_stop_status}
  end

  # control_fact_v1 is a protected derivation. The kernel checks its shape and copies its
  # identity; it never invents one, and a plain caller map cannot stand in for it.
  defp require_control_fact(control) do
    if is_map(control) and not is_struct(control) and control["schema_version"] == 1 and
         is_binary(control["control_id"]) and control["control_id"] != "" and
         is_integer(control["control_revision"]) and control["control_revision"] >= 0,
       do: :ok,
       else: {:error, :invalid_control_fact}
  end
end
