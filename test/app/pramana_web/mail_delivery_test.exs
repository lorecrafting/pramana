defmodule PramanaWeb.MailDeliveryTest do
  use PramanaWeb.ConnCase, async: false

  alias Pramana.Accounts
  alias Pramana.Accounts.UserToken
  alias Pramana.Repo

  test "unconfigured delivery rejects signup before creating identity or token" do
    ready = Application.get_env(:pramana, :mail_delivery_ready)
    Application.put_env(:pramana, :mail_delivery_ready, false)
    on_exit(fn -> Application.put_env(:pramana, :mail_delivery_ready, ready) end)

    email = "no-delivery@example.com"

    assert get(build_conn(), "/users/register").status == 503
    assert post(build_conn(), "/users/register", user: %{email: email}).status == 503
    refute Accounts.get_user_by_email(email)
    assert Repo.aggregate(UserToken, :count, :user_id) == 0
  end
end
