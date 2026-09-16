defmodule Pramana.Guard do
  @moduledoc """
  Deterministic citation verification.

  This is the keystone of the project. From `CLAUDE.md`:

  > **The model is not trusted to cite correctly. The citation guard re-resolves every
  > URN and byte-compares the quoted span.**

  The guard runs **after** generation and **outside** the model. It is pure arithmetic
  over the bake: extract every URN from the output, re-resolve each against the
  corpus, and byte-compare any quoted text. Nothing about it depends on which model
  produced the text, so it works identically for Claude today, a local model tomorrow,
  and something else in three years.

  ## What it catches

  - Fabricated URNs (a plausible-looking citation to a passage that does not exist)
  - Real URNs quoted with altered text (the subtlest and most damaging failure)
  - Machine-translated text presented as canonical source (`CLAUDE.md` invariant #7)

  ## What it deliberately does not do

  It does not judge whether a citation *supports* the claim it is attached to. That is
  a question of interpretation; this module answers only the mechanical question of
  whether the text is really there. Conflating the two would make the guard's
  guarantee fuzzy, and its value is that the guarantee is not fuzzy.
  """

  alias Pramana.Corpus
  alias Pramana.EvidenceInput
  alias Pramana.Punctuation
  alias Pramana.Retrieval.Lexical
  alias Pramana.Retrieval.Variants
  alias Pramana.Telemetry

  # Matches a URN wherever it appears: bare, bracketed, or in markdown.
  # Deliberately permissive in what it extracts and strict in what it accepts —
  # a malformed URN should be REPORTED as invalid, never silently skipped.
  #
  # ONE definition, reused by the quote-pairing regex below. A second, hand-written
  # URN pattern previously omitted the `:` separator, so pairing captured only
  # "pramana:cbeta.T" and never matched a real URN. The guard silently degraded to
  # existence-checking and reported :ok for altered quotations — the exact failure it
  # exists to prevent. Never write a second URN pattern.
  # The optional `#tr:<lang>/<translator>` tail must be part of THIS pattern, not a
  # second one. Without it a quoted rendering URN is captured truncated to its anchor,
  # the English quote is compared against Chinese source text, and the guard reports
  # `:quote_mismatch` — a true failure for a false reason, which is the kind of finding
  # that gets dismissed. Translator ids include `:`, `@` and `+`
  # (`model:claude-opus-5@prompt-v3+glossary-ddb2`).
  @urn_source "pramana:[a-zA-Z0-9_.\\-]+:[a-zA-Z0-9_.\\-]+(?:@[a-zA-Z0-9_.\\-+]+)?" <>
                "(?:#tr:[a-zA-Z0-9_.\\-]+/[a-zA-Z0-9_.\\-@+:]+)?"
  @urn_pattern Regex.compile!(@urn_source)
  @quoted_citation Regex.compile!(
                     "[\u300c\u300e\"\u201c]([^\u300d\u300f\"\u201d]{1,400})" <>
                       "[\u300d\u300f\"\u201d]\\s*[\\[\u3010(]?\\s*(" <> @urn_source <> ")",
                     "u"
                   )

  @wrapped_citation Regex.compile!(
                      "([\\[（(【])\\s*(" <> @urn_source <> ")\\s*([\\]）)】])",
                      "u"
                    )
  @opened_citation Regex.compile!("([\\[（(【])\\s*(" <> @urn_source <> ")", "u")
  @closed_citation Regex.compile!("(" <> @urn_source <> ")\\s*[\\]）)】]", "u")
  @wrappers %{"[" => "]", "(" => ")", "（" => "）", "【" => "】"}

  @type verdict ::
          :ok
          | :bad_urn
          | :not_found
          | :quote_mismatch
          | :not_citable_as_source

  @type finding :: %{
          urn: String.t(),
          verdict: verdict(),
          quoted: String.t() | nil,
          actual: String.t() | nil,
          provenance: map() | nil,
          # `"source"` or `"translation"`. A caller that requires scripture rather than
          # a rendering can reject on this without re-parsing the URN, and a verified
          # quote of a translation never reads as a verified quote of the text.
          layer: String.t(),
          # Byte offset in the inspected text where this URN occurrence was found.
          # Present only when the finding was produced by `check_output/1`.
          source_offset: non_neg_integer() | nil,
          occurrence: map() | nil
        }

  @doc """
  Verifies that `quoted_text` really appears at `urn`.

  Comparison is on exact bytes after trimming surrounding whitespace. It is
  deliberately not fuzzy: "close enough" is how a misquotation survives review.

  Returns `true` only when the URN resolves and the quote is contained in the span.
  """
  @spec verify(String.t(), String.t()) :: boolean()
  def verify(urn, quoted_text) when is_binary(urn) and is_binary(quoted_text) do
    String.trim(quoted_text) != "" and match?(%{verdict: :ok}, check(urn, quoted_text))
  end

  def verify(_, _), do: false

  @doc """
  Checks one citation, returning a structured finding rather than a boolean.

  Pass `nil` for `quoted_text` to check only that the URN resolves.
  """
  @spec check(String.t(), String.t() | nil) :: finding()
  def check(urn, quoted_text \\ nil) do
    Telemetry.span(
      [:pramana, :guard, :check],
      fn -> do_check(urn, quoted_text) end,
      # THE VERDICT IS THE POINT. A refusal is the highest-signal thing this system produces
      # and it was being computed and discarded — `docs/PLAN.md` § A6. Counting them by
      # verdict is what turns "the guard says no sometimes" into a map of where the corpus
      # is hard to cite.
      fn finding -> {%{}, %{verdict: finding.verdict, layer: finding.layer}} end
    )
  end

  defp do_check(urn, quoted_text) do
    case Corpus.resolve(urn) do
      {:error, reason} ->
        %{
          urn: urn,
          verdict: reason,
          quoted: quoted_text,
          actual: nil,
          provenance: nil,
          layer: "source",
          source_offset: nil,
          occurrence: nil
        }

      {:ok, span} ->
        check_span(span, quoted_text, urn)
    end
  end

  @doc """
  Checks an already-resolved span. Exposed so the invariant-#7 rule can be exercised
  directly, without needing a generated translation layer to exist in the corpus yet.
  """
  @spec check_span(map(), String.t() | nil, String.t() | nil) :: finding()
  def check_span(span, quoted_text \\ nil, urn \\ nil) do
    urn = urn || Map.get(span, :urn)

    case citable_as_source(span) do
      :ok -> compare(urn, span, quoted_text)
      verdict -> finding(urn, span, quoted_text, verdict)
    end
  end

  # Invariant #7: generated translations are a layer over a source anchor, never a
  # source in their own right.
  #
  # Wired before there was anything to check, so the guard would not have to be retrofitted
  # around content that already existed — which is exactly how an invariant like this gets
  # quietly skipped. This comment used to end "translation layers do not exist until
  # Phase 3, so today `:method` is always absent and this always returns :ok", and stayed
  # that way two phases after the corpus grew 241,409 renderings.
  #
  # The path is real now: `Corpus.resolve/1` sends a URN carrying `#tr:<lang>/<translator>`
  # to `Translations.resolve/1`, which returns a span whose provenance has `method`. So a
  # generated rendering quoted as scripture reaches this clause through the ORDINARY resolve
  # path, not one a caller has to remember to use. Absent `:method` still defaults to
  # "human", because a source span legitimately has none.
  defp citable_as_source(span) do
    case Map.get(span.provenance || %{}, :method, "human") do
      "human" -> :ok
      _generated -> :not_citable_as_source
    end
  end

  defp compare(urn, span, nil), do: finding(urn, span, nil, :ok)

  defp compare(urn, span, quoted) do
    verdict =
      if String.contains?(span.content, String.trim(quoted)),
        do: :ok,
        else: :quote_mismatch

    if String.trim(quoted) == "",
      do: finding(urn, span, nil, :ok),
      else: finding(urn, span, quoted, verdict)
  end

  defp finding(urn, span, quoted, verdict, source_offset \\ nil) do
    provenance = Map.get(span, :provenance)

    %{
      urn: urn,
      verdict: verdict,
      quoted: quoted,
      actual: span.content,
      provenance: provenance,
      layer: Map.get(provenance || %{}, :layer, "source"),
      source_offset: source_offset,
      occurrence: nil
    }
  end

  @doc """
  Says **how** a quotation failed, not only that it did.

  `:quote_mismatch` is a true verdict and a useless one: it covers a model that invented a
  passage, a scholar quoting the same line from an edition that punctuates differently, and
  a citation that names the line before the one it quotes. Those are three different
  defects in three different layers, and telling them apart is deterministic.

      :editorial_punctuation   the words match; the punctuation does not
      :orthographic_variant    the words match under this corpus's variant classes
      :spans_line_boundary     the quote runs past this line into the next
      :wrong_address           the text is real and this URN is not where it lives
      :not_found_in_search    a completed search found no replacement here
      :search_unavailable     the diagnostic search could not be completed

  ## The one that inverts the usual reading

  **`:wrong_address` is not a hallucination.** The model found real text and cited the wrong
  line for it, which indicts *addressing* — or retrieval, for handing back a span whose URN
  did not travel with it. A completed no-match search is limited to the material and
  search method used; it never proves fabrication. A search error is not a no-match result.

  ## And the one that is arguably not an error at all

  **A Taishō line breaks wherever the block-cutter reached**, mid-sentence and mid-compound,
  so a passage worth quoting routinely spans two of them. `:spans_line_boundary` says the
  quotation is real and continuous in the printed page and the citation named only its first
  line. That is a citation worth tightening, not a false claim, and reporting it as
  `:quote_mismatch` alongside a fabrication trains people to ignore the guard.

  Checked cheapest first, and the corpus is only consulted once the free string comparisons
  have failed. The optional `:search` function supplies the diagnostic search boundary;
  by default it is the ordinary lexical phrase search.
  """
  @spec diagnose(map(), keyword()) :: map()
  def diagnose(finding, opts \\ [])

  def diagnose(%{verdict: :quote_mismatch, quoted: quoted, actual: actual} = finding, opts)
      when is_binary(quoted) and is_binary(actual) do
    search = Keyword.get(opts, :search, &Lexical.search/2)
    Map.merge(finding, classify(String.trim(quoted), actual, finding, search))
  rescue
    # The mismatch at the cited address is still known. A failed diagnostic query
    # establishes nothing about whether a replacement exists elsewhere.
    _error -> Map.merge(finding, search_unavailable())
  end

  def diagnose(finding, _opts), do: Map.put(finding, :reason, nil)

  defp classify(quoted, actual, finding, search) do
    cond do
      Punctuation.strip(quoted) == "" ->
        %{
          reason: :empty_quote,
          explanation: "No substantive quotation remains after removing editorial punctuation."
        }

      Punctuation.same_but_for_punctuation?(quoted, actual) or
          String.contains?(Punctuation.strip(actual), Punctuation.strip(quoted)) ->
        %{
          reason: :editorial_punctuation,
          explanation:
            "The characters are the same; the punctuation is not. CBETA's punctuation is a " <>
              "modern editorial addition and is not in the witness, so an edition that " <>
              "punctuates differently is not a different text."
        }

      variant_match?(quoted, actual) ->
        %{
          reason: :orthographic_variant,
          explanation:
            "The passage matches once this corpus's orthographic variants are applied. The " <>
              "quotation uses a different but equivalent glyph."
        }

      spans_boundary?(quoted, finding) ->
        %{
          reason: :spans_line_boundary,
          explanation:
            "The quotation is continuous across this line and its neighbours. A Taishō " <>
              "line breaks wherever the block-cutter reached, mid-sentence and " <>
              "mid-compound, so this is a citation to tighten — cite the range — rather " <>
              "than a false claim."
        }

      true ->
        elsewhere(quoted, search)
    end
  end

  # Only the CHEAP direction: expand the quotation's variant classes and see whether any
  # spelling of it is present. Expanding the whole line would be the same answer at many
  # times the cost.
  defp variant_match?(quoted, actual) do
    stripped_actual = Punctuation.strip(actual)

    quoted
    |> Punctuation.strip()
    |> Variants.expand(max_forms: 16)
    |> elem(0)
    |> Enum.any?(&String.contains?(stripped_actual, &1))
  end

  # ANCHORED AT THE CITED LINE, and that is the whole difficulty.
  #
  # The first version asked whether the quotation appeared anywhere in the surrounding
  # window, which is true of a quotation lying wholly in the NEXT line — and that is
  # `:wrong_address`, a different and more useful answer. So the two windows tested here
  # both include the focus: the quotation either starts on this line and runs forward, or
  # starts earlier and runs into it. A quotation that sits entirely in a neighbour matches
  # neither and falls through to the search, which returns the URN it actually lives at.
  #
  # A small window, too: a quotation that only matches once fifty lines are concatenated is
  # not spanning a boundary, it is a paraphrase of a passage.
  defp spans_boundary?(quoted, %{urn: urn}) when is_binary(urn) do
    case Corpus.context(urn, before: 1, after: 2) do
      {:ok, %{focus: focus, before: before_spans, after: after_spans}} ->
        needle = Punctuation.strip(quoted)

        anchored =
          Enum.any?(
            [concat(before_spans ++ [focus]), concat([focus | after_spans])],
            &String.contains?(&1, needle)
          )

        # AND in no single line. Containment in `focus <> next` is also true of a quotation
        # lying wholly inside `next` — which is `:wrong_address`, and the more useful
        # answer, because it names the URN the words actually live at. Spanning means
        # crossing: present across the join and absent from either side alone.
        anchored and not Enum.any?([focus | before_spans ++ after_spans], &in_span?(&1, needle))

      _ ->
        false
    end
  end

  defp spans_boundary?(_quoted, _finding), do: false

  defp concat(spans), do: spans |> Enum.map_join("", & &1.content) |> Punctuation.strip()

  defp in_span?(span, needle), do: span.content |> Punctuation.strip() |> String.contains?(needle)

  # Search results are diagnostic candidates, not proof of fabrication or of an
  # exhaustive corpus. Keep completed no-match searches separate from failed ones.
  defp elsewhere(quoted, search) do
    stripped = Punctuation.strip(quoted)

    case search.(stripped, mode: :phrase, limit: 3) do
      {:ok, %{results: [%{span: span} | _] = results}} ->
        %{
          reason: :wrong_address,
          search_status: :matched,
          found_at: Enum.map(results, & &1.span.urn) |> Enum.uniq(),
          explanation:
            "The search found candidate text at #{span.urn}; it does not match the cited " <>
              "address. The text is real, but a replacement must be checked against the " <>
              "exact quotation before changing the citation."
        }

      {:ok, %{results: []}} ->
        %{
          reason: :not_found_in_search,
          search_status: :no_match,
          explanation:
            "The quotation does not match this cited passage. A completed phrase search " <>
              "found no replacement in the loaded corpus. This does not establish that " <>
              "the passage was fabricated or that it is absent from other editions or sources."
        }

      _ ->
        search_unavailable()
    end
  end

  defp search_unavailable do
    %{
      reason: :search_unavailable,
      search_status: :unavailable,
      explanation:
        "The quotation does not match this cited passage, but the diagnostic search " <>
          "could not be completed. No conclusion about a replacement or absence was established."
    }
  end

  @doc """
  Extracts every URN mentioned in a block of generated text.

  Order-preserving and de-duplicated.
  """
  @spec extract_urns(String.t()) :: [String.t()]
  def extract_urns(text) when is_binary(text) do
    @urn_pattern
    |> Regex.scan(text)
    |> Enum.map(&trim_sentence_punctuation(hd(&1)))
    |> Enum.uniq()
  end

  # A URN AT THE END OF A SENTENCE KEEPS THE FULL STOP, and then resolves to nothing.
  #
  # `.` is legal *inside* a locator — `sc.ms:mn1@1.1` — so the pattern has to admit it,
  # and it therefore swallows the period of "…as stated at pramana:cbeta.T:T0262_001@
  # p0001c17." The guard reported `:not_found` for a perfectly good citation, which is a
  # false accusation rather than a missed one, and prose is where citations mostly live.
  #
  # Found 2026-09-02 while building `Pramana.Repair`, and invisible to `evals/` because
  # its gold citations are constructed rather than written in sentences. No locator
  # grammar here ends in punctuation, so trimming it is safe in a way that loosening the
  # pattern would not be.
  defp trim_sentence_punctuation(urn) do
    String.replace(urn, ~r/[.,;:!?)\]】」』]+$/u, "")
  end

  @doc """
  Verifies every citation in a block of generated text.

  Returns `%{findings: [...], ok?: boolean, checked: n, failed: n}`. `ok?` is true
  only when every citation resolved cleanly.

  Quoted text is associated with a URN when it appears in the conventional forms —
  `「…」【urn】`, `"…" (urn)` — since those are what a model producing Buddhist-studies
  prose actually emits. Anything unrecognised is checked for existence only, and the
  finding says so, rather than being reported as verified.
  """
  @spec check_output(String.t(), keyword()) :: %{
          findings: [finding()],
          ok?: boolean(),
          checked: non_neg_integer(),
          failed: non_neg_integer(),
          verified_quotes: non_neg_integer(),
          existence_only: non_neg_integer(),
          translations: non_neg_integer()
        }
  def check_output(text, opts \\ []) when is_binary(text) do
    findings =
      text
      |> occurrences(opts)
      |> Enum.map(fn occurrence ->
        check(occurrence.urn, occurrence.quoted)
        |> Map.merge(%{source_offset: occurrence.urn_range.byte_start, occurrence: occurrence})
      end)

    failed = Enum.count(findings, &(&1.verdict != :ok))

    # A citation with no recognisable quotation was only checked for EXISTENCE. That
    # is a materially weaker guarantee than a byte-compared quote, so it is reported
    # rather than folded into `ok?` — otherwise existence-only output reads as fully
    # verified.
    verified_quotes = Enum.count(findings, &(&1.verdict == :ok and &1.quoted != nil))

    %{
      findings: findings,
      ok?: failed == 0,
      checked: length(findings),
      failed: failed,
      verified_quotes: verified_quotes,
      existence_only: length(findings) - failed - verified_quotes,
      # Verified quotes that were of a TRANSLATION, not of the text. Counted separately
      # because "3 citations verified" over three renderings of one Pāli line is a very
      # different claim from three verified quotes of scripture, and a summary that does
      # not distinguish them overstates what was checked.
      translations: Enum.count(findings, &(&1.layer == "translation"))
    }
  end

  @doc """
  Recognized citation occurrences with half-open UTF-8 byte ranges in the ORIGINAL input.

  One parser owns both checking and editing. Repeated URNs remain distinct. A quote
  range excludes its quotation marks; a citation range includes only a matching
  citation wrapper, never surrounding prose or document-wide whitespace.
  """
  @spec occurrences(String.t(), keyword()) :: [map()]
  def occurrences(text, opts \\ []) when is_binary(text) do
    text
    |> EvidenceInput.regions(opts)
    |> Enum.flat_map(fn {offset, region} ->
      region |> region_occurrences() |> Enum.map(&shift_occurrence(&1, offset))
    end)
  end

  # Bounded regex passes per region. No whole-prefix or whole-suffix scan per citation.
  defp region_occurrences(text) do
    quoted =
      @quoted_citation
      |> Regex.scan(text, return: :index)
      |> Map.new(fn [_, quote_range, {pos, _}] -> {pos, quote_range} end)

    wrappers = wrapper_ranges(text)

    openings =
      @opened_citation
      |> Regex.scan(text, return: :index)
      |> MapSet.new(fn [_, _, {pos, _}] -> pos end)

    closings =
      @closed_citation
      |> Regex.scan(text, return: :index)
      |> MapSet.new(fn [_, {pos, _}] -> pos end)

    @urn_pattern
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{pos, _} = urn_range] ->
      occurrence(text, urn_range, Map.get(quoted, pos), Map.get(wrappers, pos), openings, closings)
    end)
  end

  defp wrapper_ranges(text) do
    @wrapped_citation
    |> Regex.scan(text, return: :index)
    |> Enum.reduce(%{}, fn [whole, opening, {pos, len}, closing], acc ->
      open = binary_part(text, elem(opening, 0), elem(opening, 1))
      close = binary_part(text, elem(closing, 0), elem(closing, 1))
      raw = binary_part(text, pos, len)

      if @wrappers[open] == close and trim_sentence_punctuation(raw) == raw,
        do: Map.put(acc, pos, byte_range(whole)),
        else: acc
    end)
  end

  defp occurrence(text, {pos, length}, quote_range, wrapper, openings, closings) do
    urn = text |> binary_part(pos, length) |> trim_sentence_punctuation()
    urn_range = %{byte_start: pos, byte_end: pos + byte_size(urn)}

    %{
      urn: urn,
      quoted: if(quote_range, do: binary_part(text, elem(quote_range, 0), elem(quote_range, 1))),
      urn_range: urn_range,
      quote_range: byte_range(quote_range),
      citation_range: wrapper || urn_range,
      unpaired_wrapper?:
        is_nil(wrapper) and
          (MapSet.member?(openings, pos) or MapSet.member?(closings, pos))
    }
  end

  defp byte_range(nil), do: nil
  defp byte_range({pos, length}), do: %{byte_start: pos, byte_end: pos + length}

  defp shift_occurrence(occurrence, offset) do
    occurrence
    |> Map.update!(:urn_range, &shift_range(&1, offset))
    |> Map.update!(:quote_range, &shift_range(&1, offset))
    |> Map.update!(:citation_range, &shift_range(&1, offset))
  end

  defp shift_range(nil, _offset), do: nil

  defp shift_range(range, offset),
    do: %{byte_start: range.byte_start + offset, byte_end: range.byte_end + offset}
end
