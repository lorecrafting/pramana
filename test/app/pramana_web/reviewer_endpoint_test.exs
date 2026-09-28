defmodule PramanaWeb.ReviewerEndpointTest do
  use Pramana.DataCase, async: false

  alias Pramana.Accounts
  alias Pramana.AccountsFixtures
  alias Pramana.ReviewerAccess
  alias PramanaWeb.ReviewerEndpoint
  import Swoosh.TestAssertions

  @scope String.duplicate("b", 64)

  setup do
    start_supervised!(ReviewerEndpoint)
    :ok
  end

  test "private endpoint exposes generated login but no reader, LiveView or MCP" do
    assert request(:get, "/users/log-in").status == 200
    assert request(:get, "/").status == 302
    assert request(:get, "/users/register").status == 404
    assert request(:get, "/passage").status == 404
    assert request(:get, "/mcp").status == 404
    assert request(:get, "/live/websocket").status == 404
  end

  test "private magic link confirms and signs in independently, then grant is rechecked" do
    user = AccountsFixtures.unconfirmed_user_fixture()
    {token, _stored} = AccountsFixtures.generate_user_magic_link_token(user)
    confirm = request(:get, "/users/log-in/#{token}")
    assert confirm.status == 200

    login =
      Plug.Test.conn(
        :post,
        "/users/log-in",
        URI.encode_query(%{
          "user[token]" => token,
          "_action" => "confirmed",
          "_csrf_token" => field(confirm.resp_body, "_csrf_token")
        })
      )
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Test.recycle_cookies(confirm)
      |> ReviewerEndpoint.call([])

    assert login.status == 302
    assert request(:get, "/", login).status == 403
    confirmed = Accounts.get_user!(user.id)
    refute is_nil(confirmed.confirmed_at)

    assert {:ok, _} = ReviewerAccess.grant_scope(user.email, @scope, "operator-1")
    home = request(:get, "/", login)
    assert home.status == 200
    assert home.resp_body =~ user.email
    assert home.resp_body =~ @scope

    assert :ok = ReviewerAccess.revoke_scope(user.email, @scope, "operator-1")
    assert request(:get, "/", login).status == 403
  end

  test "unconfirmed session and public session cannot enter private endpoint" do
    unconfirmed = AccountsFixtures.unconfirmed_user_fixture()
    token = Accounts.generate_user_session_token(unconfirmed)
    conn = Plug.Test.conn(:get, "/") |> Plug.Test.init_test_session(%{user_token: token})
    assert ReviewerEndpoint.call(conn, []).status == 302

    confirmed = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    assert {:ok, _} = ReviewerAccess.grant_scope(confirmed.email, @scope, "operator-1")
    public_page = PramanaWeb.Endpoint.call(Plug.Test.conn(:get, "/users/log-in"), [])

    public_session =
      Plug.Test.conn(
        :post,
        "/users/log-in",
        URI.encode_query(%{
          "user[email]" => confirmed.email,
          "user[password]" => AccountsFixtures.valid_user_password(),
          "_csrf_token" => field(public_page.resp_body, "_csrf_token")
        })
      )
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Test.recycle_cookies(public_page)
      |> PramanaWeb.Endpoint.call([])

    assert public_session.status == 302
    assert request(:get, "/", public_session).status == 302
  end

  test "private login sends a magic link back to the private origin" do
    user = AccountsFixtures.user_fixture()
    assert_email_sent()
    page = ReviewerEndpoint.call(Plug.Test.conn(:get, "https://review.example/users/log-in"), [])

    sent =
      Plug.Test.conn(
        :post,
        "https://review.example/users/log-in",
        URI.encode_query(%{
          "user[email]" => user.email,
          "_csrf_token" => field(page.resp_body, "_csrf_token")
        })
      )
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Test.recycle_cookies(page)
      |> ReviewerEndpoint.call([])

    assert sent.status == 302

    assert_email_sent(fn email ->
      email.text_body =~ "https://review.example/users/log-in/"
    end)
  end

  defp request(method, path, cookies_or_params \\ nil) do
    conn =
      case cookies_or_params do
        params when is_map(params) and not is_struct(params) ->
          Plug.Test.conn(method, path, params)

        _ ->
          Plug.Test.conn(method, path)
      end

    conn =
      if match?(%Plug.Conn{}, cookies_or_params),
        do: Plug.Test.recycle_cookies(conn, cookies_or_params),
        else: conn

    ReviewerEndpoint.call(conn, [])
  end

  defp field(body, name) do
    [tag] = Regex.run(~r/<input(?=[^>]*name="#{name}")[^>]*>/, body)
    [_, value] = Regex.run(~r/value="([^"]+)"/, tag)
    value
  end
end
