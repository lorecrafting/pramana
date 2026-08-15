defmodule Pramana.Repo.Migrations.AddTitleMatchMethod do
  use Ecto.Migration

  @moduledoc """
  Adds `title_match` as a relation method.

  Chinese commentary titles usually contain the title of the work they explain —
  大方廣圓覺修多羅了義經略疏 on 大方廣圓覺修多羅了義經. That containment is deterministic
  and checkable, so it deserves to be recorded rather than left to an LLM.

  It gets its own method rather than being filed under `catalogue` because it is a
  weaker claim: a catalogue is an editorial judgement about what a text *is*, while this
  is an inference from a string. Collapsing them would lose exactly the distinction
  `CLAUDE.md` invariant #5 exists to preserve.
  """

  def up do
    drop constraint(:work_relations, :work_relations_method_known)

    create constraint(:work_relations, :work_relations_method_known,
             check: "method IN ('catalogue','manifest','title_match','lemma_match','llm')"
           )
  end

  def down do
    execute "DELETE FROM work_relations WHERE method = 'title_match'"

    drop constraint(:work_relations, :work_relations_method_known)

    create constraint(:work_relations, :work_relations_method_known,
             check: "method IN ('catalogue','manifest','lemma_match','llm')"
           )
  end
end
