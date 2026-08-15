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
end
