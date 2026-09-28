defmodule PramanaWeb.ReviewerRightsController do
  use PramanaWeb, :controller

  alias Pramana.Reviewer.Reviews
  alias Pramana.Reviewer.RightsReviews

  def index(conn, _params) do
    with {:ok, artifact} <- Reviews.configured_scope(),
         {:ok, items} <-
           RightsReviews.list(
             artifact,
             conn.assigns.rights_scopes,
             conn.assigns.current_scope.user.id
           ) do
      render(conn, :index, items: items, scope_sha256: artifact["scope_content_sha256"])
    else
      _ -> send_resp(conn, 503, "Rights scope unavailable")
    end
  end

  def show(conn, %{"item_id" => item_id}) do
    with {:ok, artifact} <- Reviews.configured_scope(),
         {:ok, rights_review} <-
           RightsReviews.get(
             artifact,
             conn.assigns.rights_scopes,
             conn.assigns.current_scope.user.id,
             item_id
           ) do
      render(conn, :show,
        rights_review: rights_review,
        form: Phoenix.Component.to_form(%{}, as: :rights_review)
      )
    else
      {:error, :scope_not_configured} -> send_resp(conn, 503, "Rights scope unavailable")
      {:error, :invalid_scope_artifact} -> send_resp(conn, 503, "Rights scope unavailable")
      {:error, :invalidated_scope} -> send_resp(conn, 503, "Rights scope unavailable")
      _ -> send_resp(conn, 404, "Rights item unavailable")
    end
  end

  def create(conn, %{"item_id" => item_id} = params) do
    submission = Map.get(params, "rights_review", Map.delete(params, "item_id"))

    with {:ok, artifact} <- Reviews.configured_scope(),
         {:ok, _judgment} <-
           RightsReviews.submit(conn.assigns.current_scope.user, artifact, item_id, submission) do
      conn
      |> put_flash(:info, "Rights assessment saved with your account and evidence.")
      |> redirect(to: "/reviews/rights/#{item_id}")
    else
      {:error, :scope_not_configured} -> send_resp(conn, 503, "Rights scope unavailable")
      {:error, :invalid_scope_artifact} -> send_resp(conn, 503, "Rights scope unavailable")
      {:error, :invalidated_scope} -> send_resp(conn, 503, "Rights scope unavailable")
      {:error, :invalid_submission} -> send_resp(conn, 400, "Invalid rights submission")
      _ -> send_resp(conn, 409, "Rights scope changed or access expired")
    end
  end
end
