defmodule Pramana.Corpus do
  @moduledoc """
  Reading the baked corpus: loading texts, and resolving URNs to spans.

  Every span returned here carries `urn`, offsets, `sha256`, and provenance — the
  decoupling contract in `docs/ARCHITECTURE.md`. Nothing in this module returns
  unattributed text, because the whole point is that a caller (or a model) can never
  obtain a quotation it cannot then verify.
  """

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Repo
  alias Pramana.URN

  # NOTE: Elixir map types are EXACT — `%{a: t}` means those keys and no others. An
  # undeclared key here does not merely under-document, it makes the spec unsatisfiable,
  # and dialyzer then narrows `resolve/1` to its error branch and reports every
  # downstream `verdict == :ok` as impossible. Keep this in step with `to_span/1`.
  @type span :: %{
          urn: String.t(),
          content: String.t(),
          char_start: non_neg_integer(),
          char_end: non_neg_integer(),
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          sha256: String.t(),
          kind: String.t(),
          juan: pos_integer() | nil,
          meta: map(),
          provenance: map()
        }

  @doc """
  Resolves a URN string to a span.

  Accepts untrusted input — an LLM's cited URN, a user's paste — and never raises.
  """
  @spec resolve(String.t()) :: {:ok, span()} | {:error, :bad_urn | :not_found}
  def resolve(urn_string) when is_binary(urn_string) do
    case URN.parse(urn_string) do
      {:ok, _urn} -> fetch_span(urn_string)
      {:error, _} -> {:error, :bad_urn}
    end
  end

  def resolve(_), do: {:error, :bad_urn}

  @doc """
  Resolves several URNs at once, preserving order and reporting each failure.

  Returns `{:ok, results}` where each element is `{urn_string, {:ok, span} | {:error,
  reason}}`. A batch never fails as a whole: the citation guard needs to know exactly
  which citations were bad, not merely that one was.
  """
  @spec resolve_many([String.t()]) :: [{String.t(), {:ok, span()} | {:error, atom()}}]
  def resolve_many(urn_strings) when is_list(urn_strings) do
    Enum.map(urn_strings, fn urn -> {urn, resolve(urn)} end)
  end

  defp fetch_span(urn_string) do
    query =
      from s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where: s.urn == ^urn_string,
        preload: [text: {t, [:work, :witness, :source]}]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      segment -> {:ok, to_span(segment)}
    end
  end

  @doc """
  Builds a span from a loaded segment.

  Public so retrieval returns the identical shape `resolve/1` does — one span shape
  means the guard needs one code path, and a search result is verifiable by exactly
  the same arithmetic as a direct lookup.
  """
  @spec span_from_segment(Segment.t()) :: span()
  def span_from_segment(%Segment{} = segment), do: to_span(segment)

  defp to_span(%Segment{} = segment) do
    %{
      urn: segment.urn,
      content: segment.content,
      char_start: segment.char_start,
      char_end: segment.char_end,
      byte_start: segment.byte_start,
      byte_end: segment.byte_end,
      sha256: segment.content_sha256,
      kind: segment.kind,
      juan: segment.juan,
      meta: segment.meta,
      provenance: provenance(segment)
    }
  end

  @doc """
  The provenance record attached to every span.

  Multi-axis by construction, so a caller can always tell a Kumārajīva translation
  from a Kamakura-period Japanese commentary. `addressing` distinguishes a citation
  checkable against a printed page from a derived one (a locally-added source with no
  canonical page/line grammar) — see `docs/LAYERS.md`.
  """
  @spec provenance(Segment.t()) :: map()
  def provenance(%Segment{text: text} = segment) do
    work = text.work

    %{
      work_id: work.id,
      title: work.title,
      composition_origin: work.composition_origin,
      text_role: work.text_role,
      attributed_author: work.attributed_author,
      attribution_confidence: work.attribution_confidence,
      witness: text.witness_id,
      source: text.source_id,
      license_class: text.source && text.source.license_class,
      volume: text.volume,
      juan: segment.juan,
      page: segment.page,
      register: segment.register,
      line: segment.line,
      addressing: addressing(text.source_id)
    }
  end

  # Locally-added sources have no canonical page/line grammar, so their URNs cannot be
  # checked against a printed edition. Retrieval must surface that difference rather
  # than let a derived reference pass as a canonical one.
  defp addressing("local" <> _), do: "derived"
  defp addressing(_), do: "canonical"

  @doc "Loads a text's full body, used for offset verification."
  @spec body(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def body(urn_prefix) when is_binary(urn_prefix) do
    case Repo.one(from t in Text, where: t.urn_prefix == ^urn_prefix, select: t.body) do
      nil -> {:error, :not_found}
      body -> {:ok, body}
    end
  end
end
