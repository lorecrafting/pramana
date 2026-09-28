defmodule PramanaWeb.ReviewerEndpointTest do
  use Pramana.DataCase, async: false

  alias Pramana.ReviewerAccess
  alias PramanaWeb.ReviewerEndpoint

  @scope String.duplicate("b", 64)

  setup do
    start_supervised!(ReviewerEndpoint)
    :ok
  end

  test "private endpoint exposes sign-in but no reader, LiveView or MCP surface" do
    assert request(:get, "/login").status == 200
    assert request(:get, "/").status == 302
    assert request(:get, "/passage").status == 404
    assert request(:get, "/mcp").status == 404
    assert request(:get, "/live/websocket").status == 404
  end

  test "private page rechecks a signed session against the current grant" do
    assert {:ok, account, _credential} =
             ReviewerAccess.provision("reviewer.web", "silent principal", @scope, "operator-1")

    session = %{
      "account_id" => account.id,
      "epoch" => account.session_epoch,
      "expires_at" => System.system_time(:second) + 60
    }

    conn = request(:get, "/", session)
    assert conn.status == 200
    assert conn.resp_body =~ "silent principal"
    assert conn.resp_body =~ @scope

    assert :ok = ReviewerAccess.revoke_scope("reviewer.web", @scope, "operator-1")
    assert request(:get, "/", session).status == 302
    assert request(:get, "/", %{session | "expires_at" => 0}).status == 302
  end

  test "a provisioned credential opens a signed browser session" do
    assert {:ok, _account, credential} =
             ReviewerAccess.provision("reviewer.login", "silent principal", @scope, "operator-1")

    login = request(:get, "/login")
    [_, csrf] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, login.resp_body)

    post =
      Plug.Test.conn(
        :post,
        "/login",
        URI.encode_query(%{
          "_csrf_token" => csrf,
          "login_id" => "reviewer.login",
          "credential" => credential
        })
      )
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Test.recycle_cookies(login)
      |> ReviewerEndpoint.call([])

    assert post.status == 302

    dashboard =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.recycle_cookies(post)
      |> ReviewerEndpoint.call([])

    assert dashboard.status == 200
    assert dashboard.resp_body =~ "silent principal"
  end

  defp request(method, path, session \\ nil) do
    conn = Plug.Test.conn(method, path)

    conn =
      if session,
        do: Plug.Test.init_test_session(conn, %{"reviewer_session" => session}),
        else: conn

    ReviewerEndpoint.call(conn, [])
  end
end
