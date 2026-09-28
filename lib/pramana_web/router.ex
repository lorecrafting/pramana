defmodule PramanaWeb.Router do
  use PramanaWeb, :router

  import PramanaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PramanaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # The MCP surface. Not under a browser pipeline: it is JSON-RPC over Streamable
  # HTTP, consumed by agents rather than browsers.
  forward "/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: PramanaWeb.MCP.Server

  # The reader. A renderer over the same domain the MCP surface reads — see
  # `PramanaWeb.SearchLive`. Query state lives in the URL so a search, and the passage it
  # found, are both linkable.
  scope "/", PramanaWeb do
    pipe_through :browser

    live "/", SearchLive, :index
    live "/passage", PassageLive, :show
    live "/works/:work_id", WorkLive, :show
    live "/survey", SurveyLive, :index
    live "/inventory", InventoryLive, :index
    live "/check", CheckLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", PramanaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:pramana, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PramanaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PramanaWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", PramanaWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", PramanaWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
