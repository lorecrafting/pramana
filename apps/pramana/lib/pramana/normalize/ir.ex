defmodule Pramana.Normalize.IR do
  @moduledoc """
  The canonical intermediate representation every source normalizes into.

  One IR per text. The unit is the **physical line of the printed edition**, because
  in the Taishō that line is the citation: `<lb n="0001a05"/>` means page 0001,
  register a, line 05, and a scholar checks us by opening the volume to that line.
  See `docs/ARCHITECTURE.md`, Stage 1.
  """

  defmodule Line do
    @moduledoc "One physical line of a printed edition, with everything attached to it."

    @type kind :: :prose | :verse | :head

    @type t :: %__MODULE__{
            anchor: String.t(),
            juan: pos_integer() | nil,
            kind: kind(),
            text: String.t(),
            notes: [String.t()],
            apparatus: [map()],
            gaiji: [String.t()],
            editorial_punctuation: boolean()
          }

    @enforce_keys [:anchor, :text]
    defstruct anchor: nil,
              juan: nil,
              kind: :prose,
              text: "",
              notes: [],
              apparatus: [],
              gaiji: [],
              editorial_punctuation: false
  end

  @type t :: %__MODULE__{
          work_id: String.t(),
          canon: String.t(),
          volume: pos_integer() | nil,
          number: String.t() | nil,
          title: String.t() | nil,
          title_original: String.t() | nil,
          author: String.t() | nil,
          license_notice: String.t() | nil,
          juan_count: non_neg_integer(),
          gaiji: %{String.t() => map()},
          lines: [Line.t()],
          unanchored_apparatus: [map()]
        }

  @enforce_keys [:work_id, :canon]
  defstruct work_id: nil,
            canon: nil,
            volume: nil,
            number: nil,
            title: nil,
            title_original: nil,
            author: nil,
            license_notice: nil,
            juan_count: 0,
            gaiji: %{},
            lines: [],
            unanchored_apparatus: []

  @doc """
  The full body text, lines joined by newline.

  Segment `char_start`/`char_end` offsets are into exactly this string, so it must be
  built the same way everywhere. That is why it lives here rather than at each call
  site.
  """
  @spec body(t()) :: String.t()
  def body(%__MODULE__{lines: lines}) do
    Enum.map_join(lines, "\n", & &1.text)
  end

  @doc "Counts lines whose text is non-empty."
  @spec content_line_count(t()) :: non_neg_integer()
  def content_line_count(%__MODULE__{lines: lines}) do
    Enum.count(lines, &(&1.text != ""))
  end

  @doc """
  Total apparatus entries, attached and unattached.

  Used to prove nothing was dropped: this must equal the number of `<app>` elements
  in the source. Silent loss in the apparatus is exactly the class of bug that makes
  a critical edition untrustworthy.
  """
  @spec apparatus_count(t()) :: non_neg_integer()
  def apparatus_count(%__MODULE__{lines: lines, unanchored_apparatus: orphans}) do
    Enum.sum(Enum.map(lines, &length(&1.apparatus))) + length(orphans)
  end
end
