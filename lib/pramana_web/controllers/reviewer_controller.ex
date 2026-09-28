defmodule PramanaWeb.ReviewerController do
  use PramanaWeb, :controller

  alias Pramana.Reviewer.Reviews

  def index(conn, _params) do
    account = conn.assigns.current_scope.user
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
    <body><main><h1>Source review</h1><p>Signed in as #{escape(account.email)}.</p>
    <p>Your permitted pilot scopes:</p><ul>#{items}</ul>
    <h2>Links needing review</h2><ul>#{cases}</ul>
    <form method="post" action="/users/log-out"><input type="hidden" name="_csrf_token" value="#{csrf_token()}"><input type="hidden" name="_method" value="delete">
    <button type="submit">Sign out</button></form></main></body></html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(200, body)
  end

  defp csrf_token, do: Plug.CSRFProtection.get_csrf_token()
  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
