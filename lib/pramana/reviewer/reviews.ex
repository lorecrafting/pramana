defmodule Pramana.Reviewer.Reviews do
  @moduledoc "Private review cases and attributed judgments for one configured pilot scope."

  import Ecto.Query

  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Release
  alias Pramana.Release.Selection
  alias Pramana.Repo
  alias Pramana.Reviewer.Account
  alias Pramana.Reviewer.Grant
  alias Pramana.Reviewer.Judgment

  @form_keys ~w(_csrf_token judgment rationale source_references scope_sha256 release_id assertion_fingerprint)

  @doc "Loads the operator-mounted scope artifact. A missing or invalid file exposes no cases."
  def configured_scope do
    case System.get_env("PRAMANA_REVIEW_SCOPE_PATH") do
      path when is_binary(path) and path != "" ->
        with {:ok, bytes} <- File.read(path),
             {:ok, artifact} <- decode(bytes),
             :ok <- ScopeArtifact.validate(artifact) do
          {:ok, artifact}
        else
          _ -> {:error, :invalid_scope_artifact}
        end

      _ ->
        {:error, :scope_not_configured}
    end
  end

  @doc "Lists only current flagged assertions present in the configured exact scope."
  def list_cases(artifact, scopes) do
    with :ok <- permitted_scope(artifact, scopes),
         :ok <- selected_release(artifact) do
      candidates = candidates(artifact)

      rows =
        from(r in WorkRelation, where: r.review_status == "needs_review", order_by: r.id)
        |> Repo.all()

      {:ok, matching_cases(rows, candidates)}
    end
  end

  @doc "Loads one current case with work metadata, source quotations and this reviewer's history."
  def get_case(artifact, scopes, account_id, id) do
    with :ok <- permitted_scope(artifact, scopes),
         :ok <- selected_release(artifact),
         {:ok, parsed_id} <- parse_id(id),
         %WorkRelation{} = row <- Repo.get(WorkRelation, parsed_id),
         %{} = candidate <- Enum.find(candidates(artifact), &matches?(&1, row)),
         %Work{} = source <- Repo.get(Work, row.source_work_id),
         %Work{} = target <- Repo.get(Work, row.target_work_id) do
      {:ok,
       %{
         row: row,
         candidate: candidate,
         fingerprint: fingerprint(candidate),
         scope_sha256: artifact["scope_content_sha256"],
         release_id: artifact["release"]["release_id"],
         source: source,
         target: target,
         quotations: quotation_examples(row, artifact["release"]["source_bake_id"]),
         judgments:
           own_judgments(
             account_id,
             row.id,
             artifact["scope_content_sha256"],
             artifact["release"]["release_id"],
             fingerprint(candidate)
           )
       }}
    else
      _ -> {:error, :unavailable_case}
    end
  end

  @doc "Appends a judgment only while account, grant, release and assertion still match."
  def submit(%Account{} = account, artifact, id, params) when is_map(params) do
    scope_sha256 = artifact["scope_content_sha256"]
    release_id = artifact["release"]["release_id"]

    with true <- Enum.all?(Map.keys(params), &(&1 in @form_keys)),
         {:ok, parsed_id} <- parse_id(id),
         true <- params["scope_sha256"] == scope_sha256,
         true <- params["release_id"] == release_id,
         changeset <- judgment_changeset(params),
         true <- changeset.valid? do
      Repo.transaction(fn ->
        append_checked(account, artifact, parsed_id, params["assertion_fingerprint"], changeset)
      end)
    else
      false -> {:error, :invalid_submission}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit(_, _, _, _), do: {:error, :invalid_submission}

  defp append_checked(account, artifact, assertion_id, submitted_fingerprint, changeset) do
    scope_sha256 = artifact["scope_content_sha256"]
    release_id = artifact["release"]["release_id"]

    case checked_context(account, artifact, assertion_id, submitted_fingerprint) do
      {:ok, live_account, grant, row} ->
        changeset
        |> Ecto.Changeset.change(%{
          account_id: live_account.id,
          grant_id: grant.id,
          assertion_id: row.id,
          scope_sha256: scope_sha256,
          release_id: release_id,
          assertion_fingerprint: submitted_fingerprint,
          inserted_at: DateTime.utc_now()
        })
        |> Repo.insert()
        |> case do
          {:ok, judgment} -> judgment
          {:error, reason} -> Repo.rollback(reason)
        end

      _ ->
        Repo.rollback(:stale_or_unauthorized)
    end
  end

  defp checked_context(account, artifact, assertion_id, submitted_fingerprint) do
    scope_sha256 = artifact["scope_content_sha256"]
    release_id = artifact["release"]["release_id"]

    with %Account{} = live_account <- active_account_locked(account),
         %Grant{} = grant <- active_grant_locked(account.id, scope_sha256),
         ^release_id <- selected_release_id_locked(),
         %WorkRelation{} = row <- relation_locked(assertion_id),
         %{} = candidate <- Enum.find(candidates(artifact), &matches?(&1, row)),
         true <- fingerprint(candidate) == submitted_fingerprint do
      {:ok, live_account, grant, row}
    else
      _ -> {:error, :stale_or_unauthorized}
    end
  end

  defp active_account_locked(account) do
    from(a in Account,
      where: a.id == ^account.id and a.active and a.session_epoch == ^account.session_epoch,
      lock: "FOR SHARE"
    )
    |> Repo.one()
  end

  defp active_grant_locked(account_id, scope_sha256) do
    from(g in Grant,
      where:
        g.account_id == ^account_id and g.scope_sha256 == ^scope_sha256 and
          g.capability == "relation_review" and is_nil(g.revoked_at),
      lock: "FOR SHARE"
    )
    |> Repo.one()
  end

  defp relation_locked(assertion_id) do
    from(r in WorkRelation, where: r.id == ^assertion_id, lock: "FOR SHARE")
    |> Repo.one()
  end

  defp matching_cases(rows, candidates) do
    Enum.flat_map(rows, fn row ->
      case Enum.find(candidates, &matches?(&1, row)) do
        nil -> []
        candidate -> [%{id: row.id, candidate: candidate}]
      end
    end)
  end

  defp judgment_changeset(params) do
    attrs =
      Map.take(params, ~w(judgment rationale source_references))
      |> Map.new(fn {key, value} ->
        {key, if(is_binary(value), do: String.trim(value), else: value)}
      end)

    Judgment.changeset(%Judgment{}, attrs)
  end

  defp candidates(artifact) do
    admitted =
      for edge <- artifact["relations"],
          assertion <- edge["assertions"],
          assertion["review_status"] == "needs_review" do
        candidate(edge, assertion)
      end

    separate =
      for review_case <- artifact["review_cases"] do
        candidate(review_case, review_case["assertion"])
      end

    admitted ++ separate
  end

  defp candidate(edge, assertion) do
    %{
      source_work_id: edge["source_work_id"],
      target_work_id: edge["target_work_id"],
      relation: edge["relation"],
      assertion: assertion
    }
  end

  defp matches?(candidate, row) do
    row.source_work_id == candidate.source_work_id and
      row.target_work_id == candidate.target_work_id and
      row.relation == candidate.relation and
      assertion_payload(row) == candidate.assertion
  end

  defp assertion_payload(row) do
    %{
      "method" => row.method,
      "confidence" => row.confidence,
      "scope" => row.scope,
      "target_urn" => row.target_urn,
      "evidence" => row.evidence || %{},
      "evidence_sha256" => ScopeArtifact.digest(row.evidence || %{}),
      "review_status" => row.review_status,
      "review_reason" => row.review_reason
    }
  end

  defp fingerprint(candidate) do
    ScopeArtifact.digest(%{
      "source_work_id" => candidate.source_work_id,
      "target_work_id" => candidate.target_work_id,
      "relation" => candidate.relation,
      "assertion" => candidate.assertion
    })
  end

  defp permitted_scope(artifact, scopes) do
    if artifact["scope_content_sha256"] in scopes,
      do: :ok,
      else: {:error, :unavailable_scope}
  end

  defp selected_release(artifact) do
    if Release.current_id() == artifact["release"]["release_id"],
      do: :ok,
      else: {:error, :stale_release}
  end

  defp selected_release_id_locked do
    from(selection in Selection,
      join: release in ReleaseSchema,
      on: release.id == selection.release_id,
      where: selection.id == 1,
      select: release.release_id,
      lock: "FOR SHARE"
    )
    |> Repo.one()
  end

  defp own_judgments(account_id, assertion_id, scope_sha256, release_id, fingerprint) do
    from(j in Judgment,
      where:
        j.account_id == ^account_id and j.assertion_id == ^assertion_id and
          j.scope_sha256 == ^scope_sha256 and j.release_id == ^release_id and
          j.assertion_fingerprint == ^fingerprint,
      order_by: [desc: j.inserted_at, desc: j.id]
    )
    |> Repo.all()
  end

  defp quotation_examples(row, bake_id) do
    pair_filter = quote_pair_filter(row)

    from(q in Quotation,
      join: a in Text,
      on: a.id == q.a_text_id,
      join: b in Text,
      on: b.id == q.b_text_id,
      where:
        q.bake_id == ^bake_id and a.source_id == "cbeta" and a.witness_id == "T" and
          b.source_id == "cbeta" and b.witness_id == "T",
      where: ^pair_filter,
      order_by: [desc: q.length, asc: q.id],
      limit: 3,
      select: %{
        text: q.text,
        text_sha256: q.text_sha256,
        a_work_id: q.a_work_id,
        a_urn: q.a_urn,
        b_urn: q.b_urn
      }
    )
    |> Repo.all()
    |> Enum.map(&present_quote(&1, row.source_work_id))
  end

  defp quote_pair_filter(row) do
    dynamic(
      [q],
      (q.a_work_id == ^row.source_work_id and q.b_work_id == ^row.target_work_id) or
        (q.b_work_id == ^row.source_work_id and q.a_work_id == ^row.target_work_id)
    )
  end

  defp present_quote(quote, source_work_id) do
    {source_urn, target_urn} =
      if quote.a_work_id == source_work_id,
        do: {quote.a_urn, quote.b_urn},
        else: {quote.b_urn, quote.a_urn}

    %{
      text: quote.text,
      text_sha256: quote.text_sha256,
      source_urn: source_urn,
      target_urn: target_urn
    }
  end

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}

  defp decode(bytes) do
    {:ok, ScopeArtifact.decode!(bytes)}
  rescue
    _ -> {:error, :invalid_scope_artifact}
  end
end
