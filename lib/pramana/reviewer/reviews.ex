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
  alias Pramana.Reviewer.Disposition
  alias Pramana.Reviewer.Grant
  alias Pramana.Reviewer.Judgment

  @form_keys ~w(_csrf_token judgment rationale source_references scope_sha256 release_id assertion_fingerprint)

  @doc "Loads the operator-mounted scope artifact. A missing or invalid file exposes no cases."
  def configured_scope do
    case System.get_env("PRAMANA_REVIEW_SCOPE_PATH") do
      path when is_binary(path) and path != "" ->
        with {:ok, artifact} <- load_scope(path),
             false <- invalidated?(artifact["scope_content_sha256"]) do
          {:ok, artifact}
        else
          true -> {:error, :invalidated_scope}
          error -> error
        end

      _ ->
        {:error, :scope_not_configured}
    end
  end

  @doc "Validates one saved scope for operator inspection, including past scopes."
  def load_scope(path) when is_binary(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, artifact} <- decode(bytes),
         :ok <- ScopeArtifact.validate(artifact) do
      {:ok, artifact}
    else
      _ -> {:error, :invalid_scope_artifact}
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
         {:ok, case_info} <- exact_candidate(artifact, row),
         %Work{} = source <- Repo.get(Work, row.source_work_id),
         %Work{} = target <- Repo.get(Work, row.target_work_id) do
      candidate = case_info.candidate

      {:ok,
       %{
         row: row,
         candidate: candidate,
         fingerprint: case_info.fingerprint,
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
             case_info.fingerprint
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
      append_checked(account, artifact, parsed_id, params["assertion_fingerprint"], changeset)
    else
      false -> {:error, :invalid_submission}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit(_, _, _, _), do: {:error, :invalid_submission}

  defp append_checked(account, artifact, assertion_id, submitted_fingerprint, changeset) do
    with %WorkRelation{} = row <- Repo.get(WorkRelation, assertion_id),
         {:ok, case_info} <- exact_candidate(artifact, row),
         true <- case_info.fingerprint == submitted_fingerprint do
      attrs = Ecto.Changeset.apply_changes(changeset)

      case Repo.insert_all(
             Judgment,
             authorized_insert(account, artifact, row.id, case_info.candidate, attrs),
             returning: true
           ) do
        {1, [judgment]} -> {:ok, judgment}
        {0, []} -> {:error, :stale_or_unauthorized}
      end
    else
      _ -> {:error, :stale_or_unauthorized}
    end
  end

  defp authorized_insert(account, artifact, assertion_id, candidate, attrs) do
    scope_sha256 = artifact["scope_content_sha256"]
    release_id = artifact["release"]["release_id"]

    query =
      account
      |> authorized_rows(scope_sha256, release_id)
      |> matching_relation(assertion_id, candidate)
      |> matching_assertion(candidate.assertion)

    from [r, a, g, _s, release] in query,
      select: %{
        id: type(^Ecto.UUID.generate(), Ecto.UUID),
        account_id: a.id,
        grant_id: g.id,
        assertion_id: r.id,
        scope_sha256: ^scope_sha256,
        release_id: release.release_id,
        assertion_fingerprint: ^fingerprint(candidate),
        judgment: ^attrs.judgment,
        rationale: ^attrs.rationale,
        source_references: ^attrs.source_references,
        inserted_at: ^DateTime.utc_now()
      }
  end

  defp authorized_rows(account, scope_sha256, release_id) do
    from r in WorkRelation,
      join: a in Account,
      on: a.id == ^account.id and a.active and a.session_epoch == ^account.session_epoch,
      join: g in Grant,
      on:
        g.account_id == a.id and g.scope_sha256 == ^scope_sha256 and
          g.capability == "relation_review" and is_nil(g.revoked_at),
      join: s in Selection,
      on: s.id == 1,
      join: release in ReleaseSchema,
      on: release.id == s.release_id and release.release_id == ^release_id
  end

  defp matching_relation(query, assertion_id, candidate) do
    from [r] in query,
      where:
        r.id == ^assertion_id and r.source_work_id == ^candidate.source_work_id and
          r.target_work_id == ^candidate.target_work_id and
          r.relation == ^candidate.relation and r.review_status == "needs_review"
  end

  defp matching_assertion(query, assertion) do
    target_urn = assertion["target_urn"]

    target_filter =
      if is_nil(target_urn),
        do: dynamic([r], is_nil(r.target_urn)),
        else: dynamic([r], r.target_urn == ^target_urn)

    from [r] in query,
      where:
        r.method == ^assertion["method"] and r.confidence == ^assertion["confidence"] and
          r.scope == ^assertion["scope"] and r.review_reason == ^assertion["review_reason"] and
          fragment("COALESCE(?, '{}'::jsonb) = ?", r.evidence, ^assertion["evidence"]),
      where: ^target_filter
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
    ScopeArtifact.digest(assertion_snapshot(candidate))
  end

  @doc "Returns the exact source/target assertion content bound to a review fingerprint."
  def assertion_snapshot(candidate) do
    %{
      "source_work_id" => candidate.source_work_id,
      "target_work_id" => candidate.target_work_id,
      "relation" => candidate.relation,
      "assertion" => candidate.assertion
    }
  end

  @doc "Returns the current stored claim, even when it no longer matches a saved scope."
  def live_snapshot(%WorkRelation{} = row) do
    %{
      "source_work_id" => row.source_work_id,
      "target_work_id" => row.target_work_id,
      "relation" => row.relation,
      "assertion" => assertion_payload(row)
    }
  end

  @doc "Matches a live relation to the exact assertion recorded in one scope artifact."
  def exact_candidate(artifact, %WorkRelation{} = row) do
    case Enum.find(candidates(artifact), &matches?(&1, row)) do
      nil -> {:error, :unavailable_case}
      candidate -> {:ok, %{candidate: candidate, fingerprint: fingerprint(candidate)}}
    end
  end

  defp permitted_scope(artifact, scopes) do
    if artifact["scope_content_sha256"] in scopes,
      do: :ok,
      else: {:error, :unavailable_scope}
  end

  defp invalidated?(scope_sha256) do
    Repo.exists?(
      from d in Disposition,
        where: d.scope_sha256 == ^scope_sha256 and d.disposition == "supported"
    )
  end

  defp selected_release(artifact) do
    if Release.current_id() == artifact["release"]["release_id"],
      do: :ok,
      else: {:error, :stale_release}
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
        a_char_start: q.a_char_start,
        a_char_end: q.a_char_end,
        b_urn: q.b_urn,
        b_char_start: q.b_char_start,
        b_char_end: q.b_char_end
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
    {source_urn, source_start, source_end, target_urn, target_start, target_end} =
      if quote.a_work_id == source_work_id,
        do:
          {quote.a_urn, quote.a_char_start, quote.a_char_end, quote.b_urn, quote.b_char_start,
           quote.b_char_end},
        else:
          {quote.b_urn, quote.b_char_start, quote.b_char_end, quote.a_urn, quote.a_char_start,
           quote.a_char_end}

    %{
      text: quote.text,
      text_sha256: quote.text_sha256,
      source_urn: source_urn,
      source_start: source_start,
      source_end: source_end,
      target_urn: target_urn,
      target_start: target_start,
      target_end: target_end
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
