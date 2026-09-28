defmodule PramanaWeb.UserRegistrationController do
  use PramanaWeb, :controller

  alias Pramana.Accounts
  alias Pramana.Accounts.User
  alias Pramana.Mailer
  alias PramanaWeb.UserAuth

  def new(conn, _params) do
    if Mailer.delivery_ready?() do
      changeset = Accounts.change_user_email(%User{})
      render(conn, :new, changeset: changeset)
    else
      send_resp(conn, 503, "Account email delivery is unavailable")
    end
  end

  def create(conn, %{"user" => user_params}) do
    if Mailer.delivery_ready?(),
      do: register(conn, user_params),
      else: send_resp(conn, 503, "Account email delivery is unavailable")
  end

  defp register(conn, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &UserAuth.absolute_url(conn, ~p"/users/log-in/#{&1}")
          )

        conn
        |> put_flash(
          :info,
          "An email was sent to #{user.email}, please access it to confirm your account."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
