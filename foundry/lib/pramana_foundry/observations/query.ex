defmodule PramanaFoundry.Observations.Query do
  @moduledoc """
  Bounded request for canonical protected observations.

  `effect_ids` are explicit lookup identities, not a request to enumerate protected
  storage. `cursor` is an offset into the stable request order (the three pointer
  slots first, followed by the supplied effect IDs).
  """

  @enforce_keys []
  defstruct schema_version: 1,
            effect_ids: [],
            include_pointers: true,
            cursor: 0,
            limit: 20,
            max_bytes: 65_536,
            max_age_ms: 30_000

  @type t :: %__MODULE__{
          schema_version: 1,
          effect_ids: [String.t()],
          include_pointers: boolean(),
          cursor: non_neg_integer(),
          limit: pos_integer(),
          max_bytes: pos_integer(),
          max_age_ms: non_neg_integer()
        }
end
