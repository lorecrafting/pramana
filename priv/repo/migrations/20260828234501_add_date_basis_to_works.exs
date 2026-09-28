defmodule Pramana.Repo.Migrations.AddDateBasisToWorks do
  @moduledoc """
  Says where a work's dates came from.

  `works.date_start` and `date_end` have been null for every one of 17,281 texts since the
  schema was written, and DILA's authority can fill 1,515 of them. But **a person's lifespan
  is not a work's date** — Amoghavajra was born in 705 and did not translate at birth. What
  his dates give is a *bound*: the work was made somewhere between them.

  Storing that bound as though it were a composition date would be the same error as
  presenting a byline as an identity, which `authority_id` exists to avoid. So the basis is
  stored beside the dates:

  - `authority_lifespan` — bounded by the attributed person's birth and death. A range, and
    a wide one; useful for "is this Tang or Ming", useless for "which year".
  - `catalogue` — stated by a catalogue, for the day one supplies it.
  - `colophon` — stated by the text itself, which is the only one that is really the work's
    own date.

  Nothing in the corpus is `catalogue` or `colophon` yet. They are in the CHECK so that
  filling them later is a data change rather than a migration, and so a reader can see that
  every date currently held is the weakest of the three kinds.
  """

  use Ecto.Migration

  def change do
    alter table(:works) do
      add :date_basis, :string
    end

    create index(:works, [:date_start])
    create index(:works, [:date_basis])

    create constraint(:works, :date_basis_known,
             check:
               "date_basis IS NULL OR date_basis IN " <>
                 "('authority_lifespan', 'catalogue', 'colophon')"
           )

    # A date with no basis is a claim with no provenance, which is the thing this project
    # refuses everywhere else. The constraint makes it unrepresentable rather than
    # discouraged.
    create constraint(:works, :dates_state_their_basis,
             check: "(date_start IS NULL AND date_end IS NULL) OR date_basis IS NOT NULL"
           )
  end
end
