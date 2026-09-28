defmodule Pramana.Normalize.Tei84000.Glossary do
  @moduledoc """
  The glossary a translator publishes with a translation.

  Every 84000 file ends with one: a list of terms, each giving the English chosen, the
  Sanskrit behind it, the Tibetan the Degé actually prints, and often a note explaining the
  choice. 58,820 entries across the published Kangyur — 16,767 distinct Sanskrit terms and
  25,526 Tibetan — which is the Skt–Tib anchor set Phase 5 asks for, made by the people who
  did the translating.

  ## Each term says how it is known, and that is not decoration

      Tibetan   attestedSource       23,252    the Tibetan text says this
      Sanskrit  sourceUnspecified    22,442    reconstructed; no Sanskrit witness says it
      Sanskrit  attestedSource          575    a Sanskrit witness does say it
      Sanskrit  attestedDictionary      472    a lexicon says it

  **Most of the Sanskrit is a reconstruction.** `yūpa` beside `མཆོད་སྡོང་།` is a scholar's
  inference about what stood in a lost Indic original, not a quotation from one, and 84000
  is careful to say so. Storing the two identically would flatten that into a claim the
  edition does not make — the same failure `composition_origin` exists to prevent, one
  layer down. So the attestation travels with the term.

  ## What is not taken

  The English `translationMain` is the term as this translator rendered it; alternatives
  are kept separately rather than merged, because "pillar" and "pillars" are one decision
  and "pillar / sacrificial post" would be two.
  """

  @behaviour Saxy.Handler

  @typedoc "One glossed term, with each language's attestation."
  @type entry :: %{
          gloss_id: String.t() | nil,
          english: String.t() | nil,
          english_alternatives: [String.t()],
          sanskrit: String.t() | nil,
          sanskrit_attestation: String.t() | nil,
          tibetan: String.t() | nil,
          wylie: String.t() | nil,
          tibetan_attestation: String.t() | nil,
          chinese: String.t() | nil,
          chinese_attestation: String.t() | nil,
          pali: String.t() | nil,
          definition: String.t() | nil
        }

  # 84000's vocabulary for how a term is known, mapped to this corpus's. `attestedOther`
  # and an absent type both mean "the edition did not say a source", which is different
  # from `sourceUnspecified` only in wording.
  @attestation %{
    "attestedSource" => "source",
    "attestedDictionary" => "dictionary",
    "attestedOther" => "other",
    "sourceUnspecified" => "unspecified"
  }

  @doc """
  Every glossed term in one translation file.

  Returns `{:ok, entries}` — the glossary only, ignoring the translation itself, which is
  `Pramana.Normalize.Tei84000`'s job.
  """
  @spec parse(binary() | Enumerable.t()) :: {:ok, [entry()]} | {:error, term()}
  def parse(xml) do
    state = %{
      depth: 0,
      glossary_depth: nil,
      gloss: nil,
      term: nil,
      note?: false,
      buffer: nil,
      entries: []
    }

    with {:ok, final} <- run(xml, state), do: {:ok, Enum.reverse(final.entries)}
  end

  defp run(xml, state) when is_binary(xml), do: Saxy.parse_string(xml, __MODULE__, state)
  defp run(stream, state), do: Saxy.parse_stream(stream, __MODULE__, state)

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:end_document, _data, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attrs}, state) do
    state = %{state | depth: state.depth + 1}
    {:ok, start(local(name), Map.new(attrs), state)}
  end

  @impl Saxy.Handler
  def handle_event(:end_element, name, state) do
    {:ok, %{finish(local(name), state) | depth: state.depth - 1}}
  end

  @impl Saxy.Handler
  def handle_event(:characters, _text, %{buffer: nil} = state), do: {:ok, state}

  def handle_event(:characters, text, state), do: {:ok, %{state | buffer: state.buffer <> text}}

  defp local(name), do: name |> String.split(":") |> List.last()

  defp start("div", %{"type" => "glossary"}, state),
    do: %{state | glossary_depth: state.depth}

  defp start("gloss", attrs, %{glossary_depth: d} = state) when not is_nil(d),
    do: %{state | gloss: empty(attrs["xml:id"])}

  defp start("term", attrs, %{gloss: gloss} = state) when not is_nil(gloss),
    do: %{state | term: {attrs["xml:lang"] || "en", attrs["type"]}, buffer: ""}

  # The definition is prose, and it belongs to the gloss rather than to any one language.
  defp start("note", %{"type" => "definition"}, %{gloss: gloss} = state) when not is_nil(gloss),
    do: %{state | note?: true, buffer: ""}

  defp start(_name, _attrs, state), do: state

  defp finish("div", %{glossary_depth: d} = state) when d == state.depth,
    do: %{state | glossary_depth: nil}

  defp finish("gloss", %{gloss: gloss} = state) when not is_nil(gloss) do
    %{state | gloss: nil, entries: [finalise(gloss) | state.entries]}
  end

  defp finish("term", %{term: {lang, type}, gloss: gloss} = state) when not is_nil(gloss) do
    %{state | term: nil, buffer: nil, gloss: put_term(gloss, lang, type, squeeze(state.buffer))}
  end

  defp finish("note", %{note?: true, gloss: gloss} = state) when not is_nil(gloss),
    do: %{state | note?: false, buffer: nil, gloss: %{gloss | definition: squeeze(state.buffer)}}

  defp finish(_name, state), do: state

  defp empty(gloss_id) do
    %{
      gloss_id: gloss_id,
      english: nil,
      english_alternatives: [],
      sanskrit: nil,
      sanskrit_attestation: nil,
      tibetan: nil,
      wylie: nil,
      tibetan_attestation: nil,
      chinese: nil,
      chinese_attestation: nil,
      pali: nil,
      definition: nil
    }
  end

  defp put_term(gloss, _lang, _type, ""), do: gloss
  defp put_term(gloss, _lang, _type, nil), do: gloss

  defp put_term(gloss, "en", "translationAlternative", text),
    do: %{gloss | english_alternatives: gloss.english_alternatives ++ [text]}

  # An `en` term with no type is the main rendering when there is no other; a second one
  # is an alternative. Taking the first keeps the translator's own ordering.
  defp put_term(%{english: nil} = gloss, "en", _type, text), do: %{gloss | english: text}

  defp put_term(gloss, "en", _type, text),
    do: put_term(gloss, "en", "translationAlternative", text)

  defp put_term(%{sanskrit: nil} = gloss, "Sa-Ltn", type, text),
    do: %{gloss | sanskrit: text, sanskrit_attestation: attestation(type)}

  defp put_term(%{tibetan: nil} = gloss, "bo", type, text),
    do: %{gloss | tibetan: text, tibetan_attestation: attestation(type)}

  defp put_term(%{wylie: nil} = gloss, "Bo-Ltn", _type, text), do: %{gloss | wylie: text}

  defp put_term(%{chinese: nil} = gloss, "zh", type, text),
    do: %{gloss | chinese: text, chinese_attestation: attestation(type)}

  defp put_term(%{pali: nil} = gloss, "Pi-Ltn", _type, text), do: %{gloss | pali: text}

  # A second term in a language this already has is an attested variant of the same
  # entry, not a new entry: the same gloss can list two Tibetan spellings.
  defp put_term(gloss, _lang, _type, _text), do: gloss

  defp attestation(type), do: Map.get(@attestation, type, "unspecified")

  # An alternative that repeats the main rendering is not an alternative. 84000 lists the
  # same English twice when a term is glossed in more than one place in the text, and
  # storing "higher knowledge" as an alternative to "higher knowledge" would report a
  # choice where there was none.
  defp finalise(gloss) do
    %{
      gloss
      | english_alternatives:
          gloss.english_alternatives |> Enum.uniq() |> List.delete(gloss.english)
    }
  end

  defp squeeze(nil), do: nil

  defp squeeze(text) do
    case text |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
