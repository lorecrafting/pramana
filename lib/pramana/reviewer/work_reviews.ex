defmodule Pramana.Reviewer.WorkReviews do
  @moduledoc "Source-work recommendations bound to the mounted pilot scope and live reviewer grant."

  import Ecto.Query

  alias Pramana.Accounts.User
  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Corpus.Work
  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Release.Selection
  alias Pramana.Repo
  alias Pramana.Reviewer.Disposition
  alias Pramana.Reviewer.Grant
  alias Pramana.Reviewer.Reviews
  alias Pramana.Reviewer.WorkJudgment

  @form_keys ~w(_csrf_token judgment rationale source_references scope_sha256 release_id work_fingerprint)

  def list(artifact, scopes, account_id) do
    with :ok <- Reviews.check_scope(artifact, scopes) do
      works = manifest(artifact)
      ids = Enum.map(works, & &1["work_id"])

      rows =
        from(w in Work, where: w.id in ^ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      latest =
        from(j in WorkJudgment,
          where:
            j.account_id == ^account_id and j.scope_sha256 == ^artifact["scope_content_sha256"],
          order_by: [desc: j.inserted_at, desc: j.id]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.work_id)

      with {:ok, snapshots} <- current_snapshots(works, rows) do
        {:ok,
         Enum.map(snapshots, fn {work, snapshot} ->
           fingerprint = ScopeArtifact.digest(snapshot)

           judgment =
             latest
             |> Map.get(work["work_id"], [])
             |> Enum.find(&(&1.work_fingerprint == fingerprint))

           %{work: work, fingerprint: fingerprint, judgment: judgment}
         end)
         |> Enum.sort_by(& &1.work["work_id"])}
      end
    end
  end

  def get(artifact, scopes, account_id, work_id) do
    with :ok <- Reviews.check_scope(artifact, scopes),
         %{} = work <- Enum.find(manifest(artifact), &(&1["work_id"] == work_id)),
         %Work{} = row <- Repo.get(Work, work_id),
         {:ok, snapshot} <- current_snapshot(work, row) do
      fingerprint = ScopeArtifact.digest(snapshot)

      history =
        from(j in WorkJudgment,
          where:
            j.account_id == ^account_id and j.scope_sha256 == ^artifact["scope_content_sha256"] and
              j.release_id == ^artifact["release"]["release_id"] and j.work_id == ^work_id and
              j.work_fingerprint == ^fingerprint,
          order_by: [desc: j.inserted_at, desc: j.id]
        )
        |> Repo.all()

      {:ok,
       %{
         work: work,
         row: row,
         snapshot: snapshot,
         fingerprint: fingerprint,
         scope_sha256: artifact["scope_content_sha256"],
         release_id: artifact["release"]["release_id"],
         judgments: history
       }}
    else
      _ -> {:error, :unavailable_work}
    end
  end

  def submit(%User{} = account, artifact, work_id, params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @form_keys)),
         true <- params["scope_sha256"] == artifact["scope_content_sha256"],
         true <- params["release_id"] == artifact["release"]["release_id"],
         %{} = work <- Enum.find(manifest(artifact), &(&1["work_id"] == work_id)),
         {:ok, snapshot} <- current_snapshot(work, Repo.get(Work, work_id)),
         fingerprint <- ScopeArtifact.digest(snapshot),
         :ok <- check_fingerprint(params["work_fingerprint"], fingerprint),
         changeset <- WorkJudgment.changeset(%WorkJudgment{}, clean_params(params)),
         true <- changeset.valid? do
      attrs = Ecto.Changeset.apply_changes(changeset)

      case Repo.insert_all(
             WorkJudgment,
             authorized_insert(account, artifact, work, snapshot, fingerprint, attrs),
             returning: true
           ) do
        {1, [judgment]} -> {:ok, judgment}
        {0, []} -> {:error, :stale_or_unauthorized}
      end
    else
      false -> {:error, :invalid_submission}
      nil -> {:error, :invalid_submission}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit(_, _, _, _), do: {:error, :invalid_submission}

  defp authorized_insert(account, artifact, work, snapshot, fingerprint, attrs) do
    scope = artifact["scope_content_sha256"]
    release_id = artifact["release"]["release_id"]
    metadata = snapshot["work_metadata"]

    from w in Work,
      join: a in User,
      on: a.id == ^account.id and not is_nil(a.confirmed_at),
      join: g in Grant,
      on:
        g.account_id == a.id and g.scope_sha256 == ^scope and
          g.capability == "relation_review" and is_nil(g.revoked_at),
      join: s in Selection,
      on: s.id == 1,
      join: release in ReleaseSchema,
      on: release.id == s.release_id and release.release_id == ^release_id,
      where: [id: ^work["work_id"], title: ^work["title"], text_role: ^work["text_role"]],
      where:
        fragment(
          "ROW(?, ?, ?, ?) IS NOT DISTINCT FROM ROW(?, ?, ?, ?)",
          w.division,
          w.attributed_author,
          w.composition_origin,
          w.attribution_confidence,
          ^metadata["division"],
          ^metadata["attributed_author"],
          ^metadata["composition_origin"],
          ^metadata["attribution_confidence"]
        ),
      where:
        not exists(
          from d in Disposition,
            where: d.scope_sha256 == ^scope and d.disposition == "supported",
            select: 1
        ),
      select: %{
        id: type(^Ecto.UUID.generate(), Ecto.UUID),
        account_id: a.id,
        grant_id: g.id,
        work_id: w.id,
        scope_sha256: ^scope,
        release_id: release.release_id,
        work_fingerprint: ^fingerprint,
        work_snapshot: ^snapshot,
        judgment: ^attrs.judgment,
        rationale: ^attrs.rationale,
        source_references: ^attrs.source_references,
        inserted_at: ^DateTime.utc_now()
      }
  end

  defp clean_params(params) do
    params
    |> Map.take(~w(judgment rationale source_references))
    |> Map.new(fn {key, value} ->
      {key, if(is_binary(value), do: String.trim(value), else: value)}
    end)
  end

  defp current_snapshots(works, rows) do
    Enum.reduce_while(works, {:ok, []}, fn work, {:ok, acc} ->
      case current_snapshot(work, Map.get(rows, work["work_id"])) do
        {:ok, snapshot} -> {:cont, {:ok, [{work, snapshot} | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  defp current_snapshot(work, %Work{} = row) do
    if row.title == work["title"] and row.text_role == work["text_role"] and
         (not Map.has_key?(work, "division") or row.division == work["division"]) do
      {:ok,
       %{
         "scope_work" => work,
         "work_metadata" => %{
           "division" => row.division,
           "attributed_author" => row.attributed_author,
           "composition_origin" => row.composition_origin,
           "attribution_confidence" => row.attribution_confidence
         }
       }}
    else
      {:error, :stale_or_unauthorized}
    end
  end

  defp current_snapshot(_, _), do: {:error, :stale_or_unauthorized}

  defp check_fingerprint(value, value), do: :ok
  defp check_fingerprint(_, _), do: {:error, :stale_or_unauthorized}

  defp manifest(artifact) do
    answer_works =
      artifact["works"]
      |> Map.new(fn work ->
        {work["work_id"], Map.merge(work, %{"answer_scope" => true, "review_target" => false})}
      end)

    Enum.reduce(artifact["review_cases"], answer_works, fn review_case, works ->
      id = review_case["target_work_id"]

      Map.update(
        works,
        id,
        %{
          "work_id" => id,
          "title" => review_case["target_title"],
          "text_role" => review_case["target_text_role"],
          "source" => review_case["target_source"],
          "witness" => review_case["target_witness"],
          "answer_scope" => false,
          "review_target" => true
        },
        &Map.put(&1, "review_target", true)
      )
    end)
    |> Map.values()
    |> Enum.sort_by(& &1["work_id"])
  end
end
