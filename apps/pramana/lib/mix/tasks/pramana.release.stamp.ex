defmodule Mix.Tasks.Pramana.Release.Stamp do
  @shortdoc "Records what the retrieval state currently is, for stamping on answers"

  @moduledoc """
  Records a release: source text, English layer and index, as one id.

      mix pramana.release.stamp

  **Run this after anything that changes what a search returns** — `mix
  pramana.translate.import`, `mix pramana.embed.import`, `mix pramana.chunk`. Not after a
  re-bake alone, which moves `bake_id` and is already identified.

  ## Why it is not automatic

  It nearly is: stamping is idempotent by digest, so running it when nothing has changed
  returns the existing row instead of adding one. The reason it stays a command is that a
  release is a claim about what a published answer refers to, and the moment to make that
  claim is when a person decides the corpus is in a state worth answering from — the same
  reasoning that keeps `mix pramana.evals --gate --accept` a separate flag.

  **Forgetting is visible rather than silent.** `mix pramana.doctor` compares the stamp
  against the live corpus and says what moved, which is the property `bake_id` lacked and
  the whole reason this exists. See `Pramana.Release`.
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
  defp verdict(same, same), do: "unchanged — nothing that affects retrieval has moved."

  defp verdict(_before, _now),
    do: "MOVED — a search may now answer differently than it did under the previous id."
end
