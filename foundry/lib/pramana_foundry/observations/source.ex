defmodule PramanaFoundry.Observations.Source do
  @moduledoc false

  @type state :: term()
  @type read_result ::
          {:ok, map(), DateTime.t()} | {:error, :not_found | :unavailable | :corrupt}

  @callback snapshot(state()) :: read_result()
  @callback fact(state(), map()) :: read_result()
end
