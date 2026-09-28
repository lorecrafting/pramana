defmodule PramanaWeb.ReviewerWorkController do
  use PramanaWeb, :controller

  alias Pramana.Reviewer.Reviews
  alias Pramana.Reviewer.WorkReviews

  def show(conn, %{"work_id" => work_id}) do
    with {:ok, artifact} <- Reviews.configured_scope(),
         {:ok, work_review} <-
           WorkReviews.get(
             artifact,
             conn.assigns.reviewer_scopes,
             conn.assigns.current_scope.user.id,
             work_id
           ) do
      render(conn, :show,
        work_review: work_review,
        form: Phoenix.Component.to_form(%{}, as: :work_review)
      )
    else
      {:error, :scope_not_configured} -> send_resp(conn, 503, "Review scope unavailable")
      {:error, :invalid_scope_artifact} -> send_resp(conn, 503, "Review scope unavailable")
      {:error, :invalidated_scope} -> send_resp(conn, 503, "Review scope unavailable")
      _ -> send_resp(conn, 404, "Work unavailable in this scope")
    end
  end

  def create(conn, %{"work_id" => work_id} = params) do
    submission = Map.get(params, "work_review", Map.delete(params, "work_id"))

    with {:ok, artifact} <- Reviews.configured_scope(),
         {:ok, _judgment} <-
           WorkReviews.submit(conn.assigns.current_scope.user, artifact, work_id, submission) do
      conn
      |> put_flash(:info, "Work recommendation saved with your name and sources.")
      |> redirect(to: "/reviews/works/#{work_id}")
    else
      {:error, :scope_not_configured} -> send_resp(conn, 503, "Review scope unavailable")
      {:error, :invalid_scope_artifact} -> send_resp(conn, 503, "Review scope unavailable")
      {:error, :invalidated_scope} -> send_resp(conn, 503, "Review scope unavailable")
      {:error, :invalid_submission} -> send_resp(conn, 400, "Invalid review submission")
      _ -> send_resp(conn, 409, "Work changed or access expired")
    end
  end
end
