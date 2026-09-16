defmodule Pramana.Repo.Migrations.CreateGlossaryAnchors do
  @moduledoc """
  Where a gloss meets the corpus.

  Karashima's glossaries cite the passages a gloss rests on — `T.262` at `59b7`, with the
  Chinese quotation and the Sanskrit witness beside it — and those are Taishō addresses
  this corpus already holds. Resolving them turns a dictionary entry from a claim you take
  on trust into one you can open, read and byte-verify like any other citation here.

  ## Why a table and not `meta`

  The citations already sit in `glossary_entries.meta` as printed strings, which answers
  "what does this gloss rest on" and cannot answer the question worth asking: **which
  glosses cite this line?** That is a join, and a join needs a row.

  It also makes the resolution auditable. 29,890 citations across four works do not all
  resolve, and a jsonb array has nowhere to record which failed and why.

  ## `status`, and why absence is a first-class value rather than a failure

    * `resolved` — the address names a line this bake holds, and `urn` is it.
    * `absent` — **Karashima looked and recorded that nothing corresponds.** He writes
      these as `Z. not found at 68c1`: a real address in Dharmarakṣa's translation where
      the term Kumārajīva used simply is not. The `urn` is set, because the place is real;
      the claim is about what is not there.
    * `unresolved` — the address parsed and this bake has no such line, or it did not
      parse at all. Counted, never silently dropped.

  The middle one is the reason this table exists in this shape. `docs/PLAN.md` says zero
  results are the highest-value signal a corpus project has, and 4,347 of these citations
  are a scholar having checked a specific line and found the word absent — attested
  absence, which is ordinarily the most expensive kind of evidence to get.
  """

  use Ecto.Migration

  def change do
    create table(:glossary_anchors) do
      add :entry_id, references(:glossary_entries, on_delete: :delete_all), null: false
      add :work_id, :string
      add :urn, :string
      # As the glossary prints it — `T.262:59b7`. Kept beside the resolution so a
      # disagreement between the two is visible rather than lost in the rewrite.
      add :citation, :string, null: false
      add :status, :string, null: false
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # One row per (entry, citation) so a re-run replaces rather than accumulates.
    create unique_index(:glossary_anchors, [:entry_id, :citation])

    # THE QUESTION THIS TABLE EXISTS FOR: which glosses cite this line?
    create index(:glossary_anchors, [:urn])
    create index(:glossary_anchors, [:work_id])
    create index(:glossary_anchors, [:status])

    create constraint(:glossary_anchors, :glossary_anchor_status_known,
             check: "status in ('resolved', 'absent', 'unresolved')"
           )

    # A resolved or absent anchor names a place; an unresolved one is precisely the case
    # where it could not. Enforced rather than assumed, because a `resolved` row with no
    # URN would read as a working anchor to every consumer.
    create constraint(:glossary_anchors, :glossary_anchor_resolved_has_urn,
             check: "(status = 'unresolved') = (urn is null)"
           )
  end
end
