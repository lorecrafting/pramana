defmodule Mix.Tasks.Pramana.Release.Stamp do
  @shortdoc "Records the content identity of the current retrieval state"

  @moduledoc """
  Records a release: source text, translation layer and vector index, as one id.

      mix pramana.release.stamp

  **Run this after anything that changes what a search can return** — translation imports,
  vector imports/re-embedding, chunk rebuilds, and a source re-bake before serving from the
  new source state.

  Version-2 stamping hashes stable rendering fields and the actual stored pgvector bytes.
  It therefore scans the answer-producing rows and can take materially longer than the old
  count-based stamp. Request-time responses do not pay that cost: they read the selected
  release row.

  ## Why it is not automatic

  Stamping is idempotent by content digest, but a release is still a reviewed claim about
  what published answers refer to. The command stays explicit for the same reason
  `mix pramana.evals --gate --accept` requires an explicit acceptance action.

  **Forgetting is visible rather than silent.** `mix pramana.doctor` first checks cheap
  aggregate drift. When a v2 layer was touched without changing its counts/names, it
  recomputes only that layer's content digest to distinguish a real same-count edit from a
  no-op rewrite.

  Finish data writers before stamping. Release stampers are serialized with each other;
  the stamp lock does not freeze arbitrary corpus writes.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    before = Pramana.Release.current_id()
    {:ok, release} = Pramana.Release.stamp()

    Mix.shell().info("""

      release_id          #{release.release_id}
        source_bake_id    #{release.source_bake_id}
        translation_set   #{release.translation_set_id}
        vector_set        #{release.vector_set_id}

      covers              #{release.translations_count} rendering(s) by #{length(release.translators)} translator(s)
                          #{release.vectors_count} vector(s) from #{Enum.join(release.embedding_models, ", ")}
      #{verdict(before, release.release_id)}
    """)
  end

  defp verdict(nil, _now), do: "FIRST RELEASE — responses now carry a release_id."
  defp verdict(same, same), do: "unchanged — the stamped content identity is unchanged."

  defp verdict(_before, _now),
    do: "MOVED — answer-producing source, rendering or vector state has changed."
end
