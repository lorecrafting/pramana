defmodule Mix.Tasks.Pramana.Embed.FetchModel do
  @shortdoc "Brings the fine-tuned embedding weights back from the GPU volume"

  @moduledoc """
      mix pramana.embed.fetch_model

  Downloads the merged model produced by `priv/embed/modal_train_tibetan.py --merge-only`
  into `Pramana.Embed.local_model_dir/0`.

  ## Why this exists

  Documents are embedded on a rented GPU, which can apply a LoRA adapter. **Queries are
  embedded locally by Bumblebee, which cannot.** If the two sides use different weights
  the ranking is noise and nothing fails — every value is still a valid float — so the
  fine-tuned weights have to come back whole.

  `Pramana.Embed.build_serving/1` raises when `model/0` names an adapted model and these
  weights are absent, rather than falling back to the stock model. That refusal is the
  point: a serving that quietly embeds queries with the wrong weights returns confident
  nonsense, and no check downstream would catch it.

  The weights are **not** in git — 2.2 GB of tensors, reproducible from the adapter and
  the pinned base model. `docs/GPU_RUNBOOK.md` records how to regenerate them.
  """

  use Mix.Task

  alias Pramana.Embed

  @volume "pramana-embed"
  @remote "/merged_model"

  # Fetched FILE BY FILE. `modal volume get` with a directory source writes every file to
  # the single target path: the result was a 2.1 GB blob that `file` called "JSON data" —
  # plausible size, exit status 0, and unusable. Naming what is expected also means a
  # missing file is an error here rather than a puzzling load failure later.
  @files ~w(config.json tokenizer_config.json tokenizer.json model.safetensors)

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    target = Embed.local_model_dir()

    if File.dir?(target) do
      Mix.shell().info("already present at #{target} — delete it to re-fetch")
    else
      fetch(target)
    end

    report(target)
  end

  defp fetch(target) do
    File.mkdir_p!(Path.dirname(target))
    Mix.shell().info("fetching #{@remote} from the #{@volume} volume...")

    File.mkdir_p!(target)

    Enum.each(@files, fn file ->
      {output, status} =
        System.cmd(
          modal_cli(),
          ["volume", "get", @volume, "#{@remote}/#{file}", Path.join(target, file)],
          stderr_to_stdout: true
        )

      if status != 0 do
        Mix.raise("""
        could not fetch #{file} (exit #{status}):

        #{output}

        Produce the merged model first with:
          bin/pramana-modal run priv/embed/modal_train_tibetan.py --merge-only
        """)
      end
    end)
  end

  # The project root is explicit; the caller may be an umbrella child or worktree.
  defp modal_cli do
    path = Pramana.Paths.project("bin/pramana-modal")
    if File.regular?(path), do: path, else: Mix.raise("missing project Modal wrapper: #{path}")
  end

  # The check that matters is not "did something download" but "can Bumblebee load it and
  # does it agree with what the corpus was embedded with".
  defp report(target) do
    weights = Path.wildcard(Path.join(target, "*.safetensors"))
    config = File.exists?(Path.join(target, "config.json"))

    Mix.shell().info("""

    fine-tuned weights
      directory:      #{target}
      config.json:    #{config}
      weight files:   #{length(weights)}
      recorded model: #{Embed.model()}
      weights source: #{inspect(Embed.weights_source())}
    """)
  end
end
