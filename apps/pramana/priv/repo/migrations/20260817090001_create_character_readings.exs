defmodule Pramana.Repo.Migrations.CreateCharacterReadings do
  @moduledoc """
  The base reading of a character, and every reading attested for it.

  `docs/LAYERS.md` §2 forbids storing a reading per *corpus* character — billions of
  rows of derivable data. This is the derivation's other half: one row per **distinct
  character in Unicode**, about 44,000 of them, which is the dictionary the render step
  consults. The corpus does not appear here at all.

  ## Why `attested` exists as well as `reading`

  `reading` is Unihan's `kMandarin`: the commonest reading, and the only thing a
  per-character library ever sees. For 佛 it is *fú* — because 佛 is common in 仿佛
  *fǎngfú* — and so a character-by-character renderer calls the Buddha *fú* through
  533,670 occurrences of the canon.

  `attested` is the union of every reading Unihan records anywhere: `kHanyuPinyin`,
  `kXHC1983`, `kTGHZ2013`, `kHanyuPinlu`. 葉 is `yè, shè`; 若 is `ruò, rě, ré, rè`; 般 is
  `bān, bō, pán, bǎn`. **The Buddhist readings are already in Unicode.** What no
  per-character table can say is which one applies in 迦葉, and that is the exception
  table's job.

  It is also the integrity rule. A reading asserted for a form — derived from CC-CEDICT
  or hand-curated — must appear in this column for the matching character, or it is
  rejected. Two independent authorities have to agree before anything ships, which is
  the same standard the citation guard applies to quoted text.
  """

  use Ecto.Migration

  def change do
    create table(:character_readings, primary_key: false) do
      add :character, :string, null: false, primary_key: true
      add :reading, :string, null: false
      add :attested, {:array, :string}, null: false, default: []
      add :authority, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # A base reading must itself be attested — the invariant this table enforces on
    # everything else has to hold for its own rows first.
    create constraint(:character_readings, :base_reading_is_attested,
             check: "reading = ANY(attested)"
           )
  end
end
