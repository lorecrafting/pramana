defmodule PramanaWeb.CheckAdmissionLiveTest do
  use PramanaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PramanaWeb.CheckAdmission
  alias PramanaWeb.CheckLive

  setup do
    previous = Application.fetch_env(:pramana_web, CheckLive)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pramana_web, CheckLive, value)
        :error -> Application.delete_env(:pramana_web, CheckLive)
      end
    end)
  end

  test "reader saturation starts no verifier and produces no evidence verdict", %{conn: conn} do
    admission = start_admission(1)
    {:ok, permit} = CheckAdmission.acquire(admission)
    parent = self()

    Application.put_env(:pramana_web, CheckLive,
      timeout_ms: 5_000,
      admission: admission,
      verify: fn _ -> send(parent, :unexpected_verification) end,
      repair: fn _ -> send(parent, :unexpected_repair) end
    )

    {:ok, view, _} = live(conn, ~p"/check")
    view |> form("#report-check-form", report: "busy") |> render_submit()
    render_async(view, 3_000)

    assert has_element?(
             view,
             ~s(#check-execution[data-state="busy"]),
             "Verification did not start and no verdict was produced"
           )

    refute has_element?(view, "#verification-result")
    refute_received :unexpected_verification
    refute_received :unexpected_repair

    CheckAdmission.release(permit)
    assert eventually(fn -> CheckAdmission.stats(admission).active == 0 end)
  end

  defp start_admission(max_active) do
    permit_supervisor = unique_name(:permits)
    admission = unique_name(:admission)

    start_supervised!(
      Supervisor.child_spec(
        {DynamicSupervisor, strategy: :one_for_one, name: permit_supervisor},
        id: make_ref(),
        restart: :temporary
      )
    )

    start_supervised!(
      Supervisor.child_spec(
        {CheckAdmission,
         name: admission, permit_supervisor: permit_supervisor, max_active: max_active},
        id: make_ref()
      )
    )

    admission
  end

  defp unique_name(tag), do: {:global, {__MODULE__, tag, make_ref()}}

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
