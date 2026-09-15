defmodule Pramana.Repo do
  use Ecto.Repo,
    otp_app: :pramana,
    adapter: Ecto.Adapters.Postgres
end
