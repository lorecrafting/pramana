defmodule PramanaWeb.ReviewerRouter do
  @moduledoc "Generated account sign-in and granted reviewer pages in private mode."

  use PramanaWeb, :router
  import PramanaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :mark_reviewer_endpoint
    plug :put_root_layout, html: {PramanaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  defp mark_reviewer_endpoint(conn, _opts), do: assign(conn, :private_reviewer, true)

  if Application.compile_env(:pramana, :dev_routes) do
    scope "/dev" do
      pipe_through :browser
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  pipeline :reviewer do
    plug :require_authenticated_user
    plug :require_reviewer_grant
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  scope "/", PramanaWeb do
    pipe_through :browser

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", PramanaWeb do
    pipe_through [:browser, :authenticated]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", PramanaWeb do
    pipe_through [:browser, :reviewer]

    get "/", ReviewerController, :index
    get "/reviews/:id", ReviewerJudgmentController, :show
    post "/reviews/:id", ReviewerJudgmentController, :create
  end
end
