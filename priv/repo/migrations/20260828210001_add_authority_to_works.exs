defmodule Pramana.Repo.Migrations.AddAuthorityToWorks do
  @moduledoc """
  Links a work's byline to a DILA authority person.

  `works.attributed_author` holds the byline as the edition printed it — `劉宋 求那跋陀羅譯`
  — which is what the witness says and is deliberately kept verbatim. It is not an identity:
  the same translator appears with different characters across editions, and two people
  share a name three centuries apart.

  These columns carry the identity beside it, never instead of it. Nothing overwrites
  `attributed_author`, because the byline is evidence and the link is an inference about it.

  `method` and `confidence` are stored rather than derived, for the reason `CLAUDE.md`
  invariant #5 gives: a link made on a name plus a matching dynasty and one made on a name
  alone are different claims, and a caller must be able to tell them apart. Neither is ever
  `certain` — see `Pramana.Authority`.
  """

  use Ecto.Migration

  def change do
    alter table(:works) do
      add :authority_id, :string
      add :authority_method, :string
      add :authority_confidence, :string
    end

    # The reading query is "everything by this person", which is the whole point of having
    # an identity rather than a string.
    create index(:works, [:authority_id])

    create constraint(:works, :authority_method_known,
             check:
               "authority_method IS NULL OR authority_method IN " <>
                 "('name_and_dynasty', 'name_match_no_dynasty', 'manual')"
           )

    # No `certain`. The name is certainly in the byline; that it denotes this person rather
    # than a namesake the authority does not record is an inference, and the schema should
    # not offer a value the code must never use.
    create constraint(:works, :authority_confidence_known,
             check: "authority_confidence IS NULL OR authority_confidence IN ('probable')"
           )
  end
end
