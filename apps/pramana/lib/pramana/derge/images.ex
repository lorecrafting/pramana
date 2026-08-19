defmodule Pramana.Derge.Images do
  @moduledoc """
  The scanned woodblock page a Derge passage was printed on.

  BDRC photographed the Degé Kangyur as `W4CZ5369` and serves it over IIIF. This turns a
  citation — volume 51, folio 1b — into the image of that leaf, so a reader can check the
  print rather than trusting the etext. Nothing is downloaded and nothing is read from the
  image: the corpus links, and says whose scan it is linking to (`docs/ROADMAP.md`, Phase
  5: *catalog only, no OCR*).

  ## The mapping is published, not derived

  Every canvas in BDRC's manifest carries the folio as its label — `1a`, `1b`, `2a` —
  beside the image number and the Tibetan. So the corpus reads the mapping instead of
  computing it, which is the same rule that governs its citations: adopt the edition's own
  reference system, never invent one (`CLAUDE.md` invariant #2).

  **The arithmetic version was written first and was wrong.** Two cataloguing cards, then
  folio *n* recto at side 2n−1, is exactly right for 74 of the 103 volumes and impossible
  for the other 29, which come out claiming more leaf-sides than the scan contains. Volume
  7 shows why: the etext prints folios 1a–287b, BDRC's labels run 1a–287b, and there are
  536 canvases where contiguous sides would need 574. Sides are missing from the middle of
  the scan. Nothing computable from a filename could know which ones, and a mapping that is
  off by one leaf shows the reader a page that is *almost* right — the failure this project
  exists to prevent, arriving as a photograph.

  ## What a missing folio means

  A folio with no canvas gets `:error` rather than a nearby page. The reader is told there
  is no image of that leaf, which is true and useful; being shown its neighbour is neither.
  """

  alias Pramana.Normalize.Derge.Edition

  @image_api "https://iiif.bdrc.io"
  @presentation_api "https://iiifpres.bdrc.io"

  @derge_root "raw/derge/UT4CZ5369-200106"
  @manifests_root "raw/bdrc-derge"
  @index_path "priv/derge/folio_images.json"

  @typedoc "A page of the scan, and the IIIF services that serve it."
  @type image :: %{
          volume: pos_integer(),
          folio: String.t(),
          image_group: String.t(),
          filename: String.t(),
          image_url: String.t(),
          info_url: String.t(),
          manifest_url: String.t(),
          attribution: String.t()
        }

  @attribution "Digitised by the Buddhist Digital Resource Center (BDRC), W4CZ5369"

  @doc """
  Every volume of the edition, as `{volume number, BDRC image group}`.

  Both come from the etext: the group from the directory BDRC's scan was distributed in,
  the number from the title page inside it. Derived per volume rather than by adding 9126
  to the volume number, which happens to work and is not a fact about anything.
  """
  @spec volumes(Path.t()) :: [{pos_integer(), String.t()}]
  def volumes(root \\ @derge_root) do
    case Edition.volumes_at(root) do
      {:ok, found} ->
        found
        |> Enum.map(fn {volume, path} -> {volume, image_group(path)} end)
        |> Enum.reject(fn {_volume, group} -> is_nil(group) end)

      {:error, _reason} ->
        []
    end
  end

  defp image_group(path) do
    case Regex.run(~r/(I1KG\d+)/, path) do
      [_, group] -> group
      nil -> nil
    end
  end

  @doc "The IIIF Presentation manifest for a whole volume."
  @spec manifest_url(String.t()) :: String.t()
  def manifest_url(group), do: "#{@presentation_api}/v:bdr:#{group}/manifest"

  @doc """
  The folio-to-filename map inside one manifest.

  A canvas is labelled several times over — `1a`, `img. 3`, `1na/`, `par grangs _3` — and
  only the first is a folio. Anything that is not `digits + a|b` is a different fact about
  the same page.
  """
  @spec folios_in(map()) :: %{String.t() => String.t()}
  def folios_in(manifest) do
    manifest
    |> canvases()
    |> Enum.reduce(%{}, fn canvas, acc ->
      with folio when not is_nil(folio) <- folio_label(canvas),
           filename when not is_nil(filename) <- filename(canvas) do
        Map.put_new(acc, folio, filename)
      else
        _ -> acc
      end
    end)
  end

  defp canvases(%{"sequences" => [%{"canvases" => canvases} | _]}) when is_list(canvases),
    do: canvases

  defp canvases(%{"items" => items}) when is_list(items), do: items
  defp canvases(_manifest), do: []

  defp folio_label(%{"label" => labels}) when is_list(labels) do
    Enum.find_value(labels, fn
      %{"@value" => value} -> if folio?(value), do: value
      _ -> nil
    end)
  end

  defp folio_label(%{"label" => label}) when is_binary(label), do: if(folio?(label), do: label)
  defp folio_label(_canvas), do: nil

  defp folio?(value) when is_binary(value), do: Regex.match?(~r/^\d+[ab]$/, value)
  defp folio?(_value), do: false

  # The canvas id ends in the image file it shows.
  defp filename(canvas) do
    case canvas["@id"] || canvas["id"] do
      nil -> nil
      id -> id |> String.split("/") |> List.last()
    end
  end

  @doc """
  Builds the index the corpus reads at run time, from the fetched manifests.

  The manifests are half a megabyte each and hold far more than this needs; the index is
  volume, folio and filename, which is all a link requires.
  """
  @spec build_index(Path.t(), Path.t()) :: {:ok, non_neg_integer()}
  def build_index(manifests \\ @manifests_root, out \\ @index_path) do
    index =
      for {volume, group} <- volumes(),
          {:ok, manifest} <- [read_manifest(manifests, group)],
          into: %{} do
        {Integer.to_string(volume), %{"group" => group, "folios" => folios_in(manifest)}}
      end

    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Jason.encode!(index))
    :persistent_term.erase({__MODULE__, :index})

    {:ok, map_size(index)}
  end

  defp read_manifest(root, group) do
    with {:ok, body} <- File.read(Path.join(root, "#{group}.json")), do: Jason.decode(body)
  end

  @doc """
  The scan of one folio, or `:error` when BDRC has no canvas labelled that.

  An inserted leaf — `355xa` — is not labelled separately in the scan, so it resolves to
  the leaf it was inserted beside.
  """
  @spec find(pos_integer(), String.t()) :: {:ok, image()} | :error
  def find(volume, folio) do
    with %{} = index <- index(),
         %{"group" => group, "folios" => folios} <- index[Integer.to_string(volume)],
         filename when is_binary(filename) <- folios[normalise(folio)] do
      {:ok,
       %{
         volume: volume,
         folio: folio,
         image_group: group,
         filename: filename,
         image_url: "#{@image_api}/bdr:#{group}::#{filename}/full/max/0/default.jpg",
         info_url: "#{@image_api}/bdr:#{group}::#{filename}/info.json",
         manifest_url: manifest_url(group),
         attribution: @attribution
       }}
    else
      _ -> :error
    end
  end

  # `355xa` is an inserted leaf, which the scan labels by the leaf it sits beside.
  defp normalise(folio), do: String.replace(folio, "x", "")

  @doc """
  The scan for a URN of this corpus, or `:error` for anything that is not Derge.

      pramana:derge.D:toh113@51.100a.1  ->  volume 51, folio 100a
  """
  @spec for_urn(String.t()) :: {:ok, image()} | :error
  def for_urn(urn) when is_binary(urn) do
    with true <- String.contains?(urn, ":derge."),
         [_, locator] <- String.split(urn, "@", parts: 2),
         [volume, folio | _] <- String.split(locator, "."),
         {number, ""} <- Integer.parse(volume) do
      find(number, folio)
    else
      _ -> :error
    end
  end

  @doc "Whether the index has been built. Retrieval degrades to no images without it."
  @spec available?() :: boolean()
  def available?, do: is_map(index())

  defp index do
    case :persistent_term.get({__MODULE__, :index}, nil) do
      nil -> load_index()
      index -> index
    end
  end

  defp load_index do
    with {:ok, body} <- File.read(@index_path),
         {:ok, index} <- Jason.decode(body) do
      :persistent_term.put({__MODULE__, :index}, index)
      index
    else
      _ -> nil
    end
  end
end
