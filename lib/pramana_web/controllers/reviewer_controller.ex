defmodule PramanaWeb.ReviewerController do
  use PramanaWeb, :controller

  alias Pramana.Reviewer.Reviews
  alias Pramana.Reviewer.WorkReviews
  alias Pramana.ReviewerAccess

  def index(conn, _params) do
    account = conn.assigns.current_scope.user
    scopes = conn.assigns.reviewer_scopes

    with {:ok, artifact} <- Reviews.configured_scope(),
         {:ok, cases} <- Reviews.list_cases(artifact, scopes),
         {:ok, works} <- WorkReviews.list(artifact, scopes, account.id) do
      render(conn, :index,
        account: account,
        cases: cases,
        works: works,
        rights_granted:
          artifact["scope_content_sha256"] in ReviewerAccess.active_scopes(
            account.id,
            "rights_signoff"
          ),
        scope_sha256: artifact["scope_content_sha256"]
      )
    else
      _ -> send_resp(conn, 503, "Review scope unavailable")
    end
  end
end
