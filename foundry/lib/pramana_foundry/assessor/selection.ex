defmodule PramanaFoundry.Assessor.Selection do
  @moduledoc false

  @enforce_keys [
    :mode,
    :mandatory,
    :baseline_optional,
    :recommended_optional,
    :delivered_optional,
    :assessment,
    :applied?,
    :fallback_reason
  ]
  defstruct [
    :mode,
    :mandatory,
    :baseline_optional,
    :recommended_optional,
    :delivered_optional,
    :assessment,
    :applied?,
    :fallback_reason
  ]

  @type t :: %__MODULE__{}
end
