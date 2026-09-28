defmodule Pramana.Repo.Migrations.CreateTextParallels do
  use Ecto.Migration

  @moduledoc """
  Hand-curated parallels between texts, from SuttaCentral's `sc-data`.

  388,074 typed relations across Chinese, Pāli, Sanskrit and Tibetan, built by scholars
  over years. `CLAUDE.md` invariant #5 says deterministic before probabilistic — this is
  existing scholarship, and ingesting it beats rediscovering a worse version of it with
  embedding similarity.

  Stored at SuttaCentral's own ids (`sa1`, `mn10`, `t792`), verbatim, because those are
  the field's identifiers and inventing our own would be the same mistake as inventing
  citation ids. Where a side can be anchored to a Taishō page we also store the resolved
  URN, so a parallel points at a passage a reader can actually open.
  """

  def change do
    create table(:text_parallels) do
      # SuttaCentral uids, kept as printed.
      add :source_uid, :string, null: false
      add :target_uid, :string, null: false

      # full | resembling | sections | mentions | retells — SuttaCentral's own typing of
      # how strong the relation is. Kept distinct because "a full parallel" and "mentions
      # in passing" are different claims and must not be flattened into "related".
      add :relation, :string, null: false

      # SuttaCentral marks an indirect/partial reference by prefixing `~`.
      add :partial, :boolean, null: false, default: false

      # Resolved into OUR corpus where possible. Null means the text is real scholarship
      # about something we have not ingested — a Pāli sutta, say — which is information,
      # not an error.
      add :source_urn, :string
      add :target_urn, :string
      add :source_work_id, :string
      add :target_work_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:text_parallels, [:source_uid, :target_uid, :relation])
    create index(:text_parallels, [:source_uid])
    create index(:text_parallels, [:target_uid])
    create index(:text_parallels, [:source_work_id])
    create index(:text_parallels, [:target_work_id])
    create index(:text_parallels, [:relation])

    create constraint(:text_parallels, :text_parallels_relation_known,
             check: "relation IN ('full','resembling','sections','mentions','retells')"
           )

    create table(:text_anchors, primary_key: false) do
      # SuttaCentral uid -> the Taishō passage it names. Separated from the parallels
      # themselves because one anchor serves every parallel touching that text.
      add :uid, :string, primary_key: true
      add :work_id, :string
      add :urn, :string
      add :acronym, :string
      add :volpage, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:text_anchors, [:work_id])
    create index(:text_anchors, [:urn])
  end
end
