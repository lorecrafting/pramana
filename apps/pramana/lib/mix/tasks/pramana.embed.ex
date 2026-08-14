defmodule Mix.Tasks.Pramana.Embed do
  @shortdoc "Embeds retrieval chunks with BGE-M3"

  @moduledoc """
  Embeds outstanding chunks, resumably.

      mix pramana.embed --division 阿含部
      mix pramana.embed --limit 200
      mix pramana.embed                    # everything outstanding

  Resumable and idempotent: a chunk already embedded by the current model is skipped,
  so a run killed at 40% resumes at 40%.

  Measured at 1.60 s/chunk on an Apple M1 — 4.5 hours for 阿含部 and about 133 hours
  for the full corpus, which is why the full run belongs on rented GPU. See
  `docs/EMBEDDING.md`.
  """

  use Mix.Task

  alias Pramana.Embed

  @switches [division: :string, limit: :integer, batch_size: :integer]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    pending = Embed.pending_count(opts)

    if pending == 0 do
      Mix.shell().info("nothing outstanding — every chunk has a #{Embed.model()} vector")
    else
      Mix.shell().info("#{pending} chunk(s) outstanding; loading #{Embed.model()}...")
      embed(opts, pending)
    end
  end

  defp embed(opts, pending) do
    serving = Embed.build_serving(opts)
    Mix.shell().info("model ready; embedding #{Embed.dims()}-dim vectors")

    {:ok, done} =
      Embed.run(Keyword.put(opts, :serving, serving) ++ [on_batch: &report(&1, pending)])

    Mix.shell().info("\nembedded #{done} chunk(s)")
  end

  defp report(%{done: done, elapsed_ms: ms}, total) do
    if rem(done, 160) == 0 or done == total do
      rate = done / max(ms / 1000, 0.001)
      remaining = (total - done) / max(rate, 0.001)

      Mix.shell().info(
        "  #{done}/#{total}  #{Float.round(rate, 2)} chunks/s  " <>
          "eta #{Float.round(remaining / 60, 1)} min"
      )
    end
  end
end
