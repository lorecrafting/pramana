defmodule PramanaWeb.ReviewerController do
  use PramanaWeb, :controller

  alias Pramana.Reviewer.Reviews
  alias Pramana.ReviewerAccess

  def login(conn, _params), do: login_page(conn, 200, "")

  def create_session(conn, %{"login_id" => login_id, "credential" => credential}) do
    case ReviewerAccess.authenticate(login_id, credential) do
      {:ok, account} ->
        conn
        |> configure_session(renew: true)
        |> put_session("reviewer_session", %{
          "account_id" => account.id,
          "epoch" => account.session_epoch,
          "expires_at" => System.system_time(:second) + ReviewerAccess.session_seconds()
        })
        |> redirect(to: "/")

      :error ->
        login_page(conn, 401, "Invalid credential or inactive access grant.")
    end
  end

  def create_session(conn, _params),
    do: login_page(conn, 401, "Invalid credential or inactive access grant.")

  def index(conn, _params) do
    account = conn.assigns.reviewer_account
    scopes = conn.assigns.reviewer_scopes

    items =
      Enum.map_join(scopes, "", fn scope ->
        "<li><code>#{escape(scope)}</code></li>"
      end)

    cases =
      with {:ok, artifact} <- Reviews.configured_scope(),
           {:ok, review_cases} <- Reviews.list_cases(artifact, scopes) do
        Enum.map_join(review_cases, "", fn item ->
          c = item.candidate

          "<li><a href=\"/reviews/#{item.id}\">#{escape(c.source_work_id)} → " <>
            "#{escape(c.target_work_id)}</a> (#{escape(c.assertion["review_reason"])})</li>"
        end)
      else
        _ -> "<li>No current review cases are available for your grant.</li>"
      end

    body = """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Source review</title></head>
    <body><main><h1>Source review</h1><p>Signed in as #{escape(account.display_name)}.</p>
    <p>Your permitted pilot scopes:</p><ul>#{items}</ul>
    <h2>Links needing review</h2><ul>#{cases}</ul>
    <form method="post" action="/logout"><input type="hidden" name="_csrf_token" value="#{csrf_token()}">
    <button type="submit">Sign out</button></form></main></body></html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(200, body)
  end

  def logout(conn, _params) do
    conn |> configure_session(drop: true) |> redirect(to: "/login")
  end

  defp login_page(conn, status, message) do
    body = """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Reviewer sign in</title></head>
    <body><main><h1>Reviewer sign in</h1><p role="alert">#{escape(message)}</p>
    <form method="post" action="/login"><input type="hidden" name="_csrf_token" value="#{csrf_token()}">
    <label>Login ID <input name="login_id" required autocomplete="username"></label>
    <label>Credential <input name="credential" type="password" required autocomplete="current-password"></label>
    <button type="submit">Sign in</button></form></main></body></html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(status, body)
  end

  defp csrf_token, do: Plug.CSRFProtection.get_csrf_token()
  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
