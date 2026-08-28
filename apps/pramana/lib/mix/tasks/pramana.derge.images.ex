defmodule Mix.Tasks.Pramana.Derge.Images do
  @shortdoc "Fetches BDRC's image lists for the Derge Kangyur, one per volume"

  @moduledoc """
  Acquires what is needed to put a photograph of the woodblock beside the text.

      mix pramana.derge.images
      mix pramana.derge.images --limit 3

  BDRC scanned the Degé Kangyur as `W4CZ5369`, one **image group** per volume, and serves
  it over IIIF. This fetches the **presentation manifest** of each group into
  `raw/bdrc-derge/` and pins it, then writes the folio-to-image index the corpus reads.

  ## The manifest already says which image is folio 1b

  Every canvas carries the folio as its label — `1a`, `1b`, `2a` — beside the image
  number and the Tibetan (`1na/`, `par grangs _3`). So the mapping is **published**, and
  nothing here has to derive it.

  That matters because deriving it does not work. The obvious arithmetic — two
  cataloguing cards, then folio *n* recto at side 2n−1 — assumes every leaf-side was
  scanned, and 29 of the 103 volumes then claim more sides than exist. Volume 7 is the
  case that settles it: the etext prints folios 1a–287b, BDRC's labels run 1a–287b, and
  there are 536 canvases where contiguous sides would need 574. Sides are missing from
  the middle of the scan, and no arithmetic over a filename could know which. The labels
  do.

  ## No OCR, and no images stored

  Only the manifests are fetched — what exists, and what it is called. The images stay at
  BDRC and are linked, which is the whole of the Phase 5 commitment: a reader can check
  the printed page, and this corpus never claims to have read it.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Derge.Images
  alias Pramana.Sources

  @switches [limit: :integer, root: :string]

  @default_root "raw/bdrc-derge"
  @source_id "bdrc-derge"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    root = Keyword.get(opts, :root, @default_root)
    File.mkdir_p!(root)

    volumes = Images.volumes() |> take(opts[:limit])

    if volumes == [], do: Mix.raise("no Derge volumes found — is raw/derge unpacked?")

    Mix.shell().info("#{length(volumes)} volume(s) from BDRC")

    results = Enum.map(volumes, &fetch(&1, root))
    {ok, failed} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    if opts[:limit] == nil and failed == [] do
      write_lockfile(root)
      Images.build_index(root)
    end

    report(ok, failed)
  end

  defp take(volumes, nil), do: volumes
  defp take(volumes, n), do: Enum.take(volumes, n)

  defp fetch({volume, group}, root) do
    path = Path.join(root, "#{group}.json")

    case Req.get(Images.manifest_url(group), receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{} = manifest}} ->
        File.write!(path, Jason.encode!(manifest))
        folios = manifest |> Images.folios_in() |> map_size()
        Mix.shell().info("  volume #{volume} (#{group}): #{folios} labelled folio(s)")
        {:ok, volume, folios}

      {:ok, %{status: status}} ->
        {:error, volume, "HTTP #{status}"}

      {:error, reason} ->
        {:error, volume, inspect(reason)}
    end
  end

  defp write_lockfile(root) do
    files =
      root
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.map(fn path ->
        bytes = File.read!(path)

        %{path: Path.basename(path), sha256: Lockfile.sha256(bytes), bytes: byte_size(bytes)}
      end)

    {:ok, definition} = Sources.fetch(@source_id)

    entry =
      Lockfile.build_entry(definition,
        files: files,
        pin: %{"type" => "content", "files_sha256" => Lockfile.manifest_hash(files)}
      )

    :ok = Lockfile.put_source(entry)
  end

  defp report(ok, failed) do
    images = Enum.reduce(ok, 0, fn {:ok, _volume, count}, acc -> acc + count end)

    Mix.shell().info("""

    fetched BDRC image lists
      volumes:  #{length(ok)}
      folios:   #{images}
      failed:   #{length(failed)}
      service:  IIIF Image API at iiif.bdrc.io, Presentation API at iiifpres.bdrc.io
      licence:  metadata only — the scans stay at BDRC and are linked, never copied
    """)

    for {:error, volume, reason} <- failed do
      Mix.shell().error("  volume #{volume}: #{reason}")
    end
  end
end
