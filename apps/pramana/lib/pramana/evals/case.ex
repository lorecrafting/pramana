defmodule Pramana.Evals.Case do
  @moduledoc """
  One gold-set question, and what a correct answer to it looks like.

  Cases are JSONL — one per line — so a malformed case fails alone rather than taking the
  file with it, and a diff names exactly which question changed.

  Every case carries a `source` field naming **how its expected answer was established**.
  That is not documentation: a published number is only meaningful if a reader can see
  where the ground truth came from, and a case whose provenance is "someone thought so"
  should be visible as such next to one whose provenance is SuttaCentral's curated
  parallels.
  """

  @type type :: :retrieval | :quote_verify | :quote_reject | :provenance | :absence

  @type t :: %__MODULE__{
          id: String.t(),
          type: type(),
          query: String.t() | nil,
          urn: String.t() | nil,
          quote: String.t() | nil,
          expect_urns: [String.t()],
          expect_provenance: map(),
          forbid_works: [String.t()],
          expect_empty: boolean(),
          k: pos_integer(),
          search_opts: keyword(),
          tradition: String.t() | nil,
          adversarial: boolean(),
          source: String.t() | nil,
          note: String.t() | nil,
          origin: {String.t(), pos_integer()}
        }

  defstruct [
    :id,
    :type,
    :query,
    :urn,
    :quote,
    :tradition,
    :source,
    :note,
    :origin,
    expect_urns: [],
    expect_provenance: %{},
    forbid_works: [],
    expect_empty: false,
    k: 10,
    search_opts: [],
    adversarial: false
  ]

  # Literal atoms, for the reason given at `@provenance_keys`: `String.to_existing_atom/1`
  # depends on what the VM has already loaded, which makes it a load-order bug waiting to
  # happen rather than a validation.
  @type_map %{
    "retrieval" => :retrieval,
    "quote_verify" => :quote_verify,
    "quote_reject" => :quote_reject,
    "provenance" => :provenance,
    "absence" => :absence
  }

  @types Map.keys(@type_map)

  @doc "The recognised case types."
  @spec types() :: [String.t()]
  def types, do: @types

  @doc "The atom for a case-type name."
  @spec type_atom(String.t()) :: type()
  def type_atom(name), do: Map.fetch!(@type_map, name)

  @doc """
  Parses one JSONL line into a case, raising with the file and line on bad input.

  Raising rather than skipping: a gold set that silently drops the cases it cannot parse
  reports a score over fewer questions than it claims, which is a quiet way to make a
  number look better than it is.
  """
  @spec parse!(String.t(), String.t(), pos_integer()) :: t()
  def parse!(line, path, line_number) do
    data = Jason.decode!(line)
    type_name = fetch!(data, "type", path, line_number)

    type =
      case Map.fetch(@type_map, type_name) do
        {:ok, type} ->
          type

        :error ->
          raise ArgumentError, "#{path}:#{line_number}: unknown case type #{inspect(type_name)}"
      end

    %__MODULE__{
      id: fetch!(data, "id", path, line_number),
      type: type,
      query: data["query"],
      urn: data["urn"],
      quote: data["quote"],
      expect_urns: List.wrap(data["expect_urns"] || data["expect_urn"]),
      expect_provenance: atomize(data["expect_provenance"] || %{}),
      forbid_works: List.wrap(data["forbid_works"] || []),
      expect_empty: data["expect_empty"] == true,
      k: data["k"] || 10,
      search_opts: search_opts(data["search_opts"] || %{}),
      tradition: data["tradition"],
      adversarial: data["adversarial"] == true,
      source: data["source"],
      note: data["note"],
      origin: {path, line_number}
    }
  end

  defp fetch!(data, key, path, line) do
    case Map.fetch(data, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{path}:#{line}: missing #{inspect(key)}"
    end
  end

  # Provenance keys are atoms in a span, and the gold set is JSON. Mapped through LITERAL
  # atoms rather than `String.to_existing_atom/1`, which is the third time this codebase
  # has been caught by that function: it raises unless the atom already exists, and
  # whether it exists depends on which modules the VM happens to have loaded — so the
  # same input works after a search and fails on a cold start. A literal map creates the
  # atoms at compile time and cannot be surprised. It also keeps the property that
  # matters: gold-set data can never mint an atom.
  @provenance_keys %{
    "composition_origin" => :composition_origin,
    "text_role" => :text_role,
    "attribution_confidence" => :attribution_confidence,
    "addressing" => :addressing,
    "division" => :division,
    "source" => :source,
    "witness" => :witness,
    "license_class" => :license_class,
    "work_id" => :work_id
  }

  defp atomize(map) do
    Map.new(map, fn {k, v} ->
      case Map.fetch(@provenance_keys, k) do
        {:ok, key} -> {key, v}
        :error -> raise ArgumentError, "unknown provenance key #{inspect(k)} in gold case"
      end
    end)
  end

  # Search options likewise: an explicit map, because `String.to_existing_atom/1` on a
  # caller-supplied key has crashed this codebase twice on module load order.
  @search_keys %{
    "origin" => :origin,
    "role" => :role,
    "division" => :division,
    "work_id" => :work_id,
    "exclude_origin" => :exclude_origin,
    "redistributable_only" => :redistributable_only,
    "license_class" => :license_class,
    "vector_kinds" => :vector_kinds,
    "mode" => :mode,
    "lexical_only" => :lexical_only,
    "semantic_only" => :semantic_only
  }

  defp search_opts(map) do
    Enum.map(map, fn {k, v} ->
      case Map.fetch(@search_keys, k) do
        {:ok, key} -> {key, decode_value(key, v)}
        :error -> raise ArgumentError, "unknown search option #{inspect(k)} in gold case"
      end
    end)
  end

  # `mode` is an atom in the retriever's API and a string in JSON.
  defp decode_value(:mode, value) when is_binary(value) do
    case value do
      "auto" -> :auto
      "phrase" -> :phrase
      "ngram" -> :ngram
      "terms" -> :terms
      other -> raise ArgumentError, "unknown search mode #{inspect(other)} in gold case"
    end
  end

  defp decode_value(_key, value), do: value
end
