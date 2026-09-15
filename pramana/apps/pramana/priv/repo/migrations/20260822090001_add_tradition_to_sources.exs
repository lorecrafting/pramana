defmodule Pramana.Repo.Migrations.AddTraditionToSources do
  @moduledoc """
  Which canon a source belongs to, as a column a query can group by.

  `Pramana.Retrieval.Semantic` kept the mapping in code — `%{"chinese" => ["cbeta"],
  "pali" => ["sc"], "tibetan" => ["derge", "derge-tengyur"]}` — and used it to run one
  search per canon under `per_tradition: true`. A source missing from that map is not
  ranked lower, it is **never queried**, and the map named four of the eight registered
  sources. Commit 4d867c9 moved the mapping onto the source registry so that omission
  became a compile error, which fixes every PINNED source and none of the local ones:
  `local-*` ids cannot be enumerated in a static registry, and
  `local-huang-nianzu-jie` holds 848 embedded chunks that per-tradition search cannot
  reach.

  ## Why a column rather than more code

  This is the `license_class` lesson (#17, gate finding 1). That was recorded on every
  source and displayed in every result, which made it look enforced — while **no
  retriever could filter on it**, so "we publish the pipeline, not the corpus" was a
  promise kept by hand. A property that decides what a query returns has to be *in* the
  query. Tradition now decides which searches run, so it belongs beside `license_class`,
  not in a module attribute compiled a layer away from the rows it describes.

  ## The backfill is literal, not derived

  The values below are written out rather than read from `Pramana.Sources`, because a
  migration records what was true when it ran. Code that a later migration re-reads has
  moved on; this file must keep meaning the same thing in five years.

  `NOT NULL` at the end is the database saying the same thing the registry now says at
  compile time: a source with no declared tradition is not a source this system is
  willing to hold, because the failure it produces is silence rather than an error.
  """

  use Ecto.Migration

  def up do
    alter table(:sources) do
      add :tradition, :string
    end

    # The pinned sources, per Pramana.Sources at the time of this migration. Note `sat`:
    # it is registered and blocked on acquisition (#14), and it is grouped here BEFORE
    # its text exists, because the day it arrives nothing would fail to say it was
    # unreachable.
    execute("UPDATE sources SET tradition = 'chinese' WHERE id IN ('cbeta', 'sat')")
    execute("UPDATE sources SET tradition = 'pali' WHERE id IN ('sc')")

    execute("""
    UPDATE sources SET tradition = 'tibetan'
    WHERE id IN ('derge', 'derge-tengyur', 'bdrc-derge', '84000', '84000-rdf')
    """)

    # Anything else is a locally-added text, and it becomes its OWN tradition rather than
    # being folded into a canon nobody declared it part of. A local manifest that does
    # belong to one can now say so, and re-ingesting corrects the row.
    execute("UPDATE sources SET tradition = id WHERE tradition IS NULL")

    # `null: false` with a default, exactly as `license_class` is declared. The default
    # applies only to a row inserted without the field — `Loader.insert_source!/1` always
    # sets it, and the registry makes a pinned source that declares none a compile error,
    # so "unknown" is reachable only by hand-building a row. It is a better answer than
    # NULL for the same reason `license_class` defaults rather than rejecting: an unknown
    # tradition still forms a GROUP, so the source is still queried and still answers,
    # where NULL would put it back in the invisible state this whole change removes.
    alter table(:sources) do
      modify :tradition, :string, null: false, default: "unknown"
    end

    execute(
      "COMMENT ON COLUMN sources.tradition IS " <>
        "'Which canon transmits this source. NOT composition_origin: a Pāli sutta and " <>
        "a Derge sūtra are both indic in origin and belong to different canons, and " <>
        "Taishō 56–84 are japanese in origin and belong to the Chinese canon.'"
    )
  end

  def down do
    alter table(:sources) do
      remove :tradition
    end
  end
end
