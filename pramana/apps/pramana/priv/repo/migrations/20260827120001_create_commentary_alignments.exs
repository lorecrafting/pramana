defmodule Pramana.Repo.Migrations.CreateCommentaryAlignments do
  @moduledoc """
  Which line of a commentary explains which line of its root text.

  `work_relations` can say *T1789 comments on T0670*. That is the easy half and only
  mildly useful. This is the other half — **passage to passage** — which is what
  `docs/COMMENTARY.md` called "the single highest-value piece of this feature" and what
  the roadmap has carried as Phase 6 lemma-and-gloss (科文) parsing since the beginning.

  ## Why this is a table and not `work_relations` with a `target_urn`

  `work_relations` has one URN column, on the target side. A passage alignment needs
  **both** ends addressed — this commentary line explains that root line — and there is no
  column for the commentary end. Widening the relation table would also mean its unique
  index, which exists to hold one assertion per (source, target, relation, method), would
  now be holding thousands of rows per pair. Those are two different cardinalities and one
  table cannot be both.

  ## Why it is not `quotations` either

  The evidence is the same shape — identical characters — and the claim is not.
  `quotations` records that two works share a string and says explicitly that **neither
  end is the source**, because character identity cannot tell you who quoted whom. Here
  direction is known, and it does not come from the characters: it comes from the
  `comments_on` relation, which was asserted on other grounds. Storing a directional claim
  in a table whose whole doctrine is that it holds no direction is how a table starts
  meaning two things.

  The scan parameters differ too. `quotations` is a global scan at a 20-character floor.
  A 科文 lemma has a median length of **10** characters, and a floor that low is only safe
  because the search is restricted to one asserted pair.

  ## The uniqueness rule, which is what makes this deterministic

  A lemma anchors to a root position only when its 8-character window occurs **exactly
  once** in the root. A commentary quoting 云何為二 tells you nothing about where in the
  root it is looking; a window that occurs once tells you exactly. This is a property of
  the root text, not a similarity threshold, and it is why no model is involved.

  Measured over the four best-attested pairs: 70–78% of the root's printed lines carry at
  least one anchor, 52–61% of the root is quoted verbatim, and 88–95% of consecutive
  anchors move forward through the root — a commentary walking its text in order, which is
  what 科文 structure predicts. Against roots the same commentaries do **not** explain,
  those numbers are 0.5–1.9%, 0.5–0.8%, and ~50%, which is chance.
  """

  use Ecto.Migration

  def change do
    create table(:commentary_alignments) do
      # The lemma itself, stored rather than only addressed, for the reason `quotations`
      # gives: offsets alone become unreadable after a re-bake and unverifiable before it.
      add :lemma, :text, null: false
      add :lemma_sha256, :string, null: false
      add :length, :integer, null: false

      add :commentary_text_id, references(:texts, on_delete: :delete_all), null: false
      add :commentary_work_id, :string, null: false
      add :commentary_urn, :string, null: false
      add :commentary_char_start, :integer, null: false
      add :commentary_char_end, :integer, null: false

      add :root_text_id, references(:texts, on_delete: :delete_all), null: false
      add :root_work_id, :string, null: false
      add :root_urn, :string, null: false
      add :root_char_start, :integer, null: false
      add :root_char_end, :integer, null: false

      # `lemma_match` today. The column exists because an LLM will eventually propose
      # alignments for the paraphrasing commentaries this method cannot reach, and
      # invariant #5 requires the difference to survive into the answer.
      add :method, :string, null: false
      add :confidence, :string, null: false

      add :bake_id, :string
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # The same lemma found at the same place twice is one fact.
    create unique_index(:commentary_alignments, [
             :commentary_text_id,
             :commentary_char_start,
             :root_text_id,
             :root_char_start
           ])

    # The reading query is "what explains THIS line", so the root URN is the hot path.
    create index(:commentary_alignments, [:root_urn])
    create index(:commentary_alignments, [:root_work_id])
    create index(:commentary_alignments, [:commentary_work_id])
    create index(:commentary_alignments, [:commentary_urn])

    # A 科文 lemma runs about ten characters and the scan window is eight. Below that a
    # "match" is a common phrase, not a citation. The floor lives in the database as well
    # as in the scanner so a later loader cannot quietly relax it.
    create constraint(:commentary_alignments, :lemma_is_long_enough, check: "length >= 8")

    # A commentary explaining itself is not an alignment.
    create constraint(:commentary_alignments, :alignment_spans_two_texts,
             check: "commentary_text_id <> root_text_id"
           )

    create constraint(:commentary_alignments, :alignment_method_is_known,
             check: "method IN ('lemma_match', 'manifest', 'llm')"
           )

    create constraint(:commentary_alignments, :alignment_confidence_is_known,
             check: "confidence IN ('certain', 'probable', 'uncertain')"
           )
  end
end
