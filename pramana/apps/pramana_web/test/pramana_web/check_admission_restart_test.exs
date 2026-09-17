defmodule PramanaWeb.CheckAdmissionRestartTest do
  use ExUnit.Case, async: true

  alias PramanaWeb.CheckAdmission

  test "admission restart does not duplicate capacity" do
    permit_supervisor = {:global, {__MODULE__, :permits, make_ref()}}
    admission = {:global, {__MODULE__, :admission, make_ref()}}

    start_supervised!(
      Supervisor.child_spec(
        {DynamicSupervisor, strategy: :one_for_one, name: permit_supervisor},
        id: make_ref()
      )
    )

    server =
      start_supervised!(
        Supervisor.child_spec(
          {CheckAdmission, name: admission, permit_supervisor: permit_supervisor, max_active: 1},
          id: make_ref()
        )
      )

    assert {:ok, permit} = CheckAdmission.acquire(admission)
    Process.exit(server, :kill)
    assert eventually(fn -> CheckAdmission.stats(admission).active == 1 end)
    assert CheckAdmission.acquire(admission) == {:error, :busy}
    CheckAdmission.release(permit)
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end
end
