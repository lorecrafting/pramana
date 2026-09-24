defmodule Pramana.Repo.Migrations.CreateGlossaryEntries do
  @moduledoc """
  The translators' own glossaries: a term in Sanskrit, Tibetan, English and sometimes
  Chinese, tied to the text it was glossed in.

  84000 publishes one with every translation — 58,820 entries across the Kangyur it has
  published, 16,767 distinct Sanskrit terms and 25,526 Tibetan ones. It is the closest
  thing this corpus has to the Skt–Tib–Chi anchors Phase 5 asks for, and it arrives
  attested rather than asserted.

  ## Separate from `glossary_terms`, which is a different thing

  `glossary_terms` is a **policy**: 376 hand-pinned renderings for one Chinese commentary,
  with rejected forms and a reading status, answering "what should this be called". This
  is **evidence**: what a named translator called a term in a named text, with the
  edition's own note on where each form comes from. Merging them would put a claim and a
  decision in one row and lose which was which.

  ## Attestation is a column, because most of the Sanskrit is not attested

  84000 marks each term with how it is known, and the distribution is the reason this
  table exists in this shape:

      Tibetan   attestedSource       23,252    the Tibetan text says this
      Sanskrit  sourceUnspecified    22,442    reconstructed; no Sanskrit witness says it
      Sanskrit  attestedSource          575    a Sanskrit witness does say it
      Sanskrit  attestedDictionary      472    a lexicon says it
      Chinese   attestedSource          281

  **The Sanskrit is overwhelmingly a reconstruction.** Storing `yūpa` beside the Tibetan
  with no further qualification would present a scholarly inference as a quotation from a
  Sanskrit text — the same class of error as presenting a Japanese commentary as an Indian
  sūtra, which is what `composition_origin` exists to prevent. So each language carries
  its own attestation and a caller can ask for only what is attested in a source.
  """

  use Ecto.Migration

  def up do
    create table(:glossary_entries) do
      add :source_id, references(:sources, type: :string, on_delete: :restrict), null: false
      add :work_id, references(:works, type: :string, on_delete: :delete_all)

      # 84000's own id for the gloss, which makes a re-ingest idempotent and lets a
      # reader find the entry in the published TEI.
      add :gloss_id, :string, null: false

      # `:text`, not `:string`, because a "term" here is not always a word. 84000 glosses
      # whole clauses — the longest English is 263 characters and the longest Wylie 258 —
      # and a 255-char cap would reject them at insert with nothing to say about which.
      add :english, :text
      add :english_alternatives, {:array, :text}, default: []

      add :sanskrit, :text
      add :sanskrit_attestation, :string
      add :tibetan, :text
      add :wylie, :text
      add :tibetan_attestation, :string
      add :chinese, :text
      add :chinese_attestation, :string
      add :pali, :text

      add :definition, :text
      add :meta, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:glossary_entries, [:source_id, :gloss_id])

    # The joins this table exists for: Sanskrit is the pivot between traditions, Tibetan
    # is what a reader of the Kangyur has in front of them, and work_id scopes a glossary
    # to the text it belongs to. Hashed, because a btree over a `text` column refuses a
    # value past a third of a page and these are terms, not documents.
    execute "CREATE INDEX glossary_entries_sanskrit_index ON glossary_entries USING hash (sanskrit)"
    execute "CREATE INDEX glossary_entries_tibetan_index ON glossary_entries USING hash (tibetan)"
    create index(:glossary_entries, [:work_id])

    create constraint(:glossary_entries, :glossary_attestation_known,
             check: """
             (sanskrit_attestation IS NULL OR sanskrit_attestation IN
               ('source','dictionary','other','unspecified'))
             AND (tibetan_attestation IS NULL OR tibetan_attestation IN
               ('source','dictionary','other','unspecified'))
             AND (chinese_attestation IS NULL OR chinese_attestation IN
               ('source','dictionary','other','unspecified'))
             """
           )

    # An entry with no term in any language says nothing. Cheaper to refuse than to
    # explain later why the glossary has empty rows in it.
    create constraint(:glossary_entries, :glossary_entry_has_a_term,
             check: "sanskrit IS NOT NULL OR tibetan IS NOT NULL OR english IS NOT NULL"
           )
  end

  def down do
    drop table(:glossary_entries)
  end
end
