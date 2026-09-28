defmodule PramanaWeb.ReviewerEndpoint do
  @moduledoc "Private reviewer HTTP entrypoint. It mounts no reader socket or MCP route."

  use Phoenix.Endpoint, otp_app: :pramana

  @session_options [
    store: :cookie,
    key: "_pramana_reviewer",
    signing_salt: "XfQcaVEp",
    same_site: "Strict",
    secure: true,
    max_age: 8 * 60 * 60
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded],
    pass: ["text/*"],
    length: 65_536

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug PramanaWeb.ReviewerRouter
end
