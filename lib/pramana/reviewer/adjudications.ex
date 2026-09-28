defmodule Pramana.Reviewer.Adjudications do
  @moduledoc "Operator inspection and explicit dispositions of attributed link reviews."

  import Ecto.Query

  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Release.Selection
  alias Pramana.Repo
  alias Pramana.Reviewer.Account
  alias Pramana.Reviewer.Disposition
  alias Pramana.Reviewer.Judgment
  alias Pramana.Reviewer.Reviews

  @doc "Shows the live scoped assertion, all judgments and earlier dispositions."
  def inspect_case(artifact, assertion_id) do
    with {:ok, id} <- parse_id(assertion_id),
         %WorkRelation{} = row <- Repo.get(WorkRelation, id) do
      snapshot = Reviews.live_snapshot(row)

      in_scope =
        selected_release_id() == artifact["release"]["release_id"] and
          match?({:ok, _}, Reviews.exact_candidate(artifact, row)) and
          not invalidated?(artifact["scope_content_sha256"])

      {:ok,
       %{
         row: row,
         fingerprint: ScopeArtifact.digest(snapshot),
         snapshot: snapshot,
         in_scope: in_scope,
         judgments: judgments(id),
         dispositions: dispositions(id)
       }}
    else
      _ -> {:error, :unavailable_case}
    end
  end

  @doc "Records one source-backed decision and clears the flag only when supported."
  def decide(artifact, assertion_id, expected_fingerprint, attrs) when is_map(attrs) do
    changeset =
      %Disposition{}
      |> Disposition.changeset(trim_fields(attrs))

    with {:ok, id} <- parse_id(assertion_id),
         true <- changeset.valid?,
         true <- is_binary(expected_fingerprint) do
      Repo.transaction(fn ->
        decide_locked(artifact, id, expected_fingerprint, changeset)
      end)
    else
      _ -> {:error, :invalid_decision}
    end
  end

  def decide(_, _, _, _), do: {:error, :invalid_decision}

  defp decide_locked(artifact, assertion_id, expected_fingerprint, changeset) do
    scope_sha256 = artifact["scope_content_sha256"]
    release_id = artifact["release"]["release_id"]

    # Serialize decisions for a scope before checking whether one already resolved it.
    with ^release_id <- selected_release_id_locked(),
         false <- invalidated?(scope_sha256),
         %WorkRelation{} = row <- relation_locked(assertion_id),
         {:ok, exact} <- Reviews.exact_candidate(artifact, row),
         ^expected_fingerprint <- exact.fingerprint,
         true <- reviewed?(assertion_id, scope_sha256, release_id, exact.fingerprint) do
      record_decision(row, artifact, exact, changeset)
    else
      _ -> Repo.rollback(:stale_or_unreviewed)
    end
  end

  defp record_decision(row, artifact, exact, changeset) do
    disposition = Ecto.Changeset.get_field(changeset, :disposition)

    changeset =
      Ecto.Changeset.change(changeset, %{
        assertion_id: row.id,
        scope_sha256: artifact["scope_content_sha256"],
        release_id: artifact["release"]["release_id"],
        assertion_fingerprint: exact.fingerprint,
        assertion_snapshot: Reviews.assertion_snapshot(exact.candidate),
        inserted_at: DateTime.utc_now()
      })

    case Repo.insert(changeset) do
      {:ok, saved} ->
        if disposition == "supported" do
          row
          |> Ecto.Changeset.change(review_status: "unflagged", review_reason: nil)
          |> Repo.update!()
        end

        saved

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp judgments(assertion_id) do
    from(j in Judgment,
      join: a in Account,
      on: a.id == j.account_id,
      where: j.assertion_id == ^assertion_id,
      order_by: [asc: j.inserted_at, asc: j.id],
      select: %{judgment: j, display_name: a.display_name, login_id: a.login_id}
    )
    |> Repo.all()
  end

  defp dispositions(assertion_id) do
    from(d in Disposition,
      where: d.assertion_id == ^assertion_id,
      order_by: [asc: d.inserted_at, asc: d.id]
    )
    |> Repo.all()
  end

  defp reviewed?(assertion_id, scope_sha256, release_id, fingerprint) do
    Repo.exists?(
      from j in Judgment,
        where:
          j.assertion_id == ^assertion_id and j.scope_sha256 == ^scope_sha256 and
            j.release_id == ^release_id and j.assertion_fingerprint == ^fingerprint
    )
  end

  defp invalidated?(scope_sha256) do
    Repo.exists?(
      from d in Disposition,
        where: d.scope_sha256 == ^scope_sha256 and d.disposition == "supported"
    )
  end

  defp selected_release_id do
    from(s in Selection,
      join: release in ReleaseSchema,
      on: release.id == s.release_id,
      where: s.id == 1,
      select: release.release_id
    )
    |> Repo.one()
  end

  defp selected_release_id_locked do
    from(s in Selection,
      join: release in ReleaseSchema,
      on: release.id == s.release_id,
      where: s.id == 1,
      select: release.release_id,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  defp relation_locked(id) do
    from(r in WorkRelation, where: r.id == ^id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}

  defp trim_fields(attrs) do
    Map.new(attrs, fn {key, value} ->
      {key, if(is_binary(value), do: String.trim(value), else: value)}
    end)
  end
end
