defmodule Pramana.Pilot.DerivationReadiness do
  @moduledoc """
  Decides whether one source bake has the clean derivation receipts required by the
  Chinese pilot scope.

  This is deliberately narrower than "all derivations are good." It checks only that the
  four deterministic producers the pilot depends on ran over the required full/default
  scopes and that their recorded input/output digests still match the database.
  """

  alias Pramana.Commentary
  alias Pramana.Corpus.Bake, as: BakeSchema
  alias Pramana.Corpus.DerivationRun
  alias Pramana.Derivations
  alias Pramana.Repo

  @requirements [
    {"quotations_scan", &__MODULE__.quotation_scope?/1},
    {"relations_title", &__MODULE__.title_scope?/1},
    {"relations_shared_text", &__MODULE__.shared_text_scope?/1},
    {"commentary_align", &__MODULE__.commentary_scope?/1}
  ]

  @type result :: %{
          ready: boolean(),
          source_bake_id: String.t(),
          derivations: %{String.t() => map()}
        }

  @doc "Checks every derivation receipt required by the pilot."
  @spec check(String.t()) :: result()
  def check(source_bake_id) when is_binary(source_bake_id) and source_bake_id != "" do
    if Repo.get(BakeSchema, source_bake_id) do
      derivations =
        Map.new(@requirements, fn {kind, coverage?} ->
          {kind, check_kind(source_bake_id, kind, coverage?)}
        end)

      %{
        ready: Enum.all?(derivations, fn {_kind, result} -> result.state == "ready" end),
        source_bake_id: source_bake_id,
        derivations: derivations
      }
    else
      %{
        ready: false,
        source_bake_id: source_bake_id,
        derivations:
          Map.new(@requirements, fn {kind, _coverage?} ->
            {kind, %{state: "source_bake_missing"}}
          end)
      }
    end
  end

  @doc false
  def quotation_scope?(%DerivationRun{} = run) do
    run.scope["source"] in [nil, "cbeta"] and
      is_nil(run.scope["division"]) and
      is_nil(run.scope["work"]) and
      run.parameters["min_length"] == 20
  end

  @doc false
  def title_scope?(%DerivationRun{} = run) do
    run.scope == %{"mode" => "full"} and run.parameters["min_title"] == 3
  end

  @doc false
  def shared_text_scope?(%DerivationRun{} = run) do
    run.scope == %{"mode" => "full"} and run.parameters["min_passages"] == 1
  end

  @doc false
  def commentary_scope?(%DerivationRun{} = run) do
    is_nil(run.scope["work"]) and
      is_nil(run.parameters["min_density_override"]) and
      run.parameters["grapheme_window"] == Commentary.window() and
      run.parameters["root_min_density"] == Commentary.min_density() and
      run.parameters["subcommentary_min_density"] == Commentary.min_density("subcommentary")
  end

  defp check_kind(source_bake_id, kind, coverage?) do
    runs = Derivations.for_bake(source_bake_id, kind)
    qualifying = Enum.filter(runs, coverage?)

    case Enum.find_value(qualifying, &accepted_receipt/1) do
      nil -> missing_result(runs, qualifying)
      result -> result
    end
  end

  defp accepted_receipt(%DerivationRun{status: "complete"} = run) do
    expected_version = Derivations.version(run.derivation)
    current_input = Derivations.current_input_digest(run)
    {current_output, output_count} = Derivations.current_output_snapshot(run)

    cond do
      run.implementation_version != expected_version ->
        false

      run.input_digest != current_input ->
        false

      run.output_digest != current_output ->
        false

      not output_count_evidence?(run, output_count) ->
        false

      true ->
        %{
          state: "ready",
          receipt_id: run.id,
          completed_at: run.completed_at,
          implementation_version: run.implementation_version,
          input_digest: run.input_digest,
          output_digest: run.output_digest,
          output_count: output_count
        }
    end
  end

  defp accepted_receipt(_run), do: false

  defp missing_result([], _qualifying), do: %{state: "missing_receipt"}

  defp missing_result(_runs, []),
    do: %{state: "missing_required_coverage"}

  defp missing_result(_runs, qualifying) do
    run = hd(qualifying)
    diagnose(run)
  end

  defp output_count_evidence?(%DerivationRun{} = run, current_output_count) do
    expected = run.stats["expected_output_count"]
    recorded = run.stats["output_count"]

    is_integer(expected) and expected >= 0 and
      expected == current_output_count and
      recorded == current_output_count and
      run.stats["output_count_matches_expected"] == true
  end

  defp diagnose(%DerivationRun{status: status} = run) when status != "complete" do
    %{
      state: "partial_receipt",
      receipt_id: run.id,
      failures: run.stats["failures"],
      input_changed_during_run: run.stats["input_changed_during_run"],
      expected_output_count: run.stats["expected_output_count"],
      output_count: run.stats["output_count"],
      output_count_matches_expected: run.stats["output_count_matches_expected"]
    }
  end

  defp diagnose(%DerivationRun{} = run) do
    expected_version = Derivations.version(run.derivation)
    current_input = Derivations.current_input_digest(run)
    {current_output, output_count} = Derivations.current_output_snapshot(run)

    cond do
      run.implementation_version != expected_version ->
        %{
          state: "stale_implementation",
          receipt_id: run.id,
          recorded: run.implementation_version,
          current: expected_version
        }

      run.input_digest != current_input ->
        %{
          state: "stale_input",
          receipt_id: run.id,
          recorded: run.input_digest,
          current: current_input
        }

      run.output_digest != current_output ->
        %{
          state: "stale_output",
          receipt_id: run.id,
          recorded: run.output_digest,
          current: current_output,
          current_output_count: output_count
        }

      not output_count_evidence?(run, output_count) ->
        %{
          state: "invalid_output_count_evidence",
          receipt_id: run.id,
          expected_output_count: run.stats["expected_output_count"],
          recorded_output_count: run.stats["output_count"],
          current_output_count: output_count,
          output_count_matches_expected: run.stats["output_count_matches_expected"]
        }

      true ->
        %{state: "unaccepted_receipt", receipt_id: run.id}
    end
  end
end
