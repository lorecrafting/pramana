defmodule Pramana.Repair do
  @moduledoc """
  Fixing a document's citations, where fixing them cannot mean inventing them.

  `Pramana.Guard` diagnoses a citation five ways and **repairs none of them**. Diagnosis
  serves a caller who checks; repair serves the one who does not, and that is most of
  them. `docs/PLAN.md` L3.

  ## The states, and the one that is not fojin's

  fojin ships a four-word vocabulary and `docs/PLAN.md` says to adopt it wholesale. Four of
  these are theirs:

    * `verified` — the quotation byte-matches the line it cites. Untouched.
    * `quote_relaxed` — the words are the corpus's words and the *presentation* differed:
      punctuation an editor added, or a variant Han form. **The quotation is replaced with
      what the corpus prints**, which makes it verbatim rather than making it plausible.
    * `citation_corrected` — the words are real and the address was wrong. The URN is
      replaced with the one they actually live at, and **only when that is unique**.
    * `no_sources` — nothing in the corpus supports it. The citation is stripped and the
      prose left standing, because the sentence may still be worth saying and the citation
      was the lie.

  The fifth is ours, and it is a deviation recorded rather than hidden:

    * `flagged` — repair would require a judgement. A quotation running across a printed
      line boundary needs a range citation somebody has to choose; a translation quoted as
      source is invariant #8 and is a question about what the author meant, not a typo.
      **Left exactly as written, and named.**

  Forcing those two into `no_sources` would delete a citation that is very nearly right,
  and into `verified` would pass one that is not. A vocabulary that cannot say what
  happened is a vocabulary that has to lie about one of them.

  ## Repair never invents, and the guard is why it does not have to

  Every correction here is a **substitution of something the corpus already said**:

    * `quote_relaxed` copies the line's own text over the paraphrase of it.
    * `citation_corrected` uses `found_at`, which `Guard.diagnose/1` produced by searching
      for the quoted words — so the replacement URN is a place those words were found, not
      a place they might be.

  Nothing here searches, guesses or generates. Where the guard could not establish a fact,
  this refuses to repair rather than composing one — which is the same rule the citation
  guard applies one level up, and the reason repair is safe to offer at all.

  ## What it does bluntly, and knows it

  Removing a citation is a string replacement over the whole document, so a URN cited twice
  — once supported and once not — loses both occurrences. The document stays honest because
  `actions` names every URN touched and the caller sees the diff rather than a silently
  rewritten file. Doing it properly needs character offsets the guard does not return, and
  inventing them here would be a second place that parses citations. Left blunt and stated.

  ## Ambiguity refuses

  A quotation found at three URNs gets `no_sources`, not the first of the three. A common
  formula appears across hundreds of works; picking one would produce a document whose
  citations are all resolvable and some of which are wrong, which is strictly worse than
  the document that came in.
  """

  alias Pramana.Guard

  @typedoc "What was done to one citation, and why."
  @type action :: %{
          urn: String.t(),
          state: :verified | :quote_relaxed | :citation_corrected | :no_sources | :flagged,
          reason: atom() | nil,
          detail: String.t() | nil,
          replaced_urn: String.t() | nil
        }

  @doc """
  Repairs every citation in a document.

  Returns `%{text:, actions:, counts:, repaired?:}`. `text` is the document with the safe
  substitutions applied; everything else is a record of what was done, so a caller can
  show the diff rather than a rewritten document nobody can audit.
  """
  @spec repair(String.t()) :: map()
  def repair(markdown) when is_binary(markdown) do
    findings =
      markdown
      |> Guard.check_output()
      |> Map.fetch!(:findings)
      |> Enum.map(&Guard.diagnose/1)

    actions = Enum.map(findings, &plan/1)
    text = Enum.reduce(Enum.zip(findings, actions), markdown, &apply_action/2)

    %{
      text: text,
      actions: actions,
      counts: Enum.frequencies_by(actions, & &1.state),
      # A document nothing was done to is not the same as one that needed nothing done,
      # and the caller is told which.
      repaired?: Enum.any?(actions, &(&1.state in [:quote_relaxed, :citation_corrected]))
    }
  end

  defp plan(%{verdict: :ok} = finding) do
    action(finding, :verified, nil, nil)
  end

  # The words are the corpus's; the presentation was not. Replacing the quotation with the
  # line's own text is a repair that cannot go wrong, because the replacement is the thing
  # being cited.
  defp plan(%{verdict: :quote_mismatch, reason: reason} = finding)
       when reason in [:editorial_punctuation, :orthographic_variant] do
    action(
      finding,
      :quote_relaxed,
      reason,
      "The quotation now reads as the edition prints it."
    )
  end

  # The text is real and the address was not. `found_at` is where the guard's own search
  # located the words — one place only, or this refuses.
  defp plan(%{verdict: :quote_mismatch, reason: :wrong_address, found_at: [urn]} = finding) do
    finding
    |> action(
      :citation_corrected,
      :wrong_address,
      "Cited #{finding.urn}; the words are at #{urn}."
    )
    |> Map.put(:replaced_urn, urn)
  end

  defp plan(%{verdict: :quote_mismatch, reason: :wrong_address, found_at: urns} = finding)
       when length(urns) > 1 do
    action(
      finding,
      :no_sources,
      :ambiguous,
      "These words are in #{length(urns)} places and the citation names none of them. " <>
        "Choosing one would make every citation resolvable and some of them wrong."
    )
  end

  defp plan(%{verdict: :quote_mismatch, reason: :absent_from_corpus} = finding) do
    action(finding, :no_sources, :absent_from_corpus, "These words appear nowhere in this bake.")
  end

  # A quotation genuinely continuous across a printed line. The citation is not wrong, it
  # is narrower than the quotation, and the range that fixes it is a choice about how much
  # to cite — which is the author's.
  defp plan(%{verdict: :quote_mismatch, reason: :spans_line_boundary} = finding) do
    action(
      finding,
      :flagged,
      :spans_line_boundary,
      "The quotation runs past the end of this line. Cite the range instead — which range " <>
        "is a decision about how much to quote."
    )
  end

  # Invariant #8. A generated rendering presented as scripture is not a typo, and quietly
  # deleting the citation would hide the thing most worth seeing.
  defp plan(%{verdict: :not_citable_as_source} = finding) do
    action(
      finding,
      :flagged,
      :not_citable_as_source,
      "This cites a translation as though it were the source text."
    )
  end

  defp plan(%{verdict: verdict} = finding) when verdict in [:not_found, :bad_urn] do
    action(finding, :no_sources, verdict, "This URN resolves to nothing in this bake.")
  end

  defp plan(finding), do: action(finding, :flagged, Map.get(finding, :reason), nil)

  defp action(finding, state, reason, detail) do
    %{
      urn: finding.urn,
      state: state,
      reason: reason,
      detail: detail,
      replaced_urn: nil
    }
  end

  defp apply_action({finding, %{state: :quote_relaxed}}, text) do
    case {finding.quoted, finding.actual} do
      {quoted, actual} when is_binary(quoted) and is_binary(actual) ->
        String.replace(text, quoted, actual)

      _ ->
        text
    end
  end

  defp apply_action({_finding, %{state: :citation_corrected, replaced_urn: to} = a}, text)
       when is_binary(to) do
    String.replace(text, a.urn, to)
  end

  # A citation with no support is REMOVED and the sentence kept. The alternative — leaving
  # it — is a document that still asserts a source for something the corpus does not say.
  defp apply_action({_finding, %{state: :no_sources} = a}, text) do
    text
    |> String.replace(~r/\s*[\[\(（【]\s*#{Regex.escape(a.urn)}\s*[\]\)）】]/u, "")
    |> String.replace(a.urn, "")
    |> String.replace(~r/[ \t]{2,}/u, " ")
  end

  defp apply_action({_finding, _action}, text), do: text
end
