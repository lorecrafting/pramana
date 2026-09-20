defmodule PramanaWeb.CheckLifecycleTest do
  use PramanaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

  test "running checks stay responsive and reject submissions that bypass the disabled button", %{
    conn: conn
  } do
    parent = self()
    configure(verify: blocking_verifier(parent))
    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "first report")
    assert_receive {:started, "first report", worker}
    worker_ref = Process.monitor(worker)

    assert has_element?(view, ~s(#check-execution[data-state="verifying"]))
    assert has_element?(view, "#check-submit[disabled]")
    assert has_element?(view, "#check-cancel")
    refute has_element?(view, "#verification-result")
    render_submit(view, "check", %{"report" => "second report"})
    render_submit(view, "check", %{"report" => nil})
    refute_received {:started, "second report", _}
    assert has_element?(view, "textarea", "first report")

    view |> element("#check-cancel") |> render_click()
    render_async(view, 3_000)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}
    assert has_element?(view, ~s(#check-execution[data-state="cancelled"]), "No verdict")
    refute has_element?(view, "#verification-result")
    refute has_element?(view, "#check-submit[disabled]")
  end

  test "a new report clears the previous verdict and repair before it finishes", %{conn: conn} do
    parent = self()

    verify = fn report ->
      if report == "first", do: verdict(:verified), else: blocking_verifier(parent).(report)
    end

    configure(verify: verify)
    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "first")
    render_async(view, 3_000)
    assert has_element?(view, ~s(#verification-result[data-status="verified"]))
    assert render(view) =~ "REPAIR SENTINEL"

    submit(view, "second")
    assert_receive {:started, "second", _worker}
    refute has_element?(view, "#verification-result")
    refute render(view) =~ "REPAIR SENTINEL"
    render_click(view, "cancel")
    render_async(view, 3_000)
  end

  test "deadline expiry stops the worker and never creates an evidence verdict", %{conn: conn} do
    parent = self()
    configure(verify: blocking_verifier(parent), timeout_ms: 1_000)
    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "slow")
    assert_receive {:started, "slow", worker}
    worker_ref = Process.monitor(worker)
    render_async(view, 3_000)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}

    assert has_element?(
             view,
             ~s(#check-execution[data-state="timed_out"]),
             "neither a pass nor a refutation"
           )

    refute has_element?(view, "#verification-result")
  end

  test "repair timeout preserves a real failure verdict and discards partial repairs", %{
    conn: conn
  } do
    parent = self()

    configure(
      verify: fn _ -> verdict(:failed) end,
      repair: blocking_verifier(parent),
      timeout_ms: 1_000
    )

    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "repair slow")
    assert_receive {:started, "repair slow", worker}
    worker_ref = Process.monitor(worker)
    assert has_element?(view, ~s(#verification-result[data-status="failed"]))
    render_async(view, 3_000)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}

    assert has_element?(
             view,
             ~s(#check-execution[data-state="timed_out"]),
             "verdict is unchanged"
           )

    assert has_element?(view, ~s(#verification-result[data-status="failed"]))
    refute render(view) =~ "REPAIR SENTINEL"
  end

  test "repair cancellation retains the completed verdict but never a partial repair", %{
    conn: conn
  } do
    configure(verify: fn _ -> verdict(:verified) end, repair: blocking_verifier(self()))
    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "repair cancellation")
    assert_receive {:started, "repair cancellation", worker}
    worker_ref = Process.monitor(worker)
    assert has_element?(view, ~s(#verification-result[data-status="verified"]))
    render_click(view, "cancel")
    render_async(view, 3_000)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}

    assert has_element?(
             view,
             ~s(#check-execution[data-state="cancelled"]),
             "verdict is unchanged"
           )

    assert has_element?(view, ~s(#verification-result[data-status="verified"]))
    refute render(view) =~ "REPAIR SENTINEL"
  end

  test "a cancelling page cannot admit work or resurrect an unobserved completion", %{conn: conn} do
    configure(verify: blocking_verifier(self()))
    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "first")
    assert_receive {:started, "first", worker}
    socket = :sys.get_state(view.pid).socket
    id = socket.assigns.check_run
    # Model the cancellation/cleanup interval without relying on a fast worker's
    # scheduling. This exercises the same callbacks that consume late completion.
    stopping = Phoenix.Component.assign(socket, check_state: :cancelling)
    assert {:noreply, ^stopping} = CheckLive.handle_event("check", %{"report" => "new"}, stopping)

    assert {:noreply, ^stopping} =
             CheckLive.handle_info({:check_verified, id, verdict(:verified)}, stopping)

    completed = %{execution: :completed, result: verdict(:verified), repair: repair()}
    {:noreply, cancelled} = CheckLive.handle_async({:check, id}, {:ok, completed}, stopping)
    assert cancelled.assigns.check_state == :cancelled
    assert cancelled.assigns.result == nil
    assert cancelled.assigns.repair == nil

    # A verdict already displayed before cancellation is retained instead.
    observed = Phoenix.Component.assign(stopping, result: verdict(:failed))
    {:noreply, retained} = CheckLive.handle_async({:check, id}, {:ok, completed}, observed)
    assert retained.assigns.result == verdict(:failed)
    assert retained.assigns.repair == nil

    worker_ref = Process.monitor(worker)
    render_click(view, "cancel")
    render_async(view, 3_000)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}
  end

  test "verification and repair exceptions recover without leaking exception data", %{conn: conn} do
    configure(verify: fn _ -> raise "SECRET REPORT" end)
    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "test")
    html = render_async(view, 3_000)
    assert has_element?(view, ~s(#check-execution[data-state="error"]), "No verification verdict")
    refute html =~ "SECRET REPORT"
    refute has_element?(view, "#verification-result")

    configure(verify: fn _ -> verdict(:verified) end, repair: fn _ -> raise "SECRET REPORT" end)
    {:ok, other, _} = live(build_conn(), ~p"/check")
    submit(other, "test")
    html = render_async(other, 3_000)
    assert has_element?(other, ~s(#check-execution[data-state="error"]), "verdict is unchanged")
    assert has_element?(other, ~s(#verification-result[data-status="verified"]))
    refute html =~ "SECRET REPORT"
  end

  test "leaving the LiveView kills its owned blocked worker", %{conn: conn} do
    parent = self()
    configure(verify: blocking_verifier(parent))
    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "leaving")
    assert_receive {:started, "leaving", worker}
    worker_ref = Process.monitor(worker)
    GenServer.stop(view.pid, :normal)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 3_000
  end

  test "obsolete progress and completion cannot overwrite the next report", %{conn: conn} do
    parent = self()
    configure(verify: blocking_verifier(parent))
    {:ok, view, _} = live(conn, ~p"/check")
    submit(view, "old")
    assert_receive {:started, "old", _}
    old = :sys.get_state(view.pid).socket.assigns.check_run
    render_click(view, "cancel")
    render_async(view, 3_000)

    submit(view, "new")
    assert_receive {:started, "new", worker}
    send(view.pid, {:check_verified, old, verdict(:verified)})
    assert has_element?(view, ~s(#check-execution[data-state="verifying"]))
    refute has_element?(view, "#verification-result")

    # Exercise the callback's request-identity boundary independently of Phoenix's
    # own pruning of obsolete async references.
    socket = :sys.get_state(view.pid).socket

    {:noreply, unchanged} =
      CheckLive.handle_async(
        {:check, old},
        {:ok, %{execution: :completed, result: verdict(:verified), repair: nil}},
        socket
      )

    assert unchanged == socket
    send(worker, :continue)
    render_async(view, 3_000)
    assert has_element?(view, ~s(#verification-result[data-status="incomplete"]))
  end

  test "blank oversized and malformed replacements clear old output without launching work", %{
    conn: conn
  } do
    parent = self()

    verify = fn report ->
      send(parent, {:invoked, report})
      verdict(:verified)
    end

    configure(verify: verify)
    {:ok, view, _} = live(conn, ~p"/check")

    for refused <- ["", "   ", String.duplicate("a", 200_001), nil] do
      render_submit(view, "check", %{"report" => "valid"})
      render_async(view, 3_000)
      assert_receive {:invoked, "valid"}
      assert has_element?(view, "#verification-result")
      render_submit(view, "check", %{"report" => refused})
      refute has_element?(view, "#verification-result")
      refute render(view) =~ "REPAIR SENTINEL"
      refute_received {:invoked, ^refused}
    end
  end

  defp configure(opts) do
    defaults = [
      timeout_ms: 5_000,
      verify: fn _ -> verdict(:incomplete) end,
      repair: fn _ -> repair() end
    ]

    Application.put_env(:pramana_web, CheckLive, Keyword.merge(defaults, opts))
  end

  defp submit(view, report),
    do: view |> form("#report-check-form", report: report) |> render_submit()

  defp blocking_verifier(parent) do
    fn report ->
      Process.flag(:trap_exit, true)
      send(parent, {:started, report, self()})

      receive do
        :continue -> verdict(:incomplete)
      end
    end
  end

  defp verdict(status) do
    %{
      status: status,
      summary: "VERDICT #{status}",
      citations: %{
        checked: 0,
        verified_quotes: 0,
        existence_only: 0,
        translations: 0,
        findings: []
      },
      foreign: [],
      replays: [],
      malformed: [],
      skipped: 0,
      unsourced_figures: [],
      checked_identity: %{bake_id: nil, release_id: nil}
    }
  end

  defp repair do
    %{
      original: "original",
      text: "REPAIR SENTINEL",
      actions: [
        %{state: :flagged, urn: "urn", source_offset: 0, reason: nil, detail: "REPAIR SENTINEL"}
      ],
      counts: %{flagged: 1},
      repaired?: false
    }
  end
end
