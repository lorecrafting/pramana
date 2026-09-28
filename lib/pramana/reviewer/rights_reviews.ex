defmodule Pramana.Reviewer.RightsReviews do
  @moduledoc "Attributable, operation-specific rights assessments; no runtime permission changes."

  import Ecto.Query

  alias Pramana.Accounts.User
  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Release.Selection
  alias Pramana.Repo
  alias Pramana.Reviewer.Disposition
  alias Pramana.Reviewer.Grant
  alias Pramana.Reviewer.Reviews
  alias Pramana.Reviewer.RightsJudgment

  @form_keys ~w(_csrf_token decision rationale evidence_references scope_sha256 release_id item_fingerprint)

  @dila_glossaries [
    {"soothill-hodous", "Soothill–Hodous", "Preserve glossary provenance."},
    {"karashima-kumarajiva", "Karashima / Kumārajīva",
     "Limit to T0262 and preserve glossary provenance."},
    {"karashima-dharmaraksa", "Karashima / Dharmarakṣa",
     "Limit to T0263 and preserve glossary provenance."},
    {"karashima-lokaksema", "Karashima / Lokakṣema",
     "Limit to T0224 and preserve glossary provenance."},
    {"mahavyutpatti", "Mahāvyutpatti digital edition",
     "Preserve Sanskrit/Chinese provenance; assess the digital edition, not only the historical text."}
  ]

  @cbeta_items [
    %{
      "id" => "cbeta-local",
      "resource" => "CBETA Taishō Category A",
      "operations" => "1–2 · Local storage, index and search",
      "boundary" =>
        "Noncommercial use with notice and version; exact source and edition review required."
    },
    %{
      "id" => "cbeta-reader",
      "resource" => "CBETA Taishō Category A",
      "operations" => "8–10 · Reader display, bounded evidence and local evaluation retention",
      "boundary" =>
        "Noncommercial, attributed, versioned; use the smallest permitted verbatim excerpt."
    },
    %{
      "id" => "cbeta-embeddings",
      "resource" => "CBETA Taishō Category A",
      "operations" => "3 · Embeddings and derived retrieval",
      "boundary" => "Unresolved under current policy; no new use."
    },
    %{
      "id" => "cbeta-external",
      "resource" => "CBETA Taishō Category A",
      "operations" => "5 · Send source bytes to an external provider",
      "boundary" => "Unresolved under current policy; no provider transfer."
    },
    %{
      "id" => "cbeta-generation",
      "resource" => "CBETA Taishō Category A",
      "operations" => "7 · Local generation or translation",
      "boundary" => "Unresolved under current policy; no execution."
    }
  ]

  @dila_items (for {id, name, scope} <- @dila_glossaries,
                   operation <- [:local, :external] do
                 case operation do
                   :local ->
                     %{
                       "id" => "dila-#{id}-local",
                       "resource" => "DILA #{name}",
                       "operations" => "4 · Local English-to-Chinese query expansion",
                       "boundary" => "Conservative noncommercial baseline. #{scope}"
                     }

                   :external ->
                     %{
                       "id" => "dila-#{id}-external",
                       "resource" => "DILA #{name}",
                       "operations" => "6 · Send glossary bytes to an external provider",
                       "boundary" =>
                         "Unresolved under current policy; no provider transfer. #{scope}"
                     }
                 end
               end)

  @other_items [
    %{
      "id" => "patton-display",
      "resource" => "Patton scpub20/scpub35",
      "operations" => "8 · Attributed human English display",
      "boundary" => "CC0 copyright baseline; preserve SuttaCentral stakeholder norm."
    },
    %{
      "id" => "patton-ai",
      "resource" => "Patton scpub20/scpub35",
      "operations" => "3, 4, 7 · AI-derived use or model context",
      "boundary" => "Stakeholder clearance required; no new AI use."
    },
    %{
      "id" => "mitra-historical",
      "resource" => "Historical MITRA English",
      "operations" => "7–9 · Regeneration, reader evidence or export",
      "boundary" => "Internal historical inspection only; excluded from pilot execution."
    },
    %{
      "id" => "all-export",
      "resource" => "All resources",
      "operations" => "11 · Public redistribution or artifact",
      "boundary" => "Excluded by project policy; review exact artifact before any policy change."
    },
    %{
      "id" => "all-commercial",
      "resource" => "All resources",
      "operations" => "12 · Commercial use",
      "boundary" => "Excluded for noncommercial sources; no commercial pilot."
    }
  ]

  @items @cbeta_items ++ @dila_items ++ @other_items

  def list(artifact, scopes, account_id) do
    with :ok <- Reviews.check_scope(artifact, scopes) do
      latest =
        from(j in RightsJudgment,
          where:
            j.account_id == ^account_id and j.scope_sha256 == ^artifact["scope_content_sha256"],
          order_by: [desc: j.inserted_at, desc: j.id]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.item_id)

      {:ok,
       Enum.map(@items, fn item ->
         fingerprint = ScopeArtifact.digest(item)

         judgment =
           latest |> Map.get(item["id"], []) |> Enum.find(&(&1.item_fingerprint == fingerprint))

         %{item: item, fingerprint: fingerprint, judgment: judgment}
       end)}
    end
  end

  def get(artifact, scopes, account_id, item_id) do
    with :ok <- Reviews.check_scope(artifact, scopes),
         %{} = item <- Enum.find(@items, &(&1["id"] == item_id)) do
      fingerprint = ScopeArtifact.digest(item)

      history =
        from(j in RightsJudgment,
          where:
            j.account_id == ^account_id and j.scope_sha256 == ^artifact["scope_content_sha256"] and
              j.release_id == ^artifact["release"]["release_id"] and j.item_id == ^item_id and
              j.item_fingerprint == ^fingerprint,
          order_by: [desc: j.inserted_at, desc: j.id]
        )
        |> Repo.all()

      {:ok,
       %{
         item: item,
         fingerprint: fingerprint,
         scope_sha256: artifact["scope_content_sha256"],
         release_id: artifact["release"]["release_id"],
         judgments: history
       }}
    else
      _ -> {:error, :unavailable_item}
    end
  end

  def submit(%User{} = account, artifact, item_id, params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @form_keys)),
         true <- params["scope_sha256"] == artifact["scope_content_sha256"],
         true <- params["release_id"] == artifact["release"]["release_id"],
         %{} = item <- Enum.find(@items, &(&1["id"] == item_id)),
         fingerprint <- ScopeArtifact.digest(item),
         true <- params["item_fingerprint"] == fingerprint,
         changeset <- RightsJudgment.changeset(%RightsJudgment{}, clean_params(params)),
         true <- changeset.valid? do
      attrs = Ecto.Changeset.apply_changes(changeset)

      case Repo.insert_all(
             RightsJudgment,
             authorized_insert(account, artifact, item, fingerprint, attrs),
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

  defp authorized_insert(account, artifact, item, fingerprint, attrs) do
    scope = artifact["scope_content_sha256"]
    release_id = artifact["release"]["release_id"]

    from a in User,
      join: g in Grant,
      on:
        g.account_id == a.id and g.scope_sha256 == ^scope and
          g.capability == "rights_signoff" and is_nil(g.revoked_at),
      join: s in Selection,
      on: s.id == 1,
      join: release in ReleaseSchema,
      on: release.id == s.release_id and release.release_id == ^release_id,
      where:
        a.id == ^account.id and not is_nil(a.confirmed_at) and
          not exists(
            from d in Disposition,
              where: d.scope_sha256 == ^scope and d.disposition == "supported",
              select: 1
          ),
      select: %{
        id: type(^Ecto.UUID.generate(), Ecto.UUID),
        account_id: a.id,
        grant_id: g.id,
        scope_sha256: ^scope,
        release_id: release.release_id,
        item_id: ^item["id"],
        item_fingerprint: ^fingerprint,
        policy_snapshot: ^item,
        decision: ^attrs.decision,
        rationale: ^attrs.rationale,
        evidence_references: ^attrs.evidence_references,
        inserted_at: ^DateTime.utc_now()
      }
  end

  defp clean_params(params) do
    params
    |> Map.take(~w(decision rationale evidence_references))
    |> Map.new(fn {key, value} ->
      {key, if(is_binary(value), do: String.trim(value), else: value)}
    end)
  end
end
