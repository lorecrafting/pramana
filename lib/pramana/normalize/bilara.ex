defmodule Pramana.Normalize.Bilara do
  @moduledoc """
  Normalizes SuttaCentral `bilara-data` into `Pramana.Normalize.IR`.

  The easiest source in the project, and deliberately so: bilara files are a flat JSON
  map of **segment id → text**, already aligned by the people who made them.

      {"mn1:1.1": "Evaṁ me sutaṁ—",
       "mn1:1.2": "ekaṁ samayaṁ bhagavā ukkaṭṭhāyaṁ viharati…"}

  ## The ids are adopted verbatim

  `mn1:1.1` is SuttaCentral's own citation, used across the field and printed in their
  publications. It becomes the URN locator unchanged — `pramana:sc.ms:mn1@1.1` —
  exactly as the Taishō segmenter adopts page/register/line rather than inventing ids
  (`CLAUDE.md` invariant #2). Renumbering would break every existing reference to this
  material for no gain.

  ## Ordering is not the map's ordering

  JSON objects have no guaranteed order, and Elixir maps have none at all, so the
  segments are sorted by their **numeric** id components. Sorting `mn1:1.1`, `mn1:1.10`,
  `mn1:1.2` as strings would put 1.10 before 1.2 and silently reorder the sutta — text
  that reads plausibly and is wrong, which is this project's worst failure mode.
  """

  @behaviour Pramana.Pipeline.Normalizer

  alias Pramana.Normalize.IR
  alias Pramana.Normalize.IR.Line

  @doc """
  Normalizes one bilara file into **one IR per work**.

  A file is a packaging unit, not a citation unit: `an1.1-10_root-pli-ms.json` holds ten
  suttas, keyed `an1.1:1.0`, `an1.2:1.0` and so on. Taking the work id from the filename
  and the locator from after the colon collapsed all ten `1.0`s into one address and the
  ingest died on a duplicate-URN constraint — which is the good outcome, because the
  alternative was ten different passages sharing a citation.

  The work id therefore comes from the **segment id's own prefix**, which is what
  SuttaCentral actually cites: AN 1.1, not AN 1.1-10.
  """
  @spec normalize_file(String.t(), keyword()) :: {:ok, [IR.t()]} | {:error, term()}
  def normalize_file(json, opts) do
    with {:ok, segments} <- Jason.decode(json) do
      irs =
        segments
        |> Enum.group_by(fn {id, _} -> work_of(id) end)
        |> Enum.map(fn {work_id, pairs} ->
          {:ok, ir} = normalize(Map.new(pairs), Keyword.put(opts, :work_id, work_id))
          ir
        end)
        |> Enum.sort_by(& &1.work_id)

      {:ok, irs}
    end
  end

  defp work_of(id), do: id |> String.split(":", parts: 2) |> hd()

  @impl Pramana.Pipeline.Normalizer
  def normalize(json, opts) when is_binary(json) do
    with {:ok, segments} <- Jason.decode(json) do
      normalize(segments, opts)
    end
  end

  def normalize(segments, opts) when is_map(segments) do
    work_id = Keyword.fetch!(opts, :work_id)
    witness = Keyword.get(opts, :witness, "ms")

    lines =
      segments
      |> Enum.map(fn {id, text} -> {locator(id, work_id), text} end)
      |> Enum.sort_by(fn {locator, _} -> sort_key(locator) end)
      |> Enum.map(fn {locator, text} ->
        %Line{
          anchor: locator,
          juan: nil,
          kind: :prose,
          # Bilara pads most segments with a trailing space so they concatenate into
          # running text. Trimmed here because the segment is the citable unit and its
          # sha256 must cover the text, not the typesetting.
          text: String.trim(text),
          notes: [],
          apparatus: [],
          gaiji: [],
          editorial_punctuation: false
        }
      end)

    {:ok,
     %IR{
       work_id: work_id,
       canon: witness,
       volume: nil,
       number: nil,
       title: title(lines),
       title_original: title(lines),
       author: nil,
       license_notice: Keyword.get(opts, :license_notice),
       juan_count: 0,
       lines: lines,
       outline: [],
       gaiji: %{},
       unanchored_apparatus: []
     }}
  end

  # `mn1:1.1` -> `1.1`. The work id is already carried by the URN's work component, so
  # repeating it in the locator would make every citation read `mn1@mn1:1.1`.
  defp locator(id, work_id) do
    case String.split(id, ":", parts: 2) do
      [^work_id, locator] -> locator
      [_other, locator] -> locator
      [only] -> only
    end
  end

  # `1.10` must sort after `1.2`. Comparing the dotted components as integers is the
  # only ordering that matches how the text is read.
  defp sort_key(locator) do
    locator
    |> String.split(~r/[.\-]/)
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {n, ""} -> {0, n, ""}
        # A component like "1a" sorts by its number, then by the suffix.
        {n, rest} -> {0, n, rest}
        :error -> {1, 0, part}
      end
    end)
  end

  # Bilara puts the collection name and the sutta title in the `:0.x` segments.
  defp title(lines) do
    lines
    |> Enum.filter(&String.starts_with?(&1.anchor, "0."))
    |> Enum.map(& &1.text)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " — ")
    end
  end
end
