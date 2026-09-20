defmodule PramanaFoundry.Observations.Observation do
  @moduledoc "A bounded, redacted canonical observation item."

  @enforce_keys [:kind, :status, :quality, :identity, :fact]
  defstruct [:kind, :status, :quality, :identity, :fact]

  @type t :: %__MODULE__{
          kind: :pointer | :effect_context,
          status: :present | :absent,
          quality: :canonical,
          identity: map(),
          fact: map()
        }
end
