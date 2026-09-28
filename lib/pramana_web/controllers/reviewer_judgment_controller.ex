defmodule PramanaWeb.ReviewerJudgmentController do
  use PramanaWeb, :controller

  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Reviewer.Reviews

  def show(conn, %{"id" => id}) do
    with {:ok, artifact} <- Reviews.configured_scope(),
         {:ok, review_case} <-
           Reviews.get_case(
             artifact,
             conn.assigns.reviewer_scopes,
             conn.assigns.reviewer_account.id,
             id
           ) do
      body = page(review_case)
      conn |> put_resp_content_type("text/html") |> send_resp(200, body)
    else
      {:error, :scope_not_configured} -> send_resp(conn, 503, "Review scope unavailable")
      {:error, :invalid_scope_artifact} -> send_resp(conn, 503, "Review scope unavailable")
      _ -> send_resp(conn, 404, "Review case unavailable")
    end
  end

  def create(conn, %{"id" => id} = params) do
    with {:ok, artifact} <- Reviews.configured_scope(),
         {:ok, _judgment} <-
           Reviews.submit(conn.assigns.reviewer_account, artifact, id, Map.delete(params, "id")) do
      redirect(conn, to: "/reviews/#{id}")
    else
      {:error, :scope_not_configured} -> send_resp(conn, 503, "Review scope unavailable")
      {:error, :invalid_scope_artifact} -> send_resp(conn, 503, "Review scope unavailable")
      {:error, :invalid_submission} -> send_resp(conn, 400, "Invalid review submission")
      _ -> send_resp(conn, 409, "Review case changed or access expired")
    end
  end

  defp page(review_case) do
    row = review_case.row
    assertion = review_case.candidate.assertion

    evidence =
      assertion["evidence"]
      |> ScopeArtifact.encode()
      |> escape()

    quotations =
      case review_case.quotations do
        [] ->
          "<p>No current-bake shared-passage example is available for this pair.</p>"

        examples ->
          Enum.map_join(examples, "", fn quote ->
            """
            <li><blockquote lang="zh-Hant">#{escape(quote.text)}</blockquote>
            <p>Commentary address: <code>#{escape(quote.source_urn)}</code>
            (text characters [#{quote.source_start}, #{quote.source_end}))<br>
            Target address: <code>#{escape(quote.target_urn)}</code>
            (text characters [#{quote.target_start}, #{quote.target_end}))<br>
            Shared-text SHA-256: <code>#{escape(quote.text_sha256)}</code></p></li>
            """
          end)
      end

    history =
      case review_case.judgments do
        [] ->
          "<li>No judgment submitted by this account for this case.</li>"

        judgments ->
          Enum.map_join(judgments, "", fn judgment ->
            """
            <li><strong>#{escape(judgment.judgment)}</strong> at
            #{escape(DateTime.to_iso8601(judgment.inserted_at))}: #{escape(judgment.rationale)}
            <br>Sources: #{escape(judgment.source_references)}</li>
            """
          end)
      end

    """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Review commentary link</title></head>
    <body><main><p><a href="/">← Review cases</a></p><h1>Review commentary link</h1>
    <p><strong>Needs review:</strong> #{escape(assertion["review_reason"])}</p>
    <p>#{work_label(review_case.source)} explains #{work_label(review_case.target)}
    via <code>#{escape(row.relation)}</code>. This is a candidate link, not an accepted edition claim.</p>
    <p>Method: #{escape(assertion["method"])}; confidence: #{escape(assertion["confidence"])};
    scope: #{escape(assertion["scope"])}; target address: #{escape(assertion["target_urn"])}.</p>
    <h2>Assertion evidence</h2><pre>#{evidence}</pre>
    <h2>Source context</h2><p>Witness: CBETA Taishō. Shared text alone does not prove direction.</p>
    <ul>#{quotations}</ul>
    <form method="post" action="/reviews/#{row.id}">
    <input type="hidden" name="_csrf_token" value="#{csrf_token()}">
    <input type="hidden" name="scope_sha256" value="#{escape(review_case.scope_sha256)}">
    <input type="hidden" name="release_id" value="#{escape(review_case.release_id)}">
    <input type="hidden" name="assertion_fingerprint" value="#{escape(review_case.fingerprint)}">
    <label for="judgment">Judgment</label>
    <select id="judgment" name="judgment" required>
      <option value="supported">Supported</option><option value="disputed">Disputed</option>
      <option value="cannot_determine">Cannot determine</option>
    </select>
    <label for="rationale">Reason</label><textarea id="rationale" name="rationale" maxlength="2000" required></textarea>
    <label for="source_references">Source references examined</label>
    <textarea id="source_references" name="source_references" maxlength="2000" required></textarea>
    <button type="submit">Record judgment</button></form>
    <h2>Your previous judgments</h2><ul>#{history}</ul>
    <p>Submitting a judgment does not change the relation's Needs review status.</p>
    </main></body></html>
    """
  end

  defp work_label(work) do
    "<cite>#{escape(work.title)} (#{escape(work.id)})</cite>" <>
      " — #{escape(work.text_role)}, #{escape(work.attributed_author)}"
  end

  defp csrf_token, do: Plug.CSRFProtection.get_csrf_token()

  defp escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
