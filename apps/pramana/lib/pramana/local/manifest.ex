defmodule Pramana.Local.Manifest do
  @moduledoc """
  The declaration a locally-added text ships with, and its validation.

  A new *canonical* source is code — its format and citation grammar are genuinely its
  own. A one-off text is not: a modern commentary, a teacher's talks, a translation. That
  should be a folder and a file, and it is what `docs/ADDING_TEXTS.md` describes.

  ## Validation writes nothing, deliberately

  Getting provenance wrong is the failure this project exists to prevent, so checking has
  to be separable and cheap to re-run. `mix pramana.local.validate` never touches the
  database, the lockfile or `raw/`.

  ## Defaults lean conservative, because the failure modes are asymmetric

  - **`license.class` defaults to `restricted`.** Most one-off texts are modern and in
    copyright. Defaulting permissive is a licence violation waiting to happen; defaulting
    restricted merely keeps the text off public surfaces.
  - **Provenance is required, not inferred.** No division table applies to a local text,
    and there is no catalogue to fall back on. A guess is worse than a gap.
  - **Addressing is declared, not assumed** — see below.

  ## Addressing: three honest levels, not two

  `docs/ADDING_TEXTS.md` originally offered `canonical` or `derived`. Real texts needed a
  middle term.

  | value | meaning |
  |---|---|
  | `canonical` | anchored to a published digital critical edition; a citation can be checked against it (CBETA/Taishō) |
  | `edition_page` | anchored to a page number **printed in the physical book**, recovered by our extraction. A reader with the book can turn to it; the risk is our extraction, not the anchor |
  | `derived` | no intrinsic anchor exists; positions come from file structure and shift if the file changes |

  Prefer the highest level the source actually supports, exactly as the Taishō segmenter
  adopts printed page/register/line rather than inventing ids (`CLAUDE.md` invariant #2).
  A text with printed page numbers should never be given `derived` anchors.

  ## Extraction quality is provenance

  An OCR'd text and a hand-proofread one are not the same evidence, so `extraction`
  records method and confidence and travels with every segment. This is not hypothetical:
  the Huang Nianzu source's own QA notes record a first extraction pass that was
  *silently lossy* — the book writes zero as `○` (U+25CB), the splitter only knew `〇`
  (U+3007), and ~158 of 837 pages were mis-cut without any error.
  """

  @enforce_keys [:id, :title, :provenance, :license, :citation, :format]
  defstruct [
    :id,
    :title,
    :title_en,
    :author,
    :provenance,
    :license,
    :citation,
    :format,
    :extraction,
    :comments_on,
    :source_note,
    files: []
  ]

  @type t :: %__MODULE__{}

  @required ~w(id title provenance citation)
  @origins ~w(indic chinese japanese korean tibetan)
  @roles ~w(root treatise commentary subcommentary apocryphon catalogue history conflation)
  @addressing ~w(canonical edition_page derived)
  @license_classes ~w(restricted nc cc0 cc-by cc-by-sa public-domain unknown)
  @confidences ~w(certain probable uncertain disputed)
  @formats ~w(markdown text)

  @doc """
  Loads and validates a manifest from a source directory.

  Returns `{:ok, manifest}` or `{:error, [message]}` — every problem at once, because
  fixing one field at a time through repeated runs is how people give up and guess.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, [String.t()]}
  def load(dir) do
    path = Path.join(dir, "manifest.yaml")

    with {:ok, raw} <- read(path),
         {:ok, parsed} <- parse(raw, path) do
      validate(parsed, dir)
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> {:error, ["no manifest.yaml at #{path}"]}
      {:error, reason} -> {:error, ["cannot read #{path}: #{inspect(reason)}"]}
    end
  end

  defp parse(raw, path) do
    case YamlElixir.read_from_string(raw) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, ["#{path} is not a YAML mapping"]}
      {:error, error} -> {:error, ["#{path} is not valid YAML: #{Exception.message(error)}"]}
    end
  end

  @doc """
  Validates an already-parsed manifest map against a source directory.

  Exposed separately so tests and a future manifest-authoring GUI can check a draft that
  is not yet on disk.
  """
  @spec validate(map(), Path.t()) :: {:ok, t()} | {:error, [String.t()]}
  def validate(map, dir) when is_map(map) do
    errors =
      []
      |> check_required(map)
      |> check_id(map)
      |> check_provenance(map)
      |> check_citation(map)
      |> check_license(map)
      |> check_format(map)
      |> check_extraction(map)
      |> check_comments_on(map)
      |> check_text_dir(dir)

    case errors do
      [] -> {:ok, build(map, dir)}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp check_required(errors, map) do
    Enum.reduce(@required, errors, fn key, acc ->
      if blank?(map[key]), do: ["`#{key}` is required" | acc], else: acc
    end)
  end

  # The id becomes part of every URN this text produces, so it has to survive being
  # embedded in one: no colons (the URN separator), no @ (the locator separator).
  defp check_id(errors, map) do
    case map["id"] do
      nil -> errors
      id when is_binary(id) -> validate_id(errors, id)
      _ -> ["`id` must be a string" | errors]
    end
  end

  defp validate_id(errors, id) do
    if Regex.match?(~r/\A[a-z0-9][a-z0-9-]*\z/, id) do
      errors
    else
      ["`id` must be lowercase letters, digits and hyphens (it appears in every URN)" | errors]
    end
  end

  defp check_provenance(errors, map) do
    prov = map["provenance"] || %{}

    errors
    |> require_member(prov["composition_origin"], @origins, "provenance.composition_origin")
    |> require_member(prov["text_role"], @roles, "provenance.text_role")
    |> optional_member(
      prov["attribution_confidence"],
      @confidences,
      "provenance.attribution_confidence"
    )
  end

  defp check_citation(errors, map) do
    citation = map["citation"] || %{}

    errors
    |> require_member(citation["addressing"], @addressing, "citation.addressing")
    |> check_anchor_honesty(citation)
  end

  # The point of `edition_page` is that a reader can open the book at that page, which is
  # only true if the manifest says where the numbers came from.
  defp check_anchor_honesty(errors, %{"addressing" => "edition_page"} = citation) do
    if blank?(citation["anchor_source"]) do
      [
        "`citation.anchor_source` is required when addressing is `edition_page` — say " <>
          "where the page numbers come from (e.g. \"printed page numbers in the book " <>
          "header\"), because that claim is what makes the citation checkable"
        | errors
      ]
    else
      errors
    end
  end

  defp check_anchor_honesty(errors, _citation), do: errors

  defp check_license(errors, map) do
    license = map["license"] || %{}
    optional_member(errors, license["class"], @license_classes, "license.class")
  end

  defp check_format(errors, map) do
    optional_member(errors, map["format"], @formats, "format")
  end

  defp check_extraction(errors, map) do
    case map["extraction"] do
      nil ->
        errors

      extraction when is_map(extraction) ->
        optional_member(errors, extraction["confidence"], @confidences, "extraction.confidence")

      _ ->
        ["`extraction` must be a mapping" | errors]
    end
  end

  defp check_comments_on(errors, map) do
    case map["comments_on"] do
      nil -> errors
      %{"work" => work} when is_binary(work) and work != "" -> errors
      _ -> ["`comments_on` must include a `work` naming what this text explains" | errors]
    end
  end

  defp check_text_dir(errors, dir) do
    text_dir = Path.join(dir, "text")

    cond do
      not File.dir?(text_dir) -> ["no `text/` directory at #{text_dir}" | errors]
      files(text_dir) == [] -> ["`text/` at #{text_dir} contains no files" | errors]
      true -> errors
    end
  end

  defp require_member(errors, value, allowed, field) do
    cond do
      blank?(value) ->
        ["`#{field}` is required (one of: #{Enum.join(allowed, ", ")})" | errors]

      value in allowed ->
        errors

      true ->
        [
          "`#{field}` must be one of: #{Enum.join(allowed, ", ")} (got #{inspect(value)})"
          | errors
        ]
    end
  end

  defp optional_member(errors, nil, _allowed, _field), do: errors

  defp optional_member(errors, value, allowed, field) do
    if value in allowed do
      errors
    else
      ["`#{field}` must be one of: #{Enum.join(allowed, ", ")} (got #{inspect(value)})" | errors]
    end
  end

  defp build(map, dir) do
    %__MODULE__{
      id: map["id"],
      title: map["title"],
      title_en: map["title_en"],
      author: map["author"],
      # Kept STRING-keyed. Atomizing a manifest means calling
      # `String.to_existing_atom/1` on values a user wrote, which raises for any key
      # the code has not already mentioned — `date_range` did exactly that. Manifest
      # data is external input; it does not get to touch the atom table.
      provenance: map["provenance"] || %{},
      # Restricted unless the manifest says otherwise. See the module doc.
      license:
        Map.merge(%{"class" => "restricted", "redistributable" => false}, map["license"] || %{}),
      citation: map["citation"] || %{},
      format: map["format"] || "markdown",
      extraction: map["extraction"],
      comments_on: map["comments_on"],
      source_note: map["source_note"],
      files: files(Path.join(dir, "text"))
    }
  end

  @doc "Text files in a source directory, sorted, relative to `text/`."
  @spec files(Path.t()) :: [String.t()]
  def files(text_dir) do
    text_dir
    |> Path.join("**/*.{md,txt}")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, text_dir))
    |> Enum.sort()
  end

  @doc "Whether this manifest's text may appear on a public surface."
  @spec public?(t()) :: boolean()
  def public?(%__MODULE__{license: license}) do
    license["class"] in ~w(cc0 cc-by cc-by-sa public-domain) and
      license["redistributable"] == true
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
