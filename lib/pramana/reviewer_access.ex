defmodule Pramana.ReviewerAccess do
  @moduledoc """
  Operator-provisioned reviewer identities and exact-scope grants.

  A credential is 32 random bytes shown once to the operator. Only its SHA-256 digest
  is stored. Reviewer-mode HTTP uses this module only to read accounts and grants;
  provisioning and revocation require separate operator database credentials.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Pramana.Repo
  alias Pramana.Reviewer.Account
  alias Pramana.Reviewer.Grant

  @session_seconds 8 * 60 * 60
  @scope_pattern ~r/\A[0-9a-f]{64}\z/
  @credential_pattern ~r/\A[A-Za-z0-9_-]{43}\z/

  @doc "Operator action: create an individual account and its first exact-scope grant."
  def provision(login_id, display_name, scope_sha256, granted_by)
      when is_binary(login_id) and is_binary(display_name) and is_binary(scope_sha256) and
             is_binary(granted_by) do
    login_id = normalize_login(login_id)
    scope_sha256 = String.trim(scope_sha256)
    credential = new_credential()

    account =
      Account.changeset(%Account{}, %{
        login_id: login_id,
        display_name: String.trim(display_name),
        credential_digest: digest(credential)
      })

    if Regex.match?(@scope_pattern, scope_sha256) do
      Multi.new()
      |> Multi.insert(:account, account)
      |> Multi.insert(:grant, fn %{account: inserted} ->
        Grant.changeset(%Grant{}, %{
          account_id: inserted.id,
          scope_sha256: scope_sha256,
          granted_by: String.trim(granted_by)
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{account: inserted}} -> {:ok, inserted, credential}
        {:error, _step, changeset, _changes} -> {:error, changeset}
      end
    else
      {:error, :invalid_scope}
    end
  end

  def provision(_, _, _, _), do: {:error, :invalid_input}

  @doc "Operator action: grant another exact scope to an existing active account."
  def grant_scope(login_id, scope_sha256, granted_by)
      when is_binary(login_id) and is_binary(scope_sha256) and is_binary(granted_by) do
    with true <- Regex.match?(@scope_pattern, scope_sha256),
         %Account{active: true} = account <-
           Repo.get_by(Account, login_id: normalize_login(login_id)) do
      %Grant{}
      |> Grant.changeset(%{
        account_id: account.id,
        scope_sha256: scope_sha256,
        granted_by: String.trim(granted_by)
      })
      |> Repo.insert()
    else
      _ -> {:error, :invalid_account_or_scope}
    end
  end

  def grant_scope(_, _, _), do: {:error, :invalid_input}

  @doc "Operator action: revoke one scope without deleting its grant history."
  def revoke_scope(login_id, scope_sha256, revoked_by)
      when is_binary(login_id) and is_binary(scope_sha256) and is_binary(revoked_by) do
    with true <- Regex.match?(@scope_pattern, scope_sha256),
         true <- String.trim(revoked_by) != "",
         %Account{} = account <- Repo.get_by(Account, login_id: normalize_login(login_id)) do
      now = DateTime.utc_now()

      {count, _} =
        from(g in Grant,
          where:
            g.account_id == ^account.id and g.scope_sha256 == ^scope_sha256 and
              is_nil(g.revoked_at)
        )
        |> Repo.update_all(set: [revoked_at: now, revoked_by: String.trim(revoked_by)])

      if count == 1, do: :ok, else: {:error, :not_found}
    else
      _ -> {:error, :invalid_account_or_scope}
    end
  end

  def revoke_scope(_, _, _), do: {:error, :invalid_input}

  @doc "Operator action: disable an account and invalidate every signed session."
  def disable_account(login_id) when is_binary(login_id) do
    case Repo.get_by(Account, login_id: normalize_login(login_id)) do
      %Account{} = account ->
        account
        |> Ecto.Changeset.change(active: false, session_epoch: account.session_epoch + 1)
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  def disable_account(_), do: {:error, :invalid_input}

  @doc "Operator action: replace a credential and invalidate earlier sessions."
  def rotate_credential(login_id) when is_binary(login_id) do
    case Repo.get_by(Account, login_id: normalize_login(login_id)) do
      %Account{active: true} = account ->
        credential = new_credential()

        account
        |> Ecto.Changeset.change(
          credential_digest: digest(credential),
          session_epoch: account.session_epoch + 1
        )
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated, credential}
          error -> error
        end

      _ ->
        {:error, :not_found}
    end
  end

  def rotate_credential(_), do: {:error, :invalid_input}

  @doc "Checks one supplied credential and requires at least one live grant."
  def authenticate(login_id, credential)
      when is_binary(login_id) and is_binary(credential) do
    with true <- Regex.match?(@credential_pattern, credential),
         %Account{active: true} = account <-
           Repo.get_by(Account, login_id: normalize_login(login_id)),
         true <- Plug.Crypto.secure_compare(account.credential_digest, digest(credential)),
         [_ | _] <- active_scopes(account.id) do
      {:ok, account}
    else
      _ -> :error
    end
  end

  def authenticate(_, _), do: :error

  @doc "Rechecks account status, session epoch and grants on each private request."
  def session_account(account_id, epoch)
      when is_binary(account_id) and is_integer(epoch) do
    with {:ok, _uuid} <- Ecto.UUID.cast(account_id),
         %Account{active: true, session_epoch: ^epoch} = account <- Repo.get(Account, account_id),
         [_ | _] = scopes <- active_scopes(account.id) do
      {:ok, account, scopes}
    else
      _ -> :error
    end
  end

  def session_account(_, _), do: :error

  @doc "Maximum lifetime of a signed browser session, in seconds."
  def session_seconds, do: @session_seconds

  defp active_scopes(account_id) do
    from(g in Grant,
      where:
        g.account_id == ^account_id and g.capability == "relation_review" and is_nil(g.revoked_at),
      order_by: g.scope_sha256,
      select: g.scope_sha256
    )
    |> Repo.all()
  end

  defp normalize_login(login_id), do: login_id |> String.trim() |> String.downcase()
  defp new_credential, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp digest(value),
    do: value |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end
