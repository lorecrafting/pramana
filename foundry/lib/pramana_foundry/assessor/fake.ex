defmodule PramanaFoundry.Assessor.Fake do
  @moduledoc "Deterministic model-free assessor used by fixtures and offline evaluation."

  @behaviour PramanaFoundry.Assessor

  alias PramanaFoundry.Assessor.Request
  alias PramanaFoundry.Assessor.Result

  @impl true
  def assess(%Request{} = request, opts) do
    case Keyword.get(opts, :fun) do
      fun when is_function(fun, 1) ->
        fun.(request)

      fun when is_function(fun, 2) ->
        fun.(request, opts)

      _ ->
        case Keyword.get(opts, :result) do
          %Result{} = result -> result
          _ -> Result.unavailable(request, :fake_not_configured)
        end
    end
  end
end
