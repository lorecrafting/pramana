defmodule Pramana.Provenance do
  @moduledoc """
  Plain-language names for the provenance axes.

  `CLAUDE.md` invariant #4 says a Japanese sectarian commentary must never be presentable
  as an Indian sūtra, and `docs/ARCHITECTURE.md` argues the enforcement that matters is
  **structural**: the tool response is shaped so the distinction cannot be flattened
  away, rather than a prompt asking a model to be careful.

  Shape alone is not quite enough, though. A bucket keyed
  `{composition_origin: "chinese", text_role: "apocryphon"}` is only unmissable to a
  reader who already knows the vocabulary — and the reader most likely to mis-attribute
  is the one who does not. So each bucket also carries a sentence saying what it is.

  Lives in the domain, not in the MCP layer: the Phase 8 reader needs the same words, and
  two surfaces describing the same axis differently is how a corpus starts contradicting
  itself.
  """

  @origins %{
    "indic" => "Indic-composed",
    "chinese" => "Chinese-composed",
    "japanese" => "Japanese-composed",
    "korean" => "Korean-composed",
    "tibetan" => "Tibetan-composed"
  }

  @roles %{
    "root" => "root scripture",
    "treatise" => "treatise (śāstra)",
    "commentary" => "commentary",
    "subcommentary" => "subcommentary",
    "apocryphon" => "apocryphon — the canon itself marks it doubtful",
    "catalogue" => "catalogue",
    "history" => "history"
  }

  @unattributed "unattributed"

  @doc """
  A one-line description of an origin/role bucket.

  ## Examples

      iex> Pramana.Provenance.label("indic", "root")
      "Indic-composed root scripture"

      iex> Pramana.Provenance.label("japanese", "commentary")
      "Japanese-composed commentary"

      iex> Pramana.Provenance.label("chinese", "apocryphon")
      "Chinese-composed apocryphon — the canon itself marks it doubtful"

  A missing axis is named as missing rather than guessed. 古逸部 material recovered at
  Dunhuang records where a text was *found*, not where it was composed, so null is a
  considered answer:

      iex> Pramana.Provenance.label(nil, nil)
      "origin unattributed, role uncatalogued"
  """
  @spec label(String.t() | nil, String.t() | nil) :: String.t()
  def label(origin, role) do
    case {Map.get(@origins, origin), Map.get(@roles, role)} do
      {nil, nil} -> "origin unattributed, role uncatalogued"
      {nil, r} -> "#{r}, origin unattributed"
      {o, nil} -> "#{o}, role uncatalogued"
      {o, r} -> "#{o} #{r}"
    end
  end

  @doc """
  The value used in place of `nil` when grouping or counting.

  Grouping silently under a `nil` key hides works whose provenance is genuinely unknown,
  and that population is exactly the one a careful reader needs to see.
  """
  @spec unattributed() :: String.t()
  def unattributed, do: @unattributed

  @doc "Known composition origins, for validating a filter before it reaches the database."
  @spec origins() :: [String.t()]
  def origins, do: Map.keys(@origins)

  @doc "Known text roles."
  @spec roles() :: [String.t()]
  def roles, do: Map.keys(@roles)

  @doc """
  Buckets retrieval results by composition origin and text role.

  **Grouped, never flat**, and that is invariant #4 enforced by shape: a caller handed a
  flat list can render a Kamakura-period Japanese commentary immediately below an Indian
  sūtra with nothing between them, and nothing in the data stops it. A caller handed
  buckets has to name the bucket to render it.

  Lives here rather than in a surface. The MCP tool grouped its own results and the
  Phase 8 reader would have grouped them again — two implementations of the one rule
  invariant #4 rests on, drifting independently. `label/2` was already in the domain for
  exactly this reason.

  Each result must carry `span.provenance`; anything else is left in the
  `unattributed` bucket rather than dropped, because a work whose origin nobody has
  catalogued is a fact about the catalogue, not a reason to hide the work.
  """
  @spec group([map()]) :: [map()]
  def group(results) when is_list(results) do
    results
    |> Enum.group_by(fn r ->
      p = provenance_of(r)
      {p[:composition_origin], p[:text_role]}
    end)
    |> Enum.map(fn {{origin, role}, bucket} ->
      %{
        composition_origin: origin || @unattributed,
        text_role: role || @unattributed,
        label: label(origin, role),
        count: length(bucket),
        results: bucket
      }
    end)
    # Largest bucket first, and deterministic when two tie. Alphabetical order would put
    # "chinese" ahead of "indic" always, which quietly implies a precedence the corpus
    # does not have.
    |> Enum.sort_by(&{-&1.count, &1.composition_origin, &1.text_role})
  end

  defp provenance_of(%{span: %{provenance: p}}) when is_map(p), do: p
  defp provenance_of(%{provenance: p}) when is_map(p), do: p
  defp provenance_of(_), do: %{}
end
