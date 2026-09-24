defmodule PramanaWeb.MCP.ReportAdmissionTest do
  use Pramana.DataCase, async: false

  import Plug.Conn

  alias Anubis.Server.Registry
  alias Anubis.Server.Supervisor, as: MCPSupervisor
  alias Anubis.Server.Transport.StreamableHTTP.Plug, as: MCPPlug
  alias PramanaWeb.CheckAdmission
  alias PramanaWeb.MCP.Server
  alias PramanaWeb.MCP.Tools.VerifyReport

  setup do
    previous = Application.fetch_env(:pramana_web, VerifyReport)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pramana_web, VerifyReport, value)
        :error -> Application.delete_env(:pramana_web, VerifyReport)
      end
    end)

    Application.delete_env(:pramana_web, VerifyReport)
    start_supervised!({Server, transport: {:streamable_http, start: true}})
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
          "clientInfo" => %{"name" => "report-admission-test", "version" => "1"}
        }
      })

    assert init.status == 200
    [session_id] = get_resp_header(init, "mcp-session-id")
    %{registry_mod: registry_mod} = MCPSupervisor.get_session_config(Server)
    {:ok, session} = registry_mod.lookup_session(Registry.registry_name(Server), session_id)

    initialized =
      post(opts, session_id, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert initialized.status == 202
    _ = :sys.get_state(session)
    %{calls: calls, opts: opts, session_id: session_id, session: session}
  end

  test "real MCP transport refuses full report-check capacity without inventing a verdict", ctx do
    admission = start_admission(1)
    {:ok, permit} = CheckAdmission.acquire(admission)
    parent = self()

    Application.put_env(:pramana_web, VerifyReport,
      admission: admission,
      verify: fn _ -> send(parent, :unexpected_verification) end,
      repair: fn _ -> send(parent, :unexpected_repair) end
    )

    wire = ctx |> call_async("report") |> Task.await(5_000)
    assert wire["result"]["isError"] == true
    payload = payload(wire)
    assert payload["error"]["reason"] == "report_check_busy"
    refute Map.has_key?(payload, "status")
    refute Map.has_key?(payload, "ok?")
    refute_received :unexpected_verification
    refute_received :unexpected_repair
    assert_session_usable(ctx)

    CheckAdmission.release(permit)
    assert eventually(fn -> CheckAdmission.stats(admission).active == 0 end)
  end

  defp start_admission(max_active) do
    permit_supervisor = unique_name(:permits)
    admission = unique_name(:admission)

    start_supervised!(
      Supervisor.child_spec(
        {DynamicSupervisor, strategy: :one_for_one, name: permit_supervisor},
        id: make_ref()
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

  defp call_async(ctx, markdown) do
    Task.Supervisor.async_nolink(ctx.calls, fn ->
      response =
        post(ctx.opts, ctx.session_id, %{
          "jsonrpc" => "2.0",
          "id" => 2,
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
