defmodule PramanaFoundry.Checks.AdoptionTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Checks.Adoption
  alias PramanaFoundry.Effects.ProcessGroup

  defp base(overrides) do
    Map.merge(
      %{
        recorded_identity: nil,
        completion: nil,
        deadline_epoch: nil,
        cancellation_requested?: false,
        stop_intent_checkpointed?: false
      },
      overrides
    )
  end

  test "recognizes a surviving check when its current process identity still matches" do
    {:ok, self_identity} = ProcessGroup.identity(System.pid() |> String.to_integer())

    assert {:adopted, ^self_identity} =
             Adoption.reconcile(base(%{recorded_identity: self_identity}))
  end

  test "a recorded identity whose pid no longer exists is :uncertain, never silently rerun" do
    recorded = %{
      pid: 99_999_999,
      parent_pid: 1,
      process_group_id: 99_999_999,
      started_at: "a",
      command: "x"
    }

    assert Adoption.reconcile(base(%{recorded_identity: recorded})) == :uncertain
  end

  test "a completed record with a deadline still exceeded resolves to :timeout on restart, not success" do
    completion = %{"returncode" => 0, "completed_at" => 250.0}

    recorded = %{
      pid: 99_999_999,
      parent_pid: 1,
      process_group_id: 99_999_999,
      started_at: "a",
      command: "x"
    }

    result =
      Adoption.reconcile(
        base(%{recorded_identity: recorded, completion: completion, deadline_epoch: 200.0})
      )

    assert result == :timeout
  end
end
