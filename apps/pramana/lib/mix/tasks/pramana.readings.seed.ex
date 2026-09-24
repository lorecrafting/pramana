defmodule Mix.Tasks.Pramana.Readings.Seed do
  @shortdoc "Seeds the reading-exception layer from the glossary"

  @moduledoc """
  Projects glossary terms whose language of origin is not Chinese into
  `reading_exceptions`.

      mix pramana.readings.seed

  The glossary (#34) already records, with provenance, the cases that matter: names in
  Chinese characters that are **not Chinese** and must not be read as if they were.
  Nothing is invented here — the reading, its status and its authority all come from the
  glossary row. Building the layer out from DDB and Buddhist reference works is #24.
  """

  use Mix.Task

  alias Pramana.Readings

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    {:ok, result} = Readings.seed_from_glossary()
    stats = Readings.stats()

    Mix.shell().info("""

    seeded reading exceptions
      seeded:          #{result.seeded}
      by language:     #{inspect(result.by_lang)}
      by status:       #{inspect(result.by_status)}

      table total:     #{stats.exceptions}
      by scheme:       #{inspect(stats.by_scheme)}
      no reading yet:  #{stats.without_reading}  (recorded as wrong, not yet resolved — #24)
    """)
  end
end
