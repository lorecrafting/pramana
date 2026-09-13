defmodule PramanaFoundry.Parity do
  @moduledoc """
  Retired Python-migration parity boundary.

  The Python supervisor used by the original parity harness no longer exists in the
  active source tree. Returning a successful zero-effect summary without comparing
  implementations was misleading, so FR-21 makes every former entry point fail closed.
  `shadow/2` returns success only for an explicit retired-metadata query, never for a
  comparison. Historical fixtures remain import-compatibility inputs; they are not live
  parity proof.
  """

  @retired_reason :retired_python_migration_parity

  @spec compare_fixture(atom(), Path.t()) :: map()
  def compare_fixture(kind, _path) do
    %{status: :retired, kind: kind, reason: @retired_reason}
  end

  @spec shadow(term(), keyword()) ::
          {:ok, %{status: :retired, reason: :retired_python_migration_parity}}
          | {:error, :retired_python_migration_parity}
  def shadow(_input, opts \\ []) do
    if opts == [retired_metadata: true] do
      {:ok, %{status: :retired, reason: @retired_reason}}
    else
      {:error, @retired_reason}
    end
  end
end
