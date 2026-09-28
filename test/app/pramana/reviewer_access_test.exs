defmodule Pramana.ReviewerAccessTest do
  use Pramana.DataCase, async: true

  alias Pramana.AccountsFixtures
  alias Pramana.ReviewerAccess

  @scope String.duplicate("a", 64)

  test "only a confirmed user receives an exact scope grant" do
    unconfirmed = AccountsFixtures.unconfirmed_user_fixture()

    assert {:error, :invalid_user_or_scope} =
             ReviewerAccess.grant_scope(unconfirmed.email, @scope, "operator-1")

    user = AccountsFixtures.user_fixture()
    assert {:ok, grant} = ReviewerAccess.grant_scope(user.email, @scope, "operator-1")
    assert grant.account_id == user.id
    assert ReviewerAccess.active_scopes(user.id) == [@scope]

    assert {:error, :invalid_user_or_scope} =
             ReviewerAccess.grant_scope(user.email, "wrong", "operator-1")
  end

  test "revocation removes live access while retaining grant history" do
    user = AccountsFixtures.user_fixture()
    other_scope = String.duplicate("b", 64)
    assert {:ok, _} = ReviewerAccess.grant_scope(user.email, @scope, "operator-1")
    assert {:ok, _} = ReviewerAccess.grant_scope(user.email, other_scope, "operator-1")

    assert :ok = ReviewerAccess.revoke_scope(user.email, @scope, "operator-1")
    assert ReviewerAccess.active_scopes(user.id) == [other_scope]
    assert :ok = ReviewerAccess.revoke_all(user.email, "operator-1")
    assert ReviewerAccess.active_scopes(user.id) == []
  end
end
