defmodule Pramana.Repo.Migrations.AddDivisionAndRoles do
  use Ecto.Migration

  @moduledoc """
  The Taishō division (部) as first-class data, and a wider `text_role` vocabulary.

  ## Why store the division

  The 部 is the canon's own organising principle — 阿含部, 般若部, 經疏部, 疑似部 — and it
  is richer than anything we derive from it. "Search only the Āgama section" is a real
  scholarly request, and answering it from our coarse origin/role mapping would lose
  information the catalogue actually has.

  ## Why widen text_role

  The original vocabulary conflated two questions. A Chinese translation of an Indian
  sūtra was `translation`, which describes how the text *arrived* rather than what it
  *is* — and `composition_origin` already answers the arrival question. Function is the
  useful axis: a sūtra is a root text whether you read it in Sanskrit, Chinese or
  English.

  So `root` now means scripture, `treatise` a śāstra (論), and `catalogue`/`history`
  the Chinese bibliographic and biographical genres that are neither. `translation` is
  retained for texts whose function genuinely is to be a rendering of a named other
  text.

  This makes the differentiating query say what it means:

      WHERE composition_origin = 'indic' AND text_role = 'root'
  """

  def up do
    alter table(:works) do
      add :division, :string
      add :division_en, :string
    end

    create index(:works, [:division])

    execute "ALTER TABLE works DROP CONSTRAINT text_role_known"

    execute """
    ALTER TABLE works ADD CONSTRAINT text_role_known CHECK (
      text_role IS NULL OR text_role IN (
        'root','treatise','translation','commentary','subcommentary',
        'apocryphon','catalogue','history','conflation'
      )
    )
    """
  end

  def down do
    execute "ALTER TABLE works DROP CONSTRAINT text_role_known"

    execute """
    ALTER TABLE works ADD CONSTRAINT text_role_known CHECK (
      text_role IS NULL OR text_role IN
        ('root','translation','commentary','subcommentary','apocryphon','conflation')
    )
    """

    drop index(:works, [:division])

    alter table(:works) do
      remove :division
      remove :division_en
    end
  end
end
