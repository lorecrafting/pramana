defmodule PramanaWeb.CheckAdmissionConfigTest do
  use ExUnit.Case, async: false

  alias PramanaWeb.CheckAdmission

  test "application admission configuration rejects unknown keys" do
    previous = Application.fetch_env(:pramana, CheckAdmission)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pramana, CheckAdmission, value)
        :error -> Application.delete_env(:pramana, CheckAdmission)
      end
    end)

    Application.put_env(:pramana, CheckAdmission, unknown: true)
    assert_raise ArgumentError, fn -> CheckAdmission.init([]) end
  end
end
