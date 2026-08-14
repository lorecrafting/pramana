defmodule Mix.Tasks.Pramana.Bake do
  @shortdoc "Normalizes, segments, and loads acquired sources into the corpus"

  @moduledoc """
  Runs the bake pipeline over acquired sources.

      mix pramana.bake --source cbeta --work T0262 --volume 9

  Requires `mix pramana.acquire` first — the bake reads only from `raw/`, never the
  network, so it is reproducible from `sources.lock.json`.
  """

  use Mix.Task

  alias Pramana.Acquire.CBETA
  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Loader
  alias Pramana.Normalize
  alias Pramana.URN.Taisho

  @switches [source: :string, work: :string, volume: :integer, canon: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    source = Keyword.get(opts, :source, "cbeta")
    work = Keyword.get(opts, :work, "T0262")
    volume = Keyword.get(opts, :volume, 9)
    canon = Keyword.get(opts, :canon, "T")

    # Verify raw/ still matches the lockfile before trusting a single byte of it.
    case Lockfile.verify(source) do
      {:ok, n} -> Mix.shell().info("verified #{n} raw file(s) against sources.lock.json")
      {:error, reason} -> Mix.raise("raw/ does not match the lockfile: #{inspect(reason)}")
    end

    number = String.replace_prefix(work, canon, "")
    path = Path.join([Lockfile.raw_dir(), source, CBETA.work_path(canon, volume, number)])
    xml = File.read!(path)

    {:ok, ir} =
      Normalize.CBETA.normalize(xml,
        work_id: work,
        canon: canon,
        volume: volume,
        number: number
      )

    # Volume 56-84 is mechanically Japanese-composed commentary; 1-55 and 85 need
    # catalogue data, and provenance_for_volume/1 returns nil rather than guessing.
    {:ok, provenance} = Taisho.provenance_for_volume(volume)

    {:ok, %{text: text, segments: count}} =
      Loader.load(ir, source: source, witness: canon, provenance: provenance)

    Mix.shell().info("""

    baked #{work} — #{ir.title}
      author:     #{ir.author}
      juan:       #{ir.juan_count}
      segments:   #{count}
      urn prefix: #{text.urn_prefix}
      origin:     #{provenance[:composition_origin] || "(catalogue data needed)"}
      role:       #{provenance[:text_role] || "(catalogue data needed)"}
    """)
  end
end
