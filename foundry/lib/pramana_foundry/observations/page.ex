defmodule PramanaFoundry.Observations.Page do
  @moduledoc "Typed result envelope for canonical observation queries."

  @enforce_keys [
    :status,
    :quality,
    :freshness,
    :observed_at,
    :source,
    :items,
    :next_cursor,
    :size_bytes,
    :error_code
  ]
  defstruct schema_version: 1,
            status: :ok,
            quality: :canonical,
            freshness: :unknown,
            observed_at: nil,
            source: nil,
            items: [],
            next_cursor: nil,
            size_bytes: 0,
            error_code: nil

  @type t :: %__MODULE__{
          schema_version: 1,
          status: :ok | :unavailable | :corrupt,
          quality: :canonical | :unavailable | :corrupt,
          freshness: :fresh | :stale | :unknown,
          observed_at: DateTime.t() | nil,
          source: map() | nil,
          items: [PramanaFoundry.Observations.Observation.t()],
          next_cursor: non_neg_integer() | nil,
          size_bytes: non_neg_integer(),
          error_code: atom() | nil
        }
end
