defmodule Pramana.Repo.Migrations.AddSharedTextMethod do
  use Ecto.Migration

  @moduledoc """
  Adds `shared_text` as a relation method.

  A commentary's root is usually its dominant shared-text partner among works whose
  `text_role` is `root`: 大智度論 shares 654 distinct passages with 摩訶般若波羅蜜經 and 12
  with its next partner, and no title rule can find that pair because the commentary
  never names the sūtra. See `Pramana.Quotations.Roots`.

  It is not `lemma_match`, and the distinction is the reason for the new value rather
  than a preference. `lemma_match` names what `commentary_alignments` does: align a
  commentary's lemmas to the root lines they quote, **given** a `comments_on` relation
  asserted on other grounds. This infers that relation from undirected evidence. Filing
  the inference under the name of the procedure that presupposes it would make one method
  name mean two things and would read as circular in the one place — `get_glosses` — where
  a reader is shown the method.

  Nor is it `title_match`, whose own migration set the precedent: a weaker kind of claim
  earns its own name so that `CLAUDE.md` invariant #5 survives into the answer.

  Weakest to strongest the enum now reads: `llm`, `shared_text`, `lemma_match`,
  `title_match`, `manifest`, `catalogue`.
  """

  def up do
    drop constraint(:work_relations, :work_relations_method_known)

    create constraint(:work_relations, :work_relations_method_known,
             check:
               "method IN ('catalogue','manifest','title_match','lemma_match','shared_text','llm')"
           )
  end

  def down do
    execute "DELETE FROM work_relations WHERE method = 'shared_text'"

    drop constraint(:work_relations, :work_relations_method_known)

    create constraint(:work_relations, :work_relations_method_known,
             check: "method IN ('catalogue','manifest','title_match','lemma_match','llm')"
           )
  end
end
