defmodule Pramana.Corpus do
  @moduledoc """
  Reading the baked corpus: loading texts, and resolving URNs to spans.

  Every span returned here carries `urn`, offsets, `sha256`, and provenance — the
  decoupling contract in `docs/ARCHITECTURE.md`. Nothing in this module returns
  unattributed text, because the whole point is that a caller (or a model) can never
  obtain a quotation it cannot then verify.
  """

  import Ecto.Query

  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Provenance
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

  Handles both point URNs (`…@p0001c17`) and **ranges** (`…@p0001c17-p0001c21`). The
  URN grammar has always allowed ranges, but until ranges resolved here a model citing
  one got `:not_found` — safe, since the guard rejected it, but wrong: a range is a
  legitimate citation and a passage worth quoting is usually longer than one printed
  line.
  """
  @spec resolve(String.t()) :: {:ok, span()} | {:error, :bad_urn | :not_found}
  def resolve(urn_string) when is_binary(urn_string) do
    case URN.parse(urn_string) do
      # A rendering URN resolves to a translation layer, which carries `method` — so a
      # generated rendering quoted as scripture reaches the guard's invariant-#7 check
      # through the ordinary resolve path rather than a separate one someone has to
      # remember to call.
      {:ok, %URN{rendering: r}} when not is_nil(r) -> Pramana.Translations.resolve(urn_string)
      {:ok, %URN{locator_end: nil}} -> fetch_span(urn_string)
      {:ok, %URN{} = urn} -> fetch_range(urn)
      {:error, _} -> {:error, :bad_urn}
    end
  end

  def resolve(_), do: {:error, :bad_urn}

  @doc """
  A passage with its neighbours, so it can be read rather than merely located.

  Taishō lines are typographic, not syntactic — they break mid-sentence — so a single
  segment is often unreadable on its own. Every returned neighbour is a full span and
  independently verifiable; `text` is a reading convenience, and `urn` is the range URN
  covering the whole window, which `resolve/1` can verify as a unit.
  """
  @spec context(String.t(), keyword()) :: {:ok, map()} | {:error, :bad_urn | :not_found}
  def context(urn_string, opts \\ []) do
    before_n = opts |> Keyword.get(:before, 2) |> clamp(0, 50)
    after_n = opts |> Keyword.get(:after, 2) |> clamp(0, 50)

    with {:ok, focus} <- resolve(urn_string),
         {:ok, first, last} <- focus_segments(urn_string) do
      neighbours =
        Repo.all(
          from s in Segment,
            join: t in Text,
            on: t.id == s.text_id,
            where:
              s.text_id == ^first.text_id and
                s.ordinal >= ^(first.ordinal - before_n) and
                s.ordinal <= ^(last.ordinal + after_n),
            order_by: s.ordinal,
            preload: [text: ^Text.preload_without_body()]
        )

      # SPLIT BY ORDINAL, NOT BY URN EQUALITY. A range URN equals no segment's URN, so
      # `split_while(&1.urn != focus.urn)` consumed the whole window and returned everything
      # as `before` with nothing after. It never got that far in practice, because
      # `fetch_segment/1` rejected the range first and the caller received `:not_found` —
      # including `Guard.spans_boundary?`, which then reported "does not span a line
      # boundary" for every ranged citation, which is exactly when it matters. Ordinals work
      # for a point and a range alike.
      {before_segments, rest} = Enum.split_with(neighbours, &(&1.ordinal < first.ordinal))
      after_segments = Enum.filter(rest, &(&1.ordinal > last.ordinal))
      spans = Enum.map(neighbours, &to_span/1)

      {:ok,
       %{
         focus: focus,
         before: Enum.map(before_segments, &to_span/1),
         after: Enum.map(after_segments, &to_span/1),
         text: Enum.map_join(spans, "", & &1.content),
         urn: range_urn(spans),
         segment_count: length(spans)
       }}
    end
  end

  @doc """
  A work's table of contents, each entry resolvable to a URN.

  Lets a caller survey structure without pulling text — necessary because the canon has
  millions of segments and no context window holds a whole work.
  """
  @spec outline(String.t()) :: {:ok, map()} | {:error, :not_found}
  def outline(work_id) when is_binary(work_id) do
    query =
      from t in Text,
        where: t.work_id == ^work_id,
        preload: [:work],
        limit: 1

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      text ->
        entries =
          text.outline
          |> Map.get("entries", [])
          |> Enum.map(fn e ->
            %{
              type: e["type"],
              n: e["n"],
              level: e["level"],
              title: e["title"],
              juan: e["juan"],
              urn: entry_urn(text, e)
            }
          end)

        {:ok,
         %{
           work_id: work_id,
           title: text.work.title,
           urn_prefix: text.urn_prefix,
           juan_count: get_in(text.work.meta, ["juan_count"]),
           # An outline is often the FIRST thing a caller fetches about a work, so it is
           # the moment the reader decides what kind of text this is. Without these a
           # Japanese sectarian commentary and a Kumārajīva translation look identical
           # here — invariant #4 applies to structure as much as to a quoted passage.
           composition_origin: text.work.composition_origin,
           text_role: text.work.text_role,
           division: text.work.division,
           division_en: text.work.division_en,
           attributed_author: text.work.attributed_author,
           authority_id: text.work.authority_id,
           witness: text.witness_id,
           # The witness alone does not identify the collection: the Degé Kangyur and the
           # Degé Tengyur are both witness "D", and only the source separates them. It is
           # also what decides which publisher a reader link points at.
           source: text.source_id,
           provenance_label: Provenance.label(text.work.composition_origin, text.work.text_role),
           entries: entries
         }}
    end
  end

  defp entry_urn(_text, %{"anchor" => nil}), do: nil

  defp entry_urn(text, %{"anchor" => anchor} = entry) do
    juan = entry["juan"]
    work = if juan, do: "#{text.work_id}_#{pad(juan)}", else: text.work_id
    "#{text.urn_prefix |> String.replace_suffix(text.work_id, work)}@p#{anchor}"
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(3, "0")

  defp range_urn([]), do: nil
  defp range_urn([only]), do: only.urn

  defp range_urn(spans) do
    URN.range(List.first(spans).urn, List.last(spans).urn)
  end

  defp clamp(n, lo, hi) when is_integer(n), do: n |> max(lo) |> min(hi)
  defp clamp(_, lo, _hi), do: lo

  # A range covers every segment between its endpoints, in reading order.
  #
  # Which hyphen separates the endpoints is not always knowable from the string:
  # SuttaCentral's merged-section ids contain the same character, so
  # `mn12@53-55.1-53-55.9` divides four ways and only one of them is right. Every division
  # is tried and the corpus decides — the one whose halves are both real segments of one
  # text, in order, is the range that was meant. `parse/1`'s division is simply the first
  # candidate, so the ordinary case costs nothing extra.
  defp fetch_range(%URN{} = urn) do
    urn_string = URN.to_string(urn)

    Enum.find_value(URN.splits("#{urn.locator}-#{urn.locator_end}"), fn {from, to} ->
      with {:ok, first} <- fetch_segment(URN.to_string(%{urn | locator: from, locator_end: nil})),
           {:ok, last} <- fetch_segment(URN.to_string(%{urn | locator: to, locator_end: nil})),
           true <- first.text_id == last.text_id and first.ordinal <= last.ordinal do
        between(urn_string, first.text_id, first.ordinal, last.ordinal)
      else
        _ -> nil
      end
    end) || stored_range(urn_string)
  end

  # A range URN whose endpoints cannot be split back out of it is still a real address if
  # something stored it. SuttaCentral's merged-section ids contain a hyphen — `53-55.1` —
  # which is the character this grammar uses to join two locators, so a chunk spanning
  # them has an unambiguous *identity* and an ambiguous *arithmetic*. 412 chunks are in
  # that position and none of them resolved before this: the endpoints parsed into
  # locators no segment has, and the answer was `:not_found` with nothing to indicate the
  # citation was fine and the split was wrong.
  #
  # Chunks record the ordinals they span, so identity answers what arithmetic cannot.
  defp stored_range(urn_string) do
    case Repo.one(from c in Chunk, where: c.urn == ^urn_string) do
      nil -> {:error, :not_found}
      chunk -> between(urn_string, chunk.text_id, chunk.first_ordinal, chunk.last_ordinal)
    end
  end

  defp between(urn_string, text_id, first_ordinal, last_ordinal) do
    segments =
      Repo.all(
        from s in Segment,
          join: t in Text,
          on: t.id == s.text_id,
          where:
            s.text_id == ^text_id and
              s.ordinal >= ^first_ordinal and s.ordinal <= ^last_ordinal,
          order_by: s.ordinal,
          preload: [text: ^Text.preload_without_body()]
      )

    case segments do
      [] -> {:error, :not_found}
      list -> {:ok, merge_spans(urn_string, list)}
    end
  end

  # A range span's content is the concatenation of its members, and its offsets run
  # from the first member's start to the last member's end — so the range is still
  # byte-verifiable against texts.body exactly like a point span.
  defp merge_spans(range_urn, segments) do
    first = List.first(segments)
    last = List.last(segments)
    content = Enum.map_join(segments, "", & &1.content)

    %{
      urn: range_urn,
      content: content,
      char_start: first.char_start,
      char_end: last.char_end,
      byte_start: first.byte_start,
      byte_end: last.byte_end,
      sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
      kind: first.kind,
      juan: first.juan,
      meta: %{"range_of" => length(segments)},
      provenance: provenance(first)
    }
  end

  # The segments a citation is anchored at: one for a point URN, the two ends for a range.
  # `resolve/1` has accepted ranges since a range is a legitimate citation; this is the
  # sibling that was never swept (rule 41).
  defp focus_segments(urn_string) do
    case URN.parse(urn_string) do
      {:ok, %URN{locator_end: nil}} ->
        with {:ok, segment} <- fetch_segment(urn_string), do: {:ok, segment, segment}

      {:ok, %URN{} = urn} ->
        with {:ok, first} <- fetch_segment(endpoint(urn, urn.locator)),
             {:ok, last} <- fetch_segment(endpoint(urn, urn.locator_end)) do
          {:ok, first, last}
        end

      {:error, _} ->
        {:error, :bad_urn}
    end
  end

  defp endpoint(%URN{} = urn, locator) do
    URN.to_string(%{urn | locator: locator, locator_end: nil, raw: nil})
  end

  defp fetch_segment(urn_string) do
    case Repo.one(from s in Segment, where: s.urn == ^urn_string) do
      nil -> {:error, :not_found}
      segment -> {:ok, segment}
    end
  end

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
        preload: [text: ^Text.preload_without_body()]

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
      division: work.division,
      division_en: work.division_en,
      attributed_author: work.attributed_author,
      # THE BYLINE IS WHAT THE EDITION PRINTED; THIS IS WHO IT DENOTES. 姚秦 竺佛念譯 and a
      # differently-spelled byline elsewhere are the same hand, and only the id says so. It
      # is `nil` for the 40% that cannot be resolved confidently, which is a refusal rather
      # than a gap — see `Pramana.Authority`.
      authority_id: work.authority_id,
      authority_confidence: work.authority_confidence,
      attribution_confidence: work.attribution_confidence,
      witness: text.witness_id,
      # THE SIGIL IS NOT THE WITNESS, and one letter is not a provenance record.
      #
      # `witness: "T"` and `witness: "N"` differ by a character, and the texts behind them
      # differ by fifteen centuries and two intervening languages: T0099 雜阿含經 is
      # Guṇabhadra's c. 435 rendering of a Sarvāstivāda Sanskrit original, while N0006
      # 相應部經典 is a 1990s Chinese rendering of the Japanese rendering of the Pāli. Both
      # are `indic` in origin and `root` in role, both correctly, so before this the entire
      # difference between them was the letter.
      #
      # A model reading `witness: "N"` has no way to know that. This is the `#wit1` problem
      # `Pramana.Apparatus` exists to prevent, one level up from the apparatus: a sigil in
      # front of a reader who has not been told what it means. The `witnesses` table has
      # carried real names since 2026-08-27; the payload simply never asked for one.
      witness_name: witness_name(text),
      source: text.source_id,
      license_class: text.source && text.source.license_class,
      volume: volume(segment, text),
      juan: segment.juan,
      page: segment.page,
      register: segment.register,
      line: segment.line,
      addressing: addressing(text)
    }
  end

  # Loaded via the text's association when present. Falls back to the id rather than to
  # nil: a caller that reads `witness_name` must always get something nameable, and the id
  # is what the witnesses table itself stores when nothing better is known.
  defp witness_name(%{witness: %{name: name}}) when is_binary(name), do: name
  defp witness_name(%{witness_id: id}), do: id

  # THE VOLUME OF THE LINE, NOT OF THE WORK.
  #
  # `text.volume` describes the work, and for a work that spans volumes it is a range —
  # "130-133" for L1557, "31-32" for JB271. That is a correct description and a useless
  # coordinate: every printed reference is to one volume, and `Pramana.Reader.linehead/1`
  # built `130-133n1557_p0003a01` out of it, a citation nothing can resolve.
  #
  # `IR.concat/1` stamps each line with the volume it was printed in for exactly this
  # reason, so the answer is already recorded and only had to be asked for. Segments in a
  # single-volume work carry no stamp and fall back to the text's volume, which for them
  # is the same number.
  defp volume(%Segment{meta: %{"volume" => volume}}, _text) when is_integer(volume),
    do: Integer.to_string(volume)

  defp volume(_segment, text), do: text.volume

  # A source DECLARES how checkable its anchors are; only the fallback is inferred.
  # See `Pramana.Local.Manifest` for the three levels. Inferring this from the source id
  # collapsed `edition_page` (a page number printed in the book, which a reader can turn
  # to) into `derived` (no intrinsic anchor at all), understating what can be verified.
  defp addressing(%{meta: %{"addressing" => declared}}) when is_binary(declared), do: declared
  defp addressing(%{source_id: "local" <> _}), do: "derived"
  defp addressing(_), do: "canonical"

  @doc """
  Which collections of a source the bake actually holds.

  A menu built from a static list offers canons the corpus does not contain, and every
  one of those is a promise of an empty result set — the exact confusion
  `Pramana.Coverage` exists to prevent, arriving through a dropdown instead of a search.
  Read from the corpus so it shrinks and grows with the bake.
  """
  @spec witnesses_held(String.t()) :: [String.t()]
  def witnesses_held(source_id) when is_binary(source_id) do
    Repo.all(
      from t in Text,
        where: t.source_id == ^source_id,
        select: t.witness_id,
        distinct: true,
        order_by: t.witness_id
    )
  end

  @doc "Loads a text's full body, used for offset verification."
  @spec body(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def body(urn_prefix) when is_binary(urn_prefix) do
    case Repo.one(from t in Text, where: t.urn_prefix == ^urn_prefix, select: t.body) do
      nil -> {:error, :not_found}
      body -> {:ok, body}
    end
  end
end
