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
  @urn_source "pramana:[a-zA-Z0-9_.\\-]+:[a-zA-Z0-9_.\\-]+(?:@[a-zA-Z0-9_.\\-]+)?" <>
                "(?:#tr:[a-zA-Z0-9_.\\-]+/[a-zA-Z0-9_.\\-@+:]+)?"
  @urn_pattern Regex.compile!(@urn_source)
  @quoted_citation Regex.compile!(
                     "[\u300c\u300e\"\u201c]([^\u300d\u300f\"\u201d]{1,400})" <>
                       "[\u300d\u300f\"\u201d]\\s*[\\[\u3010(]?\\s*(" <> @urn_source <> ")",
                     "u"
                   )

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
          layer: String.t()
        }

  @doc """
  Verifies that `quoted_text` really appears at `urn`.

  Comparison is on exact bytes after trimming surrounding whitespace. It is
  deliberately not fuzzy: "close enough" is how a misquotation survives review.

  Returns `true` only when the URN resolves and the quote is contained in the span.
  """
  @spec verify(String.t(), String.t()) :: boolean()
  def verify(urn, quoted_text) when is_binary(urn) and is_binary(quoted_text) do
    case check(urn, quoted_text) do
      %{verdict: :ok} -> true
      _ -> false
    end
  end

  def verify(_, _), do: false

  @doc """
  Checks one citation, returning a structured finding rather than a boolean.

  Pass `nil` for `quoted_text` to check only that the URN resolves.
  """
  @spec check(String.t(), String.t() | nil) :: finding()
  def check(urn, quoted_text \\ nil) do
    case Corpus.resolve(urn) do
      {:error, reason} ->
        %{
          urn: urn,
          verdict: reason,
          quoted: quoted_text,
          actual: nil,
          provenance: nil,
          layer: "source"
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
  # Translation layers do not exist until Phase 3, so today `:method` is always absent
  # and this always returns :ok. It is wired now, and tested with a synthetic span,
  # so the guard is not retrofitted later around content that already exists — which
  # is exactly how an invariant like this gets quietly skipped.
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

    finding(urn, span, quoted, verdict)
  end

  defp finding(urn, span, quoted, verdict) do
    provenance = Map.get(span, :provenance)

    %{
      urn: urn,
      verdict: verdict,
      quoted: quoted,
      actual: span.content,
      provenance: provenance,
      layer: Map.get(provenance || %{}, :layer, "source")
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
    |> Enum.map(&hd/1)
    |> Enum.uniq()
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
  @spec check_output(String.t()) :: %{
          findings: [finding()],
          ok?: boolean(),
          checked: non_neg_integer(),
          failed: non_neg_integer(),
          verified_quotes: non_neg_integer(),
          existence_only: non_neg_integer(),
          translations: non_neg_integer()
        }
  def check_output(text) when is_binary(text) do
    findings =
      text
      |> citation_pairs()
      |> Enum.map(fn {urn, quoted} -> check(urn, quoted) end)

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

  # Pairs a URN with the quotation immediately preceding it, when one is present in a
  # recognised form. Returns {urn, quoted_or_nil}.
  defp citation_pairs(text) do
    quoted_by_urn =
      @quoted_citation
      |> Regex.scan(text)
      |> Map.new(fn [_, quote, urn] -> {urn, quote} end)

    text
    |> extract_urns()
    |> Enum.map(fn urn -> {urn, Map.get(quoted_by_urn, urn)} end)
  end
end
