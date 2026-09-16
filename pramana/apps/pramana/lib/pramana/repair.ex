defmodule Pramana.Repair do
  @moduledoc """
  Occurrence-specific citation repairs, never a document-wide replacement.

  The guard supplies exact byte ranges in the original input. A supported correction
  changes only that occurrence. Uncertain searches, multiple candidate addresses,
  overlapping edits and non-exact replacements are flagged and left untouched.
  `no_sources` removes an unsupported citation, not its prose; it describes support
  at that address, not the truth or origin of the quotation.

  The original document and an explicit edit plan are returned beside the amended
  text. Edits are validated against the original bytes and applied right-to-left.
  Neither source corpus data nor the caller's saved document is mutated.
  """

  alias Pramana.Guard
  alias Pramana.Report

  @type action :: %{
          urn: String.t(),
          source_offset: non_neg_integer(),
          state:
            :verified
            | :existence_only
            | :quote_relaxed
            | :citation_corrected
            | :no_sources
            | :flagged,
          reason: atom() | nil,
          detail: String.t() | nil,
          replaced_urn: String.t() | nil
        }

  @doc "Repairs recognized citation occurrences; returns original, text, actions, edits and counts."
  @spec repair(String.t(), keyword()) :: map()
  def repair(markdown, opts \\ []) when is_binary(markdown) do
    planned =
      markdown
      |> Report.mask_replays()
      |> Guard.check_output()
      |> Map.fetch!(:findings)
      |> Enum.map(&Guard.diagnose(&1, opts))
      |> Enum.map(fn finding ->
        action = plan(finding)
        {action, edit_for(finding, action, markdown)}
      end)
      |> reject_overlaps()

    actions = Enum.map(planned, &elem(&1, 0))
    edits = planned |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)
    text = apply_edits(markdown, edits)

    %{
      original: markdown,
      text: text,
      actions: actions,
      edits: edits,
      counts: Enum.frequencies_by(actions, & &1.state),
      repaired?: text != markdown
    }
  end

  defp plan(%{verdict: :ok, quoted: nil} = finding),
    do: action(finding, :existence_only, nil, "Only the existence of this address was checked.")

  defp plan(%{verdict: :ok} = finding), do: action(finding, :verified, nil, nil)

  defp plan(%{verdict: :quote_mismatch, reason: reason} = finding)
       when reason in [:editorial_punctuation, :orthographic_variant] do
    action(finding, :quote_relaxed, reason, "This quotation now reads as the edition prints it.")
  end

  defp plan(%{verdict: :quote_mismatch, reason: :wrong_address, found_at: [urn]} = finding) do
    # Phrase search can normalize punctuation. Its candidate is not itself proof of
    # an exact quotation, so the ordinary guard must approve the proposed new pair.
    if Guard.verify(urn, finding.quoted) do
      finding
      |> action(:citation_corrected, :wrong_address, "Replaced this occurrence with #{urn}.")
      |> Map.put(:replaced_urn, urn)
    else
      action(
        finding,
        :flagged,
        :replacement_not_exact,
        "The candidate does not verify the exact quotation."
      )
    end
  rescue
    _error ->
      action(
        finding,
        :flagged,
        :verification_unavailable,
        "The candidate could not be verified; this occurrence is unchanged."
      )
  end

  defp plan(%{verdict: :quote_mismatch, reason: :wrong_address} = finding) do
    action(
      finding,
      :flagged,
      :ambiguous,
      "Several addresses match; choosing one requires review."
    )
  end

  defp plan(%{verdict: :quote_mismatch, reason: :not_found_in_search} = finding) do
    action(
      finding,
      :no_sources,
      :not_found_in_search,
      "The quotation does not match this address and the completed search found no replacement here. " <>
        "Removing this citation does not establish fabrication."
    )
  end

  defp plan(%{verdict: :quote_mismatch, reason: :search_unavailable} = finding) do
    action(
      finding,
      :flagged,
      :search_unavailable,
      "Diagnostic search was unavailable; the document is unchanged."
    )
  end

  defp plan(%{verdict: :quote_mismatch, reason: :spans_line_boundary} = finding) do
    action(
      finding,
      :flagged,
      :spans_line_boundary,
      "The quotation crosses a line boundary. Choose the intended range."
    )
  end

  defp plan(%{verdict: :not_citable_as_source} = finding) do
    action(
      finding,
      :flagged,
      :not_citable_as_source,
      "This cites a generated translation as source text."
    )
  end

  defp plan(%{verdict: verdict} = finding) when verdict in [:not_found, :bad_urn] do
    action(finding, :no_sources, verdict, "This URN does not resolve in the current bake.")
  end

  defp plan(finding), do: action(finding, :flagged, Map.get(finding, :reason), nil)

  defp action(finding, state, reason, detail) do
    %{
      urn: finding.urn,
      source_offset: finding.source_offset,
      state: state,
      reason: reason,
      detail: detail,
      replaced_urn: nil
    }
  end

  defp edit_for(finding, action, original) do
    change =
      case action.state do
        :quote_relaxed -> {finding.occurrence.quote_range, finding.actual}
        :citation_corrected -> {finding.occurrence.urn_range, action.replaced_urn}
        :no_sources -> {finding.occurrence.citation_range, ""}
        _ -> nil
      end

    case change do
      {%{byte_start: first, byte_end: last} = range, replacement} when is_binary(replacement) ->
        %{
          range: range,
          before: binary_part(original, first, last - first),
          after: replacement,
          source_offset: action.source_offset,
          state: action.state
        }

      _ ->
        nil
    end
  end

  # Nested citation text can create overlapping edits. Neither edit wins by order;
  # both remain visible as unresolved review items instead of corrupting the input.
  defp reject_overlaps(planned) do
    Enum.map(planned, fn {action, edit} = item ->
      collision? =
        edit &&
          Enum.any?(planned, fn {other, candidate} ->
            candidate && other.source_offset != action.source_offset &&
              edit.range.byte_start < candidate.range.byte_end &&
              candidate.range.byte_start < edit.range.byte_end
          end)

      if collision? do
        {%{
           action
           | state: :flagged,
             reason: :overlapping_edits,
             detail: "This edit overlaps another citation; review it manually."
         }, nil}
      else
        item
      end
    end)
  end

  defp apply_edits(original, edits) do
    edits
    |> Enum.sort_by(& &1.range.byte_start, :desc)
    |> Enum.reduce(original, fn edit, text ->
      %{byte_start: first, byte_end: last} = edit.range
      # Ranges originate in the guard's scan of this exact string, not a new parse.
      expected = binary_part(text, first, last - first)
      if expected != edit.before, do: raise(ArgumentError, "citation edit bytes changed")
      binary_part(text, 0, first) <> edit.after <> binary_part(text, last, byte_size(text) - last)
    end)
  end
end
