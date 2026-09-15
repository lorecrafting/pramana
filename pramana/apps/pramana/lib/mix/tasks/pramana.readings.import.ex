defmodule Mix.Tasks.Pramana.Readings.Import do
  @shortdoc "Loads the built reading dictionary into the database"

  @moduledoc """
  Imports `priv/readings/*.tsv` into `character_readings` and `reading_exceptions`.

      mix pramana.readings.import

  The TSVs are committed artifacts produced by `mix pramana.readings.build`; this task
  only loads them, so it needs no raw dictionaries and runs anywhere the repo does.
  """

  use Mix.Task

  alias Pramana.Readings

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    {:ok, result} = Readings.import_dictionary()
    stats = Readings.stats()

    Mix.shell().info("""

    reading dictionary
      characters:      #{result.characters}
      exceptions:      #{result.exceptions}

      table total:     #{stats.exceptions} exception(s)
      by scheme:       #{inspect(stats.by_scheme)}
      by status:       #{inspect(stats.by_status)}
      no reading yet:  #{stats.without_reading}  (recorded as wrong, not yet resolved)
    """)
  end
end
