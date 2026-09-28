defmodule Pramana.ReviewerAccessTest do
  use Pramana.DataCase, async: true

  alias Pramana.Reviewer.Account
  alias Pramana.ReviewerAccess

  @scope String.duplicate("a", 64)

  test "individual credential and grant control access without storing the credential" do
    assert {:ok, account, credential} =
             ReviewerAccess.provision(" Reviewer.One ", "silent principal", @scope, "operator-1")

    stored = Repo.get!(Account, account.id)
    assert stored.login_id == "reviewer.one"
    assert stored.display_name == "silent principal"
    refute stored.credential_digest == credential
    assert {:ok, ^account} = ReviewerAccess.authenticate("reviewer.one", credential)
    assert {:ok, ^account, [@scope]} = ReviewerAccess.session_account(account.id, 0)

    assert :ok = ReviewerAccess.revoke_scope("reviewer.one", @scope, "operator-1")
    assert :error = ReviewerAccess.authenticate("reviewer.one", credential)
    assert :error = ReviewerAccess.session_account(account.id, 0)

    assert {:ok, _grant} = ReviewerAccess.grant_scope("reviewer.one", @scope, "operator-1")
    assert {:ok, ^account, [@scope]} = ReviewerAccess.session_account(account.id, 0)
  end

  test "credential rotation and account disable invalidate earlier sessions" do
    assert {:ok, account, credential} =
             ReviewerAccess.provision("reviewer.two", "Reviewer Two", @scope, "operator-1")

    assert {:ok, rotated, replacement} = ReviewerAccess.rotate_credential("reviewer.two")
    assert rotated.session_epoch == 1
    assert :error = ReviewerAccess.authenticate("reviewer.two", credential)
    assert :error = ReviewerAccess.session_account(account.id, 0)
    assert {:ok, ^rotated} = ReviewerAccess.authenticate("reviewer.two", replacement)

    assert {:ok, twice_rotated, _next_credential} =
             ReviewerAccess.rotate_credential("reviewer.two")

    assert twice_rotated.session_epoch == 2
    assert :error = ReviewerAccess.session_account(account.id, 1)

    assert {:ok, disabled} = ReviewerAccess.disable_account("reviewer.two")
    refute disabled.active
    assert :error = ReviewerAccess.authenticate("reviewer.two", replacement)
    assert :error = ReviewerAccess.session_account(account.id, 2)
  end
end
