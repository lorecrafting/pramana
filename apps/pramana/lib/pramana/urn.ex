defmodule Pramana.URN do
  @moduledoc """
  Parsing and formatting for Pramāṇa URNs — the addressing scheme every citation
  resolves through.

  See `docs/ARCHITECTURE.md`, "Stage 2 — Segment". The governing rule is invariant #2
  in `CLAUDE.md`: **never invent citation IDs.** Each tradition's own citation grammar
  supplies the components; the URN only provides a consistent envelope so a citation
  can be mechanically re-resolved and byte-compared against the bake.

  ## Grammar

      pramana:<source>.<witness>:<work>[@<locator>[-<locator_end>]][#tr:<lang>/<translator>]

  ## Examples

      pramana:cbeta.T:T0262_009@p0037a13-p0037b02   Lotus Sūtra, Kumārajīva, T vol.9
      pramana:sat.T:T2688_001@p0783b12               Nichiren-school comm., T vol.84
      pramana:sc.pali:mn1@1.1                        Mūlapariyāya Sutta, segment 1.1
      pramana:84000.kangyur:toh113@F.1.b.1           Derge Kangyur, folio 1b line 1
      pramana:local.huang-nianzu-wlsj:jie@sec12.p3   locally added commentary

  ## The rendering fragment

  A trailing `#tr:<lang>/<translator>` addresses a **translation of** the anchor, never a
  text in its own right:

      pramana:sc.ms:mn1@1.1#tr:en/sujato          Sujato's English for that segment
      pramana:cbeta.T:T0262_009@p0037a13#tr:en/model:claude-opus-5@prompt-v3

  This is deliberately a fragment rather than a first-class URN. A translation cannot be
  addressed without naming the source anchor it renders, which is what makes
  `CLAUDE.md` invariant #7 — *a machine translation is never citable as source* —
  structural rather than a rule someone has to remember. Strip the fragment and you are
  holding the source citation; there is no way to hold a rendering alone.

  Note the components are the traditions' own: `T0262_009` and `p0037a13` are exactly
  what a Taishō citation looks like in print; `mn1` and `1.1` are SuttaCentral's
  segment IDs verbatim. Only the `@` envelope is ours.
  """

  @scheme "pramana"
  @rendering_prefix "tr:"

  @type t :: %__MODULE__{
          source: String.t(),
          witness: String.t(),
          work: String.t(),
          locator: String.t() | nil,
          locator_end: String.t() | nil,
          # `{lang, translator_id}` when this addresses a rendering rather than the
          # source itself. See "The rendering fragment" above.
          rendering: {String.t(), String.t()} | nil,
          # nil when the URN was CONSTRUCTED rather than parsed — the segmenter builds
          # URNs from anchors and never has an original string to preserve.
          raw: String.t() | nil
        }

  @enforce_keys [:source, :witness, :work]
  defstruct [:source, :witness, :work, :locator, :locator_end, :rendering, :raw]

  @doc """
  Parses a URN string.

  Returns `{:ok, urn}` or `{:error, reason}`. Never raises — callers handling
  untrusted input (an LLM's cited URN, for instance) depend on that.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, atom()}
  def parse(string) when is_binary(string) do
    with {:ok, base, rendering} <- split_rendering(string),
         {:ok, rest} <- strip_scheme(base),
         {:ok, namespace, work_and_locator} <- split_once(rest, ":", :missing_work),
         {:ok, source, witness} <- split_once(namespace, ".", :missing_witness),
         {:ok, work, locator, locator_end} <- parse_work_and_locator(work_and_locator),
         :ok <- validate_nonempty(source: source, witness: witness, work: work) do
      {:ok,
       %__MODULE__{
         source: source,
         witness: witness,
         work: work,
         locator: locator,
         locator_end: locator_end,
         rendering: rendering,
         raw: string
       }}
    end
  end

  def parse(_), do: {:error, :not_a_string}

  @doc "Same as `parse/1` but raises on invalid input. For literals in our own code."
  @spec parse!(String.t()) :: t()
  def parse!(string) do
    case parse(string) do
      {:ok, urn} -> urn
      {:error, reason} -> raise ArgumentError, "invalid URN #{inspect(string)}: #{reason}"
    end
  end

  @doc "Renders a URN struct back to its canonical string form."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = urn) do
    base = "#{@scheme}:#{urn.source}.#{urn.witness}:#{urn.work}"

    anchored =
      case {urn.locator, urn.locator_end} do
        {nil, _} -> base
        {loc, nil} -> "#{base}@#{loc}"
        {loc, loc_end} -> "#{base}@#{loc}-#{loc_end}"
      end

    case urn.rendering do
      nil -> anchored
      {lang, translator} -> "#{anchored}##{@rendering_prefix}#{lang}/#{translator}"
    end
  end

  @doc """
  True when the URN addresses a translation layer rather than the source text.
  """
  @spec rendering?(t()) :: boolean()
  def rendering?(%__MODULE__{rendering: nil}), do: false
  def rendering?(%__MODULE__{}), do: true

  @doc """
  A range URN spanning two addresses of the same text.

  Built from the **locator text** of each endpoint rather than from a parsed locator,
  because parsing loses locators that contain the range separator themselves.
  SuttaCentral numbers a merged section `53-55.1`; `parse/1` reads that as a range from
  `53` to `55.1`, so a caller that reassembled the endpoints from parsed halves produced
  `mn12@53-53` — an address naming a segment that does not exist and colliding with every
  other chunk in the section. That was the shape of a real defect in three places.

      iex> Pramana.URN.range("pramana:sc.ms:mn12@53-55.1", "pramana:sc.ms:mn12@53-55.9")
      "pramana:sc.ms:mn12@53-55.1-53-55.9"

  The result is not always splittable back into its endpoints — `53-55.1-53-55.9` divides
  at four places — which is `Pramana.Corpus`' problem to solve on the way in, not a reason
  to write a wrong address on the way out.
  """
  @spec range(String.t(), String.t()) :: String.t()
  def range(first_urn, last_urn) when is_binary(first_urn) and is_binary(last_urn) do
    case {String.split(first_urn, "@", parts: 2), String.split(last_urn, "@", parts: 2)} do
      {[base, from], [_, to]} -> base <> "@" <> from <> "-" <> to
      _ -> first_urn
    end
  end

  @doc """
  Every way a range locator could divide into two locators, longest first.

  `53-55.1-53-55.9` is unambiguous to a reader and ambiguous to a parser: four of its
  hyphens could be the separator. Rather than guess, a resolver tries each division and
  keeps the one whose halves are both real addresses — the corpus decides, not the string.
  """
  @spec splits(String.t()) :: [{String.t(), String.t()}]
  def splits(locator) when is_binary(locator) do
    parts = String.split(locator, "-")

    for n <- 1..(length(parts) - 1)//1 do
      {Enum.take(parts, n) |> Enum.join("-"), Enum.drop(parts, n) |> Enum.join("-")}
    end
  end

  @doc """
  The source anchor a rendering URN hangs off — the URN with its fragment removed.

  Every rendering reduces to a citable source anchor. That is the whole point of making
  it a fragment.
  """
  @spec anchor(t()) :: t()
  def anchor(%__MODULE__{} = urn), do: %{urn | rendering: nil, raw: nil}

  @doc """
  True when the URN addresses a range of anchors rather than a single point.
  """
  @spec range?(t()) :: boolean()
  def range?(%__MODULE__{locator_end: nil}), do: false
  def range?(%__MODULE__{}), do: true

  @doc """
  The `source.witness` namespace, used to dispatch to the right locator grammar.
  """
  @spec namespace(t()) :: String.t()
  def namespace(%__MODULE__{source: s, witness: w}), do: "#{s}.#{w}"

  # ---- internals ----

  # A `#` fragment is split off BEFORE anything else, so the locator grammar never has
  # to know renderings exist. `mn1@1.1#tr:en/sujato` and `mn1@1.1` parse to the same
  # anchor by construction rather than by two code paths agreeing.
  defp split_rendering(string) do
    case String.split(string, "#", parts: 2) do
      [base] ->
        {:ok, base, nil}

      [base, @rendering_prefix <> rest] ->
        case String.split(rest, "/", parts: 2) do
          [lang, translator] when lang != "" and translator != "" ->
            {:ok, base, {lang, translator}}

          _ ->
            {:error, :bad_rendering}
        end

      [_base, _other] ->
        {:error, :unknown_fragment}
    end
  end

  defp strip_scheme(@scheme <> ":" <> rest), do: {:ok, rest}
  defp strip_scheme(_), do: {:error, :bad_scheme}

  defp split_once(string, sep, error) do
    case String.split(string, sep, parts: 2) do
      [a, b] -> {:ok, a, b}
      _ -> {:error, error}
    end
  end

  defp parse_work_and_locator(string) do
    case String.split(string, "@", parts: 2) do
      [work] ->
        {:ok, work, nil, nil}

      [work, locator] ->
        {loc, loc_end} = split_range(locator)
        {:ok, work, loc, loc_end}
    end
  end

  # A hyphen separates the two ends of a range. Locator grammars in use
  # (Taishō p0037a13, Derge F.1.b.1, SuttaCentral 1.1) do not themselves contain
  # hyphens, so this is unambiguous — but see the test asserting as much, because if
  # a future source's grammar does use hyphens this is where it breaks.
  defp split_range(locator) do
    case String.split(locator, "-", parts: 2) do
      [loc] -> {loc, nil}
      [loc, loc_end] -> {loc, loc_end}
    end
  end

  defp validate_nonempty(fields) do
    Enum.find_value(fields, :ok, fn {key, value} ->
      if value == "", do: {:error, :"empty_#{key}"}
    end)
  end
end
