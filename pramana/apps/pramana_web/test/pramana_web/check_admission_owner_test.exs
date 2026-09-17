defmodule PramanaWeb.CheckAdmissionOwnerTest do
  use ExUnit.Case, async: true

  alias PramanaWeb.CheckAdmission

  test "owner exit removes permit without explicit release" do
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

    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:permit, CheckAdmission.acquire(admission)})
        Process.sleep(:infinity)
      end)

    assert_receive {:permit, {:ok, _permit}}
    Process.exit(owner, :kill)

    assert eventually(fn -> CheckAdmission.stats(admission).active == 0 end)
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
