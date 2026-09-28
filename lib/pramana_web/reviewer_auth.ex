defmodule PramanaWeb.ReviewerAuth do
  @moduledoc "Rechecks the individual account and its current grants for every request."

  import Plug.Conn
  alias Pramana.ReviewerAccess

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "reviewer_session") do
      %{"account_id" => id, "epoch" => epoch, "expires_at" => expires_at}
      when is_integer(expires_at) ->
        authorize(conn, id, epoch, expires_at)

      _ ->
        deny(conn)
    end
  end

  defp authorize(conn, id, epoch, expires_at) do
    with true <- System.system_time(:second) < expires_at,
         {:ok, account, scopes} <- ReviewerAccess.session_account(id, epoch) do
      conn |> assign(:reviewer_account, account) |> assign(:reviewer_scopes, scopes)
    else
      _ -> deny(conn)
    end
  end

  defp deny(conn) do
    conn
    |> delete_session("reviewer_session")
    |> Phoenix.Controller.redirect(to: "/login")
    |> halt()
  end
end
