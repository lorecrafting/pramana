defmodule PramanaFoundry.Assessor.Transport do
  @moduledoc false

  @callback post(binary(), keyword()) ::
              {:ok, non_neg_integer(), %{optional(String.t()) => String.t()}, binary()}
              | {:error, atom()}
end
