defmodule Pramana.Normalize.Derge.Audit do
  @moduledoc """
  Counts what a Derge volume contains, without knowing anything about how it is parsed.

  `Pramana.Normalize.Derge` decides what a line is, which work it belongs to, and what to
  drop. This module decides nothing: it adds up the character data inside `<text>` and
  says how much of it appears before the volume's first `toh` marker. Deliberately dumb,
  because a fidelity check computed by the same logic that did the parsing agrees with
  itself by construction — which is exactly how 146,962 lines went missing while every
  number the parser reported looked healthy (`docs/HISTORY.md`).

  Bytes rather than characters, and whitespace stripped, so the count survives the two
  things that make Tibetan character counts unstable: combining vowel signs, which make
  graphemes and codepoints disagree, and the TEI's pretty-printing indentation, which the
  normalizer trims away.
  """

  @behaviour Saxy.Handler

  @typedoc """
  What a volume holds.

    * `:text_bytes` — all of it, inside `<text>`
    * `:preamble_bytes` — the part before the first `<milestone unit="text">`, which
      belongs to no Tōhoku number unless a work is running into this volume from the last
  """
  @type census :: %{text_bytes: non_neg_integer(), preamble_bytes: non_neg_integer()}

  @spec census(binary() | Enumerable.t()) :: {:ok, census()} | {:error, term()}
  def census(xml) do
    state = %{in_text?: false, seen_marker?: false, text_bytes: 0, preamble_bytes: 0}

    with {:ok, final} <- parse(xml, state) do
      {:ok, Map.take(final, [:text_bytes, :preamble_bytes])}
    end
  end

  defp parse(xml, state) when is_binary(xml), do: Saxy.parse_string(xml, __MODULE__, state)
  defp parse(stream, state), do: Saxy.parse_stream(stream, __MODULE__, state)

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:end_document, _data, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attrs}, state) do
    case local(name) do
      "text" -> {:ok, %{state | in_text?: true}}
      "milestone" -> {:ok, marker(Map.new(attrs), state)}
      _ -> {:ok, state}
    end
  end

  @impl Saxy.Handler
  def handle_event(:end_element, _name, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:characters, _text, %{in_text?: false} = state), do: {:ok, state}

  def handle_event(:characters, text, state) do
    bytes = byte_size(String.replace(text, ~r/\s/u, ""))

    {:ok,
     %{
       state
       | text_bytes: state.text_bytes + bytes,
         preamble_bytes: state.preamble_bytes + if(state.seen_marker?, do: 0, else: bytes)
     }}
  end

  defp marker(%{"unit" => "text"}, state), do: %{state | seen_marker?: true}
  defp marker(_attrs, state), do: state

  defp local(name), do: name |> String.split(":") |> List.last()
end
