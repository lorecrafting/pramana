defmodule PramanaFoundry.Workflow.Kernel.Execution do
  @moduledoc """
  The execution entity of an attempt, as a struct so Elixir's type checker sees its field
  names: a misspelled field at a site that binds `%Execution{} = execution` is a compile
  warning, where the string-keyed map it replaced read `nil` silently (FR-08B subcommit 3,
  D3). Read executions through `Kernel.Executions.executions/1` and `execution/2`.

  The rest of the state stays string-keyed. A struct encodes to JSON under its field names,
  so the serialised state is unchanged; `from_map/1` is the inverse, applied by
  `State.from_json/1`.
  """

  @derive JSON.Encoder
  @enforce_keys [:execution_id, :role, :lifecycle, :result, :sealed_sequence]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          execution_id: String.t(),
          role: String.t(),
          lifecycle: String.t(),
          result: String.t() | nil,
          sealed_sequence: non_neg_integer() | nil
        }

  @doc "The struct for a JSON-decoded execution object: exactly the five fields, or raises."
  @spec from_map(map()) :: t()
  def from_map(
        %{
          "execution_id" => execution_id,
          "role" => role,
          "lifecycle" => lifecycle,
          "result" => result,
          "sealed_sequence" => sealed_sequence
        } = map
      )
      when map_size(map) == 5 do
    %__MODULE__{
      execution_id: execution_id,
      role: role,
      lifecycle: lifecycle,
      result: result,
      sealed_sequence: sealed_sequence
    }
  end
end
