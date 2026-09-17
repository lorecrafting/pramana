defmodule PramanaFoundry.Assessor.Policy do
  @moduledoc """
  Versioned advisory policy for one assessment use case.

  Confidence is stored as fixed-point parts per million. Stage A deliberately does not
  define a universal threshold; the caller must name the evaluated policy version and
  threshold it intends to test.
  """

  @max_ppm 1_000_000
  @version_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/

  @enforce_keys [:version, :min_confidence_ppm]
  defstruct [:version, :min_confidence_ppm]

  @type t :: %__MODULE__{version: String.t(), min_confidence_ppm: 0..1_000_000}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, :invalid_policy}
  def new(attrs) do
    attrs = if Keyword.keyword?(attrs), do: Map.new(attrs), else: attrs

    case attrs do
      %{version: version, min_confidence_ppm: confidence}
      when is_binary(version) and is_integer(confidence) and confidence >= 0 and
             confidence <= @max_ppm ->
        if String.valid?(version) and byte_size(version) <= 96 and
             Regex.match?(@version_pattern, version),
          do: {:ok, %__MODULE__{version: version, min_confidence_ppm: confidence}},
          else: {:error, :invalid_policy}

      _ ->
        {:error, :invalid_policy}
    end
  end
end
