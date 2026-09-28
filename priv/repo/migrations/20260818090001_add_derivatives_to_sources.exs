defmodule Pramana.Repo.Migrations.AddDerivativesToSources do
  @moduledoc """
  The fourth licence axis, which nothing in the corpus needed until 84000.

  `sources` recorded three things about a licence: whether it permits commercial use,
  whether it permits redistribution, and a coarse `license_class` for gating. Creative
  Commons has **four** switches, and the missing one is *no-derivatives*.

  Every source ingested so far happened not to need it. CBETA is NC but permits
  derivative works; bilara-data is CC0 and CC-BY-SA; the reading dictionaries are
  permissive. 84000 is the first source licensed **CC BY-NC-ND**, and ND is not a
  weaker NC — it is an orthogonal restriction on a different act.

  ## Why this cannot be folded into `license_class`

  It constrains different operations. `commercial_use` and `redistributable` govern who
  may receive the text; `derivatives` governs what may be **made** from it — and this
  pipeline makes things. It segments, it chunks, it embeds, and Phase 7 will translate.
  Whether those are derivative works is a judgement for the deployment, not for this
  schema, but the schema has to be able to *record the constraint* so the judgement has
  something to attach to. Flattening ND into "nc" would lose the question entirely, and
  the question is the whole point of tracking licences structurally.

  Default `true`: every existing source permits derivatives, and a column that silently
  told a caller otherwise would be worse than no column.
  """

  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :derivatives, :boolean, null: false, default: true
    end

    # Recorded per SOURCE, not per class, exactly as `commercial_use` is. The bilara-data
    # lesson stands: a repository-level LICENSE file is a claim, and the publication's own
    # metadata is the fact — they disagreed twice there.
    execute(
      "COMMENT ON COLUMN sources.derivatives IS " <>
        "'Whether the licence permits derivative works. CC ND licences set this false; " <>
        "it constrains what may be MADE from the text, not who may receive it.'",
      "COMMENT ON COLUMN sources.derivatives IS NULL"
    )
  end
end
