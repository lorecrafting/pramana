defmodule PramanaWeb.CheckAdmissionSmokeTest do
  use ExUnit.Case, async: true

  alias PramanaWeb.CheckAdmission

  test "released permit frees capacity" do
    permit_supervisor = {:global, {__MODULE__, :permits, make_ref()}}
    admission = {:global, {__MODULE__, :admission, make_ref()}}

    start_supervised!(
      Supervisor.child_spec(
        {DynamicSupervisor, strategy: :one_for_one, name: permit_supervisor},
        id: make_ref()
      )
    )

    start_supervised!(
      Supervisor.child_spec(
        {CheckAdmission, name: admission, permit_supervisor: permit_supervisor, max_active: 1},
        id: make_ref()
      )
    )

    assert {:ok, permit} = CheckAdmission.acquire(admission)
    assert CheckAdmission.acquire(admission) == {:error, :busy}
    assert :ok = CheckAdmission.release(permit)
  end
end
