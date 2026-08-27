defmodule Pramana.Normalize.IR do
  @moduledoc """
  The canonical intermediate representation every source normalizes into.

  One IR per text. The unit is the **physical line of the printed edition**, because
  in the Taishō that line is the citation: `<lb n="0001a05"/>` means page 0001,
  register a, line 05, and a scholar checks us by opening the volume to that line.
  See `docs/ARCHITECTURE.md`, Stage 1.
  """

  defmodule Line do
    @moduledoc """
    One physical line of a printed edition, with everything attached to it.

    `volume` is set only when a work spans more than one printed volume, and it exists
    because the anchor stops being unique there. In CBETA's X collection page numbering
    restarts at each volume: X1571's two files share **22,616 identical
    page/register/line anchors**, so `0402c01` alone names two different printed lines.
    A single-volume work leaves it `nil` — the anchor is already unambiguous and
    stamping a volume on every line would add a column that means nothing.
    """

    @type kind :: :prose | :verse | :head

    @type t :: %__MODULE__{
            anchor: String.t(),
            juan: pos_integer() | nil,
            kind: kind(),
            text: String.t(),
            notes: [String.t()],
            apparatus: [map()],
            gaiji: [String.t()],
            editorial_punctuation: boolean(),
            volume: pos_integer() | nil
          }

    @enforce_keys [:anchor, :text]

    @struct_fields [
      anchor: nil,
      juan: nil,
      kind: :prose,
      text: "",
      notes: [],
      apparatus: [],
      gaiji: [],
      editorial_punctuation: false,
      volume: nil
    ]

    defstruct @struct_fields

    # Which fields say WHERE the line is and how it is set, rather than what was printed
    # on it. Everything else is content, by subtraction — so a new kind of content is
    # content the moment it is added to the struct, and only a new piece of *metadata*
    # needs this list touched. Forgetting to add one here keeps a line addressable that
    # could have been skipped, which is the harmless direction; the other way round
    # deletes printed text from the corpus.
    @metadata [:anchor, :juan, :kind, :editorial_punctuation, :volume]
    @content @struct_fields |> Keyword.keys() |> Kernel.--(@metadata)

    @doc """
    Whether nothing at all was printed on this line but its number.

    **The one definition.** It has been written out by hand three times and been wrong
    every time, because each version listed the kinds of content that existed when it
    was written: text only (pipeline v2 dropped 5,213 note-only lines), then text and
    notes (v3 dropped 10,590 lines to a `<note>` spanning `<lb/>`), then text, notes and
    apparatus — which dropped the one line in CBETA whose entire printed content is a
    rare character, X0575 0966b12, 䦚. A gaiji-only line has empty `text` because gaiji
    are recorded as a mapping rather than substituted into the body, so it matched
    "nothing was printed here" exactly.

    A blank line is the only line that may be dropped without a URN (`CLAUDE.md`
    invariant 1, and rule 3 in `docs/STATUS.md`).
    """
    @spec blank?(t()) :: boolean()
    def blank?(%__MODULE__{} = line) do
      Enum.all?(@content, fn field -> empty?(Map.fetch!(line, field)) end)
    end

    defp empty?(""), do: true
    defp empty?([]), do: true
    defp empty?(nil), do: true
    defp empty?(_), do: false
  end

  @type t :: %__MODULE__{
          work_id: String.t(),
          canon: String.t(),
          volume: pos_integer() | nil,
          volumes: [pos_integer()],
          number: String.t() | nil,
          title: String.t() | nil,
          title_original: String.t() | nil,
          author: String.t() | nil,
          license_notice: String.t() | nil,
          juan_count: non_neg_integer(),
          foreign_lb: non_neg_integer(),
          gaiji: %{String.t() => map()},
          lines: [Line.t()],
          unanchored_apparatus: [map()],
          outline: [map()]
        }

  @enforce_keys [:work_id, :canon]
  defstruct work_id: nil,
            canon: nil,
            volume: nil,
            # Every printed volume this IR was assembled from, in printed order. Empty
            # for an IR normalized from a single file, where `volume` already says
            # which one; populated only by `concat/1`.
            volumes: [],
            number: nil,
            title: nil,
            title_original: nil,
            author: nil,
            license_notice: nil,
            juan_count: 0,
            # `<lb/>` markers belonging to ANOTHER edition's lineation, skipped rather
            # than lost. An X file carries its own `ed="X"` lines beside the earlier
            # 卍續藏經 reprint's `ed="R055"`, and only one of them is this text's. The
            # count is carried so a fidelity check can reconcile against the raw file:
            # every `<lb/>` in the body is either a line here or one of these, and
            # without the number, filtering half of them away is indistinguishable from
            # dropping half of them.
            foreign_lb: 0,
            gaiji: %{},
            lines: [],
            unanchored_apparatus: [],
            outline: []

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

  @doc """
  Assembles one work from the several printed volumes it runs across.

  ## Why this exists

  A volume is a unit of *printing*, not a unit of *work*, and the loader replaces a
  work's segments rather than appending to them — so baking one job per file silently
  discards every volume but the last to finish. That defect has now been found twice:
  75 of 1,195 Derge works (fixed in `Derge.Edition`) and 6 CBETA X works, where
  X0240, X0367, X0714, X0822, X1568 and X1571 each reuse one work number across two
  volume files. **The Taishō hid it** because CBETA gives its split works distinct ids
  (`T0220a`, `T0220b`); X reuses the number.

  It is worse than losing half a text, because which half survives depends on which
  Oban job finished last: the baked corpus kept volume 8 of X0240 and volume 82 of
  X1571 — first and second respectively. Two bakes of the same `sources.lock.json`
  could therefore differ while reporting one `bake_id`, which is the one thing a
  `bake_id` is for.

  ## What it assumes, and what it checks

  Callers must pass the volumes **in printed order**; this concatenates, it does not
  sort, because printed order is a property of the edition and not of the file names.

  Anchors are NOT rewritten. In CBETA's X the juan numbering runs continuously across
  the volume break (X08n0240 ends at juan 44, X09n0240 opens at juan 45) and the URN
  carries the juan, so the assembled work has no duplicate URNs — verified across all
  six spanning works: zero juan+anchor collisions. Each line keeps a `volume` instead,
  so the 22,616 anchors X1571 repeats between its volumes stay distinguishable in
  print terms as well as in the URN.

  Raises when the parts disagree about which work they are, since that means the
  caller grouped the wrong files together and a silently concatenated wrong text is
  the worst possible outcome.
  """
  @spec concat([t()]) :: t()
  def concat([%__MODULE__{} = only]), do: only

  def concat([%__MODULE__{} = first | _] = parts) do
    Enum.each(parts, fn part ->
      if part.work_id != first.work_id or part.canon != first.canon do
        raise ArgumentError,
              "cannot assemble #{first.canon}/#{first.work_id} from a part belonging to " <>
                "#{part.canon}/#{part.work_id} — the caller grouped unrelated files"
      end
    end)

    lines =
      Enum.flat_map(parts, fn part -> Enum.map(part.lines, &stamp_volume(&1, part.volume)) end)

    %__MODULE__{
      first
      | volumes: Enum.map(parts, & &1.volume),
        lines: lines,
        # Counted from the assembled lines rather than summed. The juan run continues
        # across the break, and X0714's juan 3 appears in BOTH its volumes, so summing
        # each part's count would report 5 fascicles for a 4-fascicle work.
        juan_count:
          lines |> Enum.map(& &1.juan) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length(),
        foreign_lb: Enum.sum(Enum.map(parts, & &1.foreign_lb)),
        gaiji: Enum.reduce(parts, %{}, &Map.merge(&2, &1.gaiji)),
        unanchored_apparatus: Enum.flat_map(parts, & &1.unanchored_apparatus),
        outline: Enum.flat_map(parts, & &1.outline)
    }
  end

  # A line already carrying a volume keeps it: assembling an assembled work must not
  # relabel its parts.
  defp stamp_volume(%Line{volume: nil} = line, volume), do: %Line{line | volume: volume}
  defp stamp_volume(%Line{} = line, _volume), do: line

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
