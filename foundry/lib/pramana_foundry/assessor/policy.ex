defmodule PramanaFoundry.Assessor.Policy do
  @moduledoc """
  Versioned advisory policy for optional-context assessment.

  Confidence is stored as fixed-point parts per million. The policy also binds the exact
  question-set and selection-algorithm versions plus the maximum optional context that an
  enabled assessment may place in the initial context. These fields are identity inputs,
  not workflow authority.
  """

  @max_ppm 1_000_000
  @max_initial_optional 24
  @version_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/

  @enforce_keys [
    :version,
    :question_set_version,
    :selection_version,
    :min_confidence_ppm,
    :max_initial_optional
  ]
  defstruct [
    :version,
    :question_set_version,
    :selection_version,
    :min_confidence_ppm,
    :max_initial_optional
  ]

  @type t :: %__MODULE__{
          version: String.t(),
          question_set_version: String.t(),
          selection_version: String.t(),
          min_confidence_ppm: 0..1_000_000,
          max_initial_optional: 1..24
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, :invalid_policy}
  def new(attrs) do
    attrs = if Keyword.keyword?(attrs), do: Map.new(attrs), else: attrs

    case attrs do
      %{
        version: version,
        question_set_version: question_set_version,
        selection_version: selection_version,
        min_confidence_ppm: confidence,
        max_initial_optional: max_initial_optional
      }
      when is_binary(version) and is_binary(question_set_version) and
             is_binary(selection_version) and is_integer(confidence) and confidence >= 0 and
             confidence <= @max_ppm and is_integer(max_initial_optional) and
             max_initial_optional >= 1 and max_initial_optional <= @max_initial_optional ->
        if valid_version?(version) and valid_version?(question_set_version) and
             valid_version?(selection_version) do
          {:ok,
           %__MODULE__{
             version: version,
             question_set_version: question_set_version,
             selection_version: selection_version,
             min_confidence_ppm: confidence,
             max_initial_optional: max_initial_optional
           }}
        else
          {:error, :invalid_policy}
        end

      _ ->
        {:error, :invalid_policy}
    end
  end

  defp valid_version?(value) do
    String.valid?(value) and byte_size(value) <= 96 and Regex.match?(@version_pattern, value)
  end
end
