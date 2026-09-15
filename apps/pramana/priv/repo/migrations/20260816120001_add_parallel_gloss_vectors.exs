defmodule Pramana.Repo.Migrations.AddParallelGlossVectors do
  @moduledoc """
  Adds a `parallel_gloss` vector kind, and a `meta` column to record where a vector's
  text came from.

  ## Why a fourth kind rather than reusing `translation`

  The eval harness measured that an English question retrieves nothing from the Chinese
  canon (#42: 0/12, against 100% for the same questions asked in Chinese). The cause is
  a missing English layer to match against — Pāli has one and scores 62.5%.

  Before generating that layer with a model, invariant #5 says use the deterministic data
  first. We hold 24,717 curated Chinese↔Pāli parallels and 210,756 human English
  renderings of the Pāli, which covers **1,616 of the 10,138 阿含部 chunks** with English
  a person actually wrote, at zero token cost.

  But that English is **not a translation of the Chinese passage**. It is a translation of
  a *different text* that scholarship judges to transmit the same discourse — the exact
  distinction `Pramana.Compare` keeps in separate keys. Storing it as `kind: translation`
  would assert that Sujato translated a Chinese Āgama line, which he did not, and
  `matched_via` would then tell a caller something false about why a passage was found.

  Hence a fourth kind. A search that lands on a Chinese passage through the English of its
  Pāli parallel says so, and a reader can weigh that differently from a direct rendering —
  which they should, because the two texts differ.

  ## `meta`

  A gloss needs to name the parallel it came from, or its provenance is unauditable.
  Added to `chunk_vectors` generally rather than to one kind, since a generated gloss will
  need to record its model and prompt in the same place.
  """

  use Ecto.Migration

  def up do
    alter table(:chunk_vectors) do
      add :meta, :map, null: false, default: %{}
    end

    drop constraint(:chunk_vectors, :chunk_vector_kind_known)

    create constraint(:chunk_vectors, :chunk_vector_kind_known,
             check: "kind IN ('source','translation','question','parallel_gloss')"
           )

    # A gloss carries a translator too — the person who rendered the PARALLEL text — so
    # the rule is "anything English-bearing names whose words these are", not just
    # translations. A source vector still must not claim one.
    drop constraint(:chunk_vectors, :translation_vector_names_its_translator)

    create constraint(:chunk_vectors, :rendered_vector_names_its_translator,
             check: "(kind IN ('translation','parallel_gloss')) = (translator_id IS NOT NULL)"
           )
  end

  def down do
    execute "DELETE FROM chunk_vectors WHERE kind = 'parallel_gloss'"

    drop constraint(:chunk_vectors, :rendered_vector_names_its_translator)

    create constraint(:chunk_vectors, :translation_vector_names_its_translator,
             check: "(kind = 'translation') = (translator_id IS NOT NULL)"
           )

    drop constraint(:chunk_vectors, :chunk_vector_kind_known)

    create constraint(:chunk_vectors, :chunk_vector_kind_known,
             check: "kind IN ('source','translation','question')"
           )

    alter table(:chunk_vectors) do
      remove :meta
    end
  end
end
