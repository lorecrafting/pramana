defmodule Pramana.ReviewerTaskTest do
  use Pramana.DataCase, async: false

  alias Mix.Tasks.Pramana.Reviewer
  alias Pramana.Accounts
  import Swoosh.TestAssertions

  test "operator provision creates an ungranted private user and sends a private link" do
    previous = System.get_env("PRAMANA_REVIEWER_URL")
    System.put_env("PRAMANA_REVIEWER_URL", "https://review.example")

    on_exit(fn ->
      if previous,
        do: System.put_env("PRAMANA_REVIEWER_URL", previous),
        else: System.delete_env("PRAMANA_REVIEWER_URL")
    end)

    email = "private-#{System.unique_integer([:positive])}@example.com"
    Reviewer.run(["provision", "--email", email])

    user = Accounts.get_user_by_email(email)
    assert user
    assert is_nil(user.confirmed_at)

    assert_email_sent(fn mail ->
      mail.to == [{"", email}] and mail.text_body =~ "https://review.example/users/log-in/"
    end)
  end

  test "serving processes cannot run account management" do
    previous = System.get_env("PRAMANA_REVIEWER")
    System.put_env("PRAMANA_REVIEWER", "1")

    on_exit(fn ->
      if previous,
        do: System.put_env("PRAMANA_REVIEWER", previous),
        else: System.delete_env("PRAMANA_REVIEWER")
    end)

    assert_raise Mix.Error, ~r/separate operator process/, fn ->
      Reviewer.run([
        "grant",
        "--email",
        "reviewer@example.com",
        "--scope-sha256",
        String.duplicate("a", 64),
        "--operator",
        "test"
      ])
    end
  end
end
