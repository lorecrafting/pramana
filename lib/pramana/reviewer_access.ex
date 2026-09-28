defmodule Pramana.ReviewerAccess do
  @moduledoc "Operator-managed exact-scope grants for registered users."

  import Ecto.Query

  alias Pramana.Accounts.User
  alias Pramana.Repo
  alias Pramana.Reviewer.Grant

  @scope_pattern ~r/\A[0-9a-f]{64}\z/

  @doc "Operator action: grant one exact review scope to a registered user."
  def grant_scope(email, scope_sha256, granted_by, capability \\ "relation_review")

  def grant_scope(email, scope_sha256, granted_by, capability)
      when is_binary(email) and is_binary(scope_sha256) and is_binary(granted_by) and
             capability in ["relation_review", "rights_signoff"] do
    with true <- Regex.match?(@scope_pattern, scope_sha256),
         %User{} = user <- Repo.get_by(User, email: String.trim(email)),
         true <- not is_nil(user.confirmed_at) do
      %Grant{capability: capability}
      |> Grant.changeset(%{
        account_id: user.id,
        scope_sha256: scope_sha256,
        granted_by: String.trim(granted_by)
      })
      |> Repo.insert()
    else
      _ -> {:error, :invalid_user_or_scope}
    end
  end

  def grant_scope(_, _, _, _), do: {:error, :invalid_input}

  @doc "Operator action: revoke one scope without deleting grant history."
  def revoke_scope(email, scope_sha256, revoked_by, capability \\ nil)

  def revoke_scope(email, scope_sha256, revoked_by, capability)
      when is_binary(email) and is_binary(scope_sha256) and is_binary(revoked_by) and
             capability in [nil, "relation_review", "rights_signoff"] do
    with true <- Regex.match?(@scope_pattern, scope_sha256),
         true <- String.trim(revoked_by) != "",
         %User{} = user <- Repo.get_by(User, email: String.trim(email)) do
      revoke(user.id, scope_sha256, String.trim(revoked_by), capability)
    else
      _ -> {:error, :invalid_user_or_scope}
    end
  end

  def revoke_scope(_, _, _, _), do: {:error, :invalid_input}

  @doc "Operator action: revoke every active scope for one account."
  def revoke_all(email, revoked_by) when is_binary(email) and is_binary(revoked_by) do
    with true <- String.trim(revoked_by) != "",
         %User{} = user <- Repo.get_by(User, email: String.trim(email)) do
      revoke(user.id, nil, String.trim(revoked_by), nil)
    else
      _ -> {:error, :invalid_user}
    end
  end

  def revoke_all(_, _), do: {:error, :invalid_input}

  @doc "Read current grants for the authenticated user on every private request."
  def active_scopes(user_id, capability \\ "relation_review")

  def active_scopes(user_id, capability)
      when is_binary(user_id) and capability in ["relation_review", "rights_signoff"] do
    from(g in Grant,
      where: g.account_id == ^user_id and g.capability == ^capability and is_nil(g.revoked_at),
      order_by: g.scope_sha256,
      select: g.scope_sha256
    )
    |> Repo.all()
  end

  defp revoke(user_id, scope_sha256, revoked_by, capability) do
    query = from(g in Grant, where: g.account_id == ^user_id and is_nil(g.revoked_at))
    query = if scope_sha256, do: where(query, [g], g.scope_sha256 == ^scope_sha256), else: query
    query = if capability, do: where(query, [g], g.capability == ^capability), else: query

    {count, _} =
      Repo.update_all(query,
        set: [revoked_at: DateTime.utc_now(), revoked_by: revoked_by]
      )

    if count > 0, do: :ok, else: {:error, :not_found}
  end
end
