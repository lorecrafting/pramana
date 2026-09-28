defmodule PramanaWeb.ReviewerRouter do
  @moduledoc "Only sign-in and granted reviewer pages are routable in private mode."

  use PramanaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :reviewer do
    plug PramanaWeb.ReviewerAuth
  end

  scope "/", PramanaWeb do
    pipe_through :browser

    get "/login", ReviewerController, :login
    post "/login", ReviewerController, :create_session
  end

  scope "/", PramanaWeb do
    pipe_through [:browser, :reviewer]

    get "/", ReviewerController, :index
    post "/logout", ReviewerController, :logout
  end
end
