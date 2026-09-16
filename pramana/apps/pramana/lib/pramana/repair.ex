defmodule Pramana.Repair do
  @moduledoc """
  Occurrence-specific citation repairs, never a document-wide replacement.

  The guard supplies exact byte ranges in the original input. A supported correction
  changes only that occurrence. Uncertain searches, multiple candidate addresses,
  overlapping edits and non-exact replacements are flagged and left untouched.
  `no_sources` removes an unsupported citation, not its prose; it describes support
  at that address, not the truth or origin of the quotation.

  The original document and an explicit edit plan are returned beside the amended
  text. Edits are validated against the original bytes and assembled from the original bytes.
  Neither source corpus data nor the caller's saved document is mutated.
  """

  alias Pramana.EvidenceInput
  alias Pramana.Guard
  alias Pramana.Repair.Intervals
  alias Pramana.Repair.Quote
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
    case EvidenceInput.check(markdown) do
      :ok ->
        repair_bounded(markdown, opts)

      {:error, refusal} ->
        %{
          original: markdown,
          text: markdown,
          actions: [],
          edits: [],
          counts: %{},
          repaired?: false,
          refusal: refusal
        }
    end
  end

  defp repair_bounded(markdown, opts) do
    planned =
      markdown
      |> Guard.check_output(regions: Report.prose_regions(markdown))
      |> Map.fetch!(:findings)
      |> Enum.map(&Guard.diagnose(&1, opts))
      |> Enum.map(fn finding ->
        action = plan(finding)
        {action, edit_for(finding, action, markdown), finding.occurrence}
      end)
      |> reject_overlaps()
      |> reject_rebindings(markdown)

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

  defp plan(%{occurrence: %{unpaired_wrapper?: true}, verdict: verdict} = finding)
       when verdict != :ok do
    action(
      finding,
      :flagged,
      :unpaired_wrapper,
      "The citation wrapper is incomplete within its prose region."
    )
  end

  defp plan(%{verdict: :ok, quoted: nil} = finding),
    do: action(finding, :existence_only, nil, "Only the existence of this address was checked.")

  defp plan(%{verdict: :ok} = finding), do: action(finding, :verified, nil, nil)

  defp plan(%{verdict: :quote_mismatch, reason: reason} = finding)
       when reason in [:editorial_punctuation, :orthographic_variant] do
    case Quote.align(finding.actual, finding.quoted, reason) do
      {:ok, replacement} ->
        finding
        |> action(
          :quote_relaxed,
          reason,
          "Aligned this quotation to the edition's exact subspan."
        )
        |> Map.put(:replacement_quote, replacement)

      {:error, refusal} ->
        action(
          finding,
          :flagged,
          refusal,
          "No unique substantive source subspan was established."
        )
    end
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
        :quote_relaxed -> {finding.occurrence.quote_range, action.replacement_quote}
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

  defp reject_overlaps(planned) do
    writes =
      for {action, edit, _} <- planned,
          edit != nil,
          do: interval(edit.range, action.source_offset)

    scopes =
      for {action, _, occurrence} <- planned,
          range <- [occurrence.quote_range, occurrence.citation_range],
          range != nil,
          do: interval(range, action.source_offset)

    conflicts = Intervals.conflicts(writes, scopes)

    Enum.map(planned, fn {action, edit, occurrence} ->
      if Map.has_key?(conflicts, action.source_offset) do
        {%{
           action
           | state: :flagged,
             reason: :overlapping_edits,
             detail:
               "An edit would change another citation or its quotation; review both manually."
         }, nil, occurrence}
      else
        {action, edit, occurrence}
      end
    end)
  end

  # Deleting one citation can make a quotation that belonged to it become syntactically
  # adjacent to the next surviving citation. The edit ranges do not overlap, but the
  # amended document would then assert a different quotation/citation pair than the one
  # that was diagnosed. Reparse the proposed output once and map surviving URN starts
  # through the original edit deltas; refuse only the deletion that owned the newly
  # attached quotation.
  defp reject_rebindings(planned, original) do
    edits = planned |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)

    if edits == [] do
      planned
    else
      actual_by_offset =
        original
        |> apply_edits(edits)
        |> Guard.occurrences(regions: Report.prose_regions(apply_edits(original, edits)))
        |> Map.new(&{&1.urn_range.byte_start, &1})

      culprits =
        Enum.reduce(planned, MapSet.new(), fn entry, acc ->
          case rebinding_culprit(entry, planned, edits, actual_by_offset) do
            nil -> acc
            source_offset -> MapSet.put(acc, source_offset)
          end
        end)

      Enum.map(planned, &reject_rebinding(&1, culprits))
    end
  end

  defp rebinding_culprit({%{state: :no_sources}, edit, _occurrence}, _planned, _edits, _actual)
       when not is_nil(edit),
       do: nil

  defp rebinding_culprit({action, _edit, occurrence}, planned, edits, actual_by_offset) do
    offset = shifted_offset(occurrence.urn_range.byte_start, edits)
    expected = expected_quote(action, occurrence)

    case Map.get(actual_by_offset, offset) do
      %{quoted: ^expected} -> nil
      nil -> nil
      actual -> deleted_quote_owner(actual, planned, edits)
    end
  end

  defp reject_rebinding({action, _edit, occurrence}, culprits)
       when is_map_key(culprits, action.source_offset) do
    {%{
       action
       | state: :flagged,
         reason: :citation_rebinding,
         detail:
           "Removing this citation would attach its quotation to another citation; review manually."
     }, nil, occurrence}
  end

  defp reject_rebinding(entry, _culprits), do: entry

  defp expected_quote(%{state: :quote_relaxed, replacement_quote: replacement}, _occurrence),
    do: replacement

  defp expected_quote(_action, occurrence), do: occurrence.quoted

  defp deleted_quote_owner(%{quote_range: nil}, _planned, _edits), do: nil

  defp deleted_quote_owner(actual, planned, edits) do
    Enum.find_value(planned, fn
      {%{state: :no_sources, source_offset: source_offset}, edit,
       %{quote_range: %{byte_start: quote_start}}}
      when not is_nil(edit) ->
        if shifted_offset(quote_start, edits) == actual.quote_range.byte_start,
          do: source_offset,
          else: nil

      _ ->
        nil
    end)
  end

  defp shifted_offset(original_offset, edits) do
    Enum.reduce(edits, original_offset, fn edit, shifted ->
      if edit.range.byte_end <= original_offset do
        shifted + byte_size(edit.after) - (edit.range.byte_end - edit.range.byte_start)
      else
        shifted
      end
    end)
  end

  defp interval(range, owner), do: {range.byte_start, range.byte_end, owner}

  defp apply_edits(original, edits), do: EvidenceInput.apply_edits(original, edits)
end
