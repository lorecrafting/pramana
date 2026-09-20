defmodule PramanaFoundry.Assessor.Off do
  @moduledoc "Default assessor adapter. Performs no external work."

  @behaviour PramanaFoundry.Assessor

  alias PramanaFoundry.Assessor.Request
  alias PramanaFoundry.Assessor.Result

  @impl true
  def assess(%Request{} = request, _opts), do: Result.not_requested(request, :disabled)
end
