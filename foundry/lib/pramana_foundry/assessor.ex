defmodule PramanaFoundry.Assessor do
  @moduledoc """
  Provider-neutral advisory assessment boundary.

  An assessor may rank optional context, but it never grants workflow authority,
  accepts work, spends a budget, changes Git state, or weakens a mandatory gate.
  Stage A has no production transport: callers must supply an adapter explicitly.
  """

  alias PramanaFoundry.Assessor.Request
  alias PramanaFoundry.Assessor.Result

  @callback assess(Request.t(), keyword()) :: Result.t()

  @spec call(module() | function(), Request.t(), keyword()) :: Result.t()
  def call(adapter, %Request{} = request, opts \\ []) do
    try do
      result =
        cond do
          is_atom(adapter) and Code.ensure_loaded?(adapter) and
              function_exported?(adapter, :assess, 2) ->
            adapter.assess(request, opts)

          is_function(adapter, 2) ->
            adapter.(request, opts)

          true ->
            Result.invalid(request, :invalid_adapter)
        end

      if match?(%Result{}, result),
        do: result,
        else: Result.invalid(request, :invalid_adapter_result)
    rescue
      _ -> Result.unavailable(request, :adapter_failure)
    catch
      _, _ -> Result.unavailable(request, :adapter_failure)
    end
  end
end
