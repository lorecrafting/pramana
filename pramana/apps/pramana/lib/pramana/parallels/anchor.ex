defmodule Pramana.Parallels.Anchor do
  @moduledoc """
  Turns a SuttaCentral text reference into a Taishō anchor this corpus can resolve.

  SuttaCentral's `text_extra_info.json` gives every text an `acronym` and a `volpage`:

      sa1    acronym "SA 1"   alt_acronym "T 99.1"   volpage "T ii 001a06"

  That volpage is the Taishō **volume, page, register and line** — the same coordinates
  our URNs use. So `sa1` is not merely "related to" something in our corpus; it *is*
  `pramana:cbeta.T:T0099_…@p0001a06`, and a parallel pointing at it lands on a passage a
  reader can open.

  ## Three printed shapes, all real

  | shape | example | count |
  |---|---|---|
  | plain | `T ii 001a06` | 2,862 |
  | with a sub-text number | `T xvii 765.1 0663a03` | 1,832 |
  | a range | `T xxiii 692b01–694a27` | ~100 |

  The range form is kept as a range, because our URN grammar already carries one and
  flattening it to its first line would silently narrow a citation that the source
  states as spanning pages.

  ## Volume numbers are Roman, and that is not decoration

  `T ii` is volume 2. Parsing it wrongly does not fail loudly — it produces a *valid*
  anchor pointing at the wrong volume, which is the failure mode this project cares
  about most. Hence an explicit table rather than a clever algorithm.
  """

  @roman %{
    "i" => 1,
    "ii" => 2,
    "iii" => 3,
    "iv" => 4,
    "v" => 5,
    "vi" => 6,
    "vii" => 7,
    "viii" => 8,
    "ix" => 9,
    "x" => 10,
    "xi" => 11,
    "xii" => 12,
    "xiii" => 13,
    "xiv" => 14,
    "xv" => 15,
    "xvi" => 16,
    "xvii" => 17,
    "xviii" => 18,
    "xix" => 19,
    "xx" => 20,
    "xxi" => 21,
    "xxii" => 22,
    "xxiii" => 23,
    "xxiv" => 24,
    "xxv" => 25,
    "xxvi" => 26,
    "xxvii" => 27,
    "xxviii" => 28,
    "xxix" => 29,
    "xxx" => 30,
    "xxxi" => 31,
    "xxxii" => 32,
    "xxxiii" => 33,
    "xxxiv" => 34,
    "xxxv" => 35,
    "xxxvi" => 36,
    "xxxvii" => 37,
    "xxxviii" => 38,
    "xxxix" => 39,
    "xl" => 40,
    "xli" => 41,
    "xlii" => 42,
    "xliii" => 43,
    "xliv" => 44,
    "xlv" => 45,
    "xlvi" => 46,
    "xlvii" => 47,
    "xlviii" => 48,
    "xlix" => 49,
    "l" => 50,
    "li" => 51,
    "lii" => 52,
    "liii" => 53,
    "liv" => 54,
    "lv" => 55,
    "lxxxv" => 85
  }

  # `T ii 001a06` and `T xvii 765.1 0663a03` — the optional middle group is a sub-text
  # number, not part of the page.
  @plain ~r/^T\s+([ivxl]+)\s+(?:[\d.]+\s+)?(\d{3,4})([abc])(\d{1,2})$/u
  # `T xxiii 692b01–694a27`. The `u` flag is REQUIRED: the separator is an en dash
  # (U+2013), and without it PCRE reads the pattern as bytes, so the three UTF-8 bytes
  # of the dash become three separate members of the character class and the range never
  # matches. It failed silently — 1 range parsed instead of ~100.
  @range ~r/^T\s+([ivxl]+)\s+(\d{3,4})([abc])(\d{1,2})[–-](\d{3,4})([abc])(\d{1,2})$/u
  # `T 99.1` or `T 792` — the Taishō text number, from acronym or alt_acronym.
  @acronym ~r/^T\s+(\d+[A-Za-z]?)(?:\.\S+)?$/u

  @type t :: %{
          volume: pos_integer(),
          work_id: String.t(),
          page: String.t(),
          register: String.t(),
          line: pos_integer(),
          page_end: String.t() | nil,
          register_end: String.t() | nil,
          line_end: pos_integer() | nil
        }

  @doc """
  Parses one `text_extra_info` entry into an anchor, or `nil`.

  `nil` is the honest answer for the many entries that carry a PTS reference rather than
  a Taishō one — a Pāli sutta has no Taishō page, and inventing one would be worse than
  having none.
  """
  @spec from_entry(map()) :: t() | nil
  def from_entry(entry) do
    with {:ok, work_id} <- work_id(entry),
         {:ok, parsed} <- volpage(entry["volpage"]) do
      Map.put(parsed, :work_id, work_id)
    else
      _ -> nil
    end
  end

  # `alt_acronym` carries the Taishō number for an Āgama text ("T 99.1" for SA 1);
  # `acronym` carries it for a text cited by Taishō number directly ("T 792").
  defp work_id(entry) do
    [entry["alt_acronym"], entry["acronym"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn acronym ->
      case Regex.run(@acronym, String.trim(acronym)) do
        [_, number] -> {:ok, "T" <> pad_number(number)}
        _ -> nil
      end
    end)
    |> case do
      nil -> :error
      ok -> ok
    end
  end

  # A Taishō number may carry a letter suffix — 150A, 220a — and CBETA uses both cases,
  # so the suffix is preserved as printed. Only the DIGITS are padded: padding "150A" as
  # a whole leaves it at four characters and yields T150A, which is well-formed and
  # matches nothing. That silently lost 71 anchors.
  defp pad_number(number) do
    case Regex.run(~r/^(\d+)([A-Za-z]?)$/u, number) do
      [_, digits, suffix] -> String.pad_leading(digits, 4, "0") <> suffix
      _ -> number
    end
  end

  defp volpage(nil), do: :error

  defp volpage(volpage) do
    volpage = String.trim(volpage)

    cond do
      match = Regex.run(@range, volpage) -> parse_range(match)
      match = Regex.run(@plain, volpage) -> parse_plain(match)
      true -> :error
    end
  end

  defp parse_plain([_, roman, page, register, line]) do
    with {:ok, volume} <- volume(roman) do
      {:ok,
       %{
         volume: volume,
         page: page,
         register: register,
         line: String.to_integer(line),
         page_end: nil,
         register_end: nil,
         line_end: nil
       }}
    end
  end

  defp parse_range([_, roman, page, register, line, page_end, register_end, line_end]) do
    with {:ok, volume} <- volume(roman) do
      {:ok,
       %{
         volume: volume,
         page: page,
         register: register,
         line: String.to_integer(line),
         page_end: page_end,
         register_end: register_end,
         line_end: String.to_integer(line_end)
       }}
    end
  end

  defp volume(roman) do
    case Map.fetch(@roman, String.downcase(roman)) do
      {:ok, volume} -> {:ok, volume}
      :error -> :error
    end
  end

  @doc "The Taishō locator an anchor starts at, e.g. `p0001a06`."
  @spec locator(t()) :: String.t()
  def locator(anchor),
    do: "p#{pad_page(anchor.page)}#{anchor.register}#{pad(anchor.line)}"

  @doc "The locator an anchor ends at, or `nil` when it is a single line."
  @spec locator_end(t()) :: String.t() | nil
  def locator_end(%{page_end: nil}), do: nil

  def locator_end(anchor),
    do: "p#{pad_page(anchor.page_end)}#{anchor.register_end}#{pad(anchor.line_end)}"

  defp pad(line), do: line |> Integer.to_string() |> String.pad_leading(2, "0")

  # SuttaCentral writes a page below 1000 with three digits ("001a06"); the Taishō
  # citation, and therefore our URN, uses four ("0001a06"). Getting this wrong produces
  # a well-formed URN that resolves to nothing.
  defp pad_page(page), do: String.pad_leading(page, 4, "0")
end
