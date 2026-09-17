defmodule PramanaWeb.MCP.ReportExecutionTest do
  use Pramana.DataCase, async: false

  import Plug.Conn

  alias Anubis.Server.Registry
  alias Anubis.Server.Supervisor, as: MCPSupervisor
  alias Anubis.Server.Transport.StreamableHTTP.Plug, as: MCPPlug
  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias Pramana.Report
  alias PramanaWeb.MCP.ReplayExecutor
  alias PramanaWeb.MCP.Server
  alias PramanaWeb.MCP.Tools.VerifyReport

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt><title level="m">Fixture</title>
  <author>姚秦 鳩摩羅什譯</author></titleStmt></fileDesc></teiHeader>
  <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>慈悲</body></text></TEI>
  """

  setup do
    previous = Application.fetch_env(:pramana_web, VerifyReport)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pramana_web, VerifyReport, value)
        :error -> Application.delete_env(:pramana_web, VerifyReport)
      end
    end)

    Application.delete_env(:pramana_web, VerifyReport)
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T")
    calls = start_supervised!({Task.Supervisor, []})
    opts = MCPPlug.init(server: Server, request_timeout: 5_000)

    init =
      post(opts, nil, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-11-25",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "report-lifecycle-test", "version" => "1"}
        }
      })

    assert init.status == 200
    assert %{"result" => %{"protocolVersion" => "2025-11-25"}} = Jason.decode!(init.resp_body)
    [session_id] = get_resp_header(init, "mcp-session-id")
    {:ok, session} = Registry.lookup_session(Registry.registry_name(Server), session_id)

    on_exit(fn -> MCPSupervisor.stop_session(Server, Registry, session_id) end)

    initialized =
      post(opts, session_id, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert initialized.status == 202
    _ = :sys.get_state(session)
    %{calls: calls, opts: opts, session_id: session_id, session: session}
  end

  test "the MCP budget is finite and shorter than the transport wait" do
    assert VerifyReport.timeout_ms() == 25_000
    assert VerifyReport.timeout_ms(timeout_ms: 1) == 1
    assert_raise ArgumentError, fn -> VerifyReport.timeout_ms(timeot_ms: 1) end

    for invalid <- [0, -1, 25_001, 60_000, :infinity, nil, "1000"] do
      assert_raise ArgumentError, fn -> VerifyReport.timeout_ms(timeout_ms: invalid) end
    end
  end

  test "a blocked verifier times out, dies and leaves the same session usable", ctx do
    configure(timeout_ms: 1_000, verify: blocked(self()))
    task = call_async(ctx, report(1))
    assert_receive {:worker, worker}
    ref = Process.monitor(worker)
    wire = Task.await(task, 4_000)
    assert wire["result"]["isError"] == true
    payload = payload(wire)
    assert payload["error"]["reason"] == "report_check_timed_out"
    refute Map.has_key?(payload, "status")
    refute Map.has_key?(payload, "ok?")
    assert Map.has_key?(payload, "bake_id") and Map.has_key?(payload, "release_id")
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
    assert_session_usable(ctx)
  end

  test "normal real verification and repair retain their existing fields", ctx do
    wire = ctx |> call_async(report(1)) |> Task.await(5_000)
    assert wire["result"]["isError"] == false
    payload = payload(wire)
    assert payload["execution"] == "completed"
    assert payload["status"] == "verified" and payload["ok?"]
    assert payload["counts"]["verified_replays"] == 1
    assert is_map(payload["repair"])
    assert payload["replay"]["tool"] == "verify_report"
    assert_session_usable(ctx)
  end

  test "a repair exception cannot hide an actual failed assertion", ctx do
    configure(repair: fn _ -> raise "PRIVATE_REPAIR_EXCEPTION" end)
    wire = ctx |> call_async(report(999)) |> Task.await(5_000)
    assert wire["result"]["isError"] == false
    payload = payload(wire)
    assert payload["execution"] == "error"
    assert payload["status"] == "failed"
    refute payload["ok?"]
    assert payload["counts"]["replay_failures"] == 1
    assert payload["repair"] == nil
    assert payload["note"] =~ "repair failed"
    refute inspect(wire) =~ "PRIVATE_REPAIR_EXCEPTION"
    assert_session_usable(ctx)
  end

  test "a verifier exception is an execution error, not an evidence verdict", ctx do
    configure(verify: fn _ -> raise "PRIVATE_VERIFIER_EXCEPTION" end)
    wire = ctx |> call_async(report(1)) |> Task.await(5_000)
    assert wire["result"]["isError"] == true
    assert payload(wire)["error"]["reason"] == "report_check_failed"
    refute Map.has_key?(payload(wire), "status")
    refute inspect(wire) =~ "PRIVATE_VERIFIER_EXCEPTION"
    assert_session_usable(ctx)
  end

  test "repair timeout preserves both successful and failed completed verification", ctx do
    for {count, status} <- [{1, "verified"}, {999, "failed"}] do
      configure(timeout_ms: 1_000, repair: blocked(self()))
      task = call_async(ctx, report(count), count + 10)
      assert_receive {:worker, worker}
      ref = Process.monitor(worker)
      wire = Task.await(task, 4_000)
      payload = payload(wire)
      assert payload["status"] == status
      assert payload["ok?"] == (status == "verified")
      assert payload["execution"] == "timed_out" and payload["repair"] == nil
      assert payload["note"] =~ "shared execution budget"
      assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
    end

    assert_session_usable(ctx)
  end

  test "repair consumes the remaining deadline rather than starting a fresh budget", ctx do
    parent = self()

    verify = fn markdown ->
      result = Report.verify(markdown, executor: ReplayExecutor.executor())
      send(parent, {:verifying, self()})

      receive do
        :continue -> result
      end
    end

    configure(timeout_ms: 2_000, verify: verify, repair: blocked(parent))
    task = call_async(ctx, report(1))
    assert_receive {:verifying, worker}
    Process.send_after(worker, :continue, 1_200)
    assert_receive {:worker, ^worker}, 1_800
    # A fresh two-second repair budget misses this boundary. This is an injected
    # lifecycle fixture, not a corpus-performance measurement.
    wire = Task.await(task, 1_200)
    assert payload(wire)["status"] == "verified"
    assert payload(wire)["execution"] == "timed_out"
  end

  test "protocol cancellation during verification stops the owned worker", ctx do
    configure(timeout_ms: 4_000, verify: blocked(self()))
    task = call_async(ctx, report(1))
    assert_receive {:worker, worker}
    ref = Process.monitor(worker)

    cancelled =
      post(ctx.opts, ctx.session_id, %{
        "jsonrpc" => "2.0",
        "method" => "notifications/cancelled",
        "params" => %{"requestId" => 2, "reason" => "test cancellation"}
      })

    assert cancelled.status == 202
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}, 2_000
    assert %{"error" => %{}} = Task.await(task, 3_000)
    assert_session_usable(ctx)
  end

  test "protocol cancellation during repair cannot publish a late result", ctx do
    configure(timeout_ms: 4_000, repair: blocked(self()))
    task = call_async(ctx, report(999))
    assert_receive {:worker, worker}
    ref = Process.monitor(worker)

    post(ctx.opts, ctx.session_id, %{
      "jsonrpc" => "2.0",
      "method" => "notifications/cancelled",
      "params" => %{"requestId" => 2}
    })

    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}, 2_000
    assert %{"error" => %{}} = Task.await(task, 3_000)
    assert_session_usable(ctx)
  end

  test "deleting the real transport session cleans up report work", ctx do
    configure(timeout_ms: 4_000, verify: blocked(self()))
    task = call_async(ctx, report(1))
    assert_receive {:worker, worker}
    worker_ref = Process.monitor(worker)
    session_ref = Process.monitor(ctx.session)

    deleted =
      Plug.Test.conn(:delete, "/mcp")
      |> put_req_header("mcp-session-id", ctx.session_id)
      |> MCPPlug.call(ctx.opts)

    assert deleted.status == 200
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 2_000
    assert_receive {:DOWN, ^session_ref, :process, _, _}, 2_000
    assert %{"error" => %{}} = Task.await(task, 3_000)
  end

  defp configure(opts), do: Application.put_env(:pramana_web, VerifyReport, opts)

  defp blocked(parent) do
    fn _ ->
      Process.flag(:trap_exit, true)
      send(parent, {:worker, self()})

      receive do
        :never -> %{}
      end
    end
  end

  defp report(count) do
    "```pramana-replay\n" <>
      Jason.encode!(%{
        tool: "survey_corpus",
        arguments: %{query: "慈悲"},
        assert: %{total_segments: count}
      }) <> "\n```"
  end

  defp call_async(ctx, markdown, id \\ 2) do
    Task.Supervisor.async_nolink(ctx.calls, fn ->
      response =
        post(ctx.opts, ctx.session_id, %{
          "jsonrpc" => "2.0",
          "id" => id,
          "method" => "tools/call",
          "params" => %{"name" => "verify_report", "arguments" => %{"report" => markdown}}
        })

      assert response.status == 200
      Jason.decode!(response.resp_body)
    end)
  end

  defp post(opts, session_id, message) do
    conn =
      Plug.Test.conn(:post, "/mcp", Jason.encode!(message))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")

    conn = if session_id, do: put_req_header(conn, "mcp-session-id", session_id), else: conn
    MCPPlug.call(conn, opts)
  end

  defp payload(wire) do
    [%{"text" => text}] = wire["result"]["content"]
    Jason.decode!(text)
  end

  defp assert_session_usable(ctx) do
    response =
      post(ctx.opts, ctx.session_id, %{
        "jsonrpc" => "2.0",
        "id" => 9_999,
        "method" => "tools/list"
      })

    assert response.status == 200
    assert %{"id" => 9_999, "result" => %{"tools" => [_ | _]}} = Jason.decode!(response.resp_body)
    state = :sys.get_state(ctx.session)
    assert state.in_flight == nil
    assert :queue.is_empty(state.request_queue)
  end
end
