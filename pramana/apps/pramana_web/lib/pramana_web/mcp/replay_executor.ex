defmodule PramanaWeb.MCP.ReplayExecutor do
  @moduledoc """
  Re-executes a `replay` record against the tools that produced it.

  `Pramana.Report` verifies a report but cannot run the tools it names: those live here, and
  the domain application has no web dependency. So the executor is injected, and this is the
  real one.

  ## Only tools that read, named explicitly

  The table below is a whitelist rather than a lookup into the server's registry, and that is
  deliberate on two counts. A report is **untrusted input** — its replay records name tools
  and arguments chosen by whoever wrote it — and the MCP surface is read-only by invariant
  #7 today, which a future tool must not be able to change by accident. An unknown tool is an
  error the report carries, not something to resolve dynamically.

  `verify_report` is deliberately absent from its own table: a report that asks to verify a
  report is a loop, and a loop over untrusted input is a denial of service.
  """

  alias PramanaWeb.MCP.Tools

  @tools %{
    "search" => Tools.Search,
    "search_translations" => Tools.SearchTranslations,
    "survey_corpus" => Tools.SurveyCorpus,
    "get_passage" => Tools.GetPassage,
    "get_outline" => Tools.GetOutline,
    "get_commentaries" => Tools.GetCommentaries,
    "get_glosses" => Tools.GetGlosses,
    "get_parallels" => Tools.GetParallels,
    "get_quotations" => Tools.GetQuotations,
    "get_readings" => Tools.GetReadings,
    "get_works_by_person" => Tools.GetWorksByPerson,
    "get_person" => Tools.GetPerson,
    "compare_versions" => Tools.CompareVersions,
    "compare_witnesses" => Tools.CompareWitnesses,
    "define_from_canon" => Tools.DefineFromCanon,
    "verify_citation" => Tools.VerifyCitation
  }

  @doc "The tools a replay record may name."
  @spec tools() :: [String.t()]
  def tools, do: Map.keys(@tools)

  @doc """
  Returns an executor for `Pramana.Report.verify/2`.
  """
  @spec executor() :: (String.t(), map() -> {:ok, map()} | {:error, term()})
  def executor do
    fn tool, arguments -> run(tool, arguments) end
  end

  defp run(tool, arguments) do
    case Map.fetch(@tools, tool) do
      :error -> {:error, {:unknown_tool, tool}}
      {:ok, module} -> invoke(module, arguments)
    end
  end

  # ENSURE THE MODULE IS LOADED BEFORE ATOMIZING ITS FIELD NAMES.
  #
  # `to_existing_atom` is the right tool and it has a trap: an atom exists only once the
  # module defining it has been *loaded*, and module loading is lazy. Before this line,
  # `get_person` with a perfectly valid `authority_id` failed with "no function clause
  # matching" — the key had been dropped because `:authority_id` did not yet exist in the
  # atom table. A caught test, and it would have looked like a schema bug in production.
  defp invoke(module, arguments) do
    Code.ensure_loaded!(module)

    case module.execute(atomize(arguments), %{}) do
      {:reply, response, _frame} -> decode(response)
      other -> {:error, {:unexpected_reply, other}}
    end
  rescue
    error -> {:error, {:tool_raised, Exception.message(error)}}
  end

  # `to_existing_atom`, because the keys come from a report nobody wrote here and an
  # arbitrary string must not be able to grow the atom table. A key no tool declares is
  # dropped rather than passed on — the schema would reject it anyway, and dropping it
  # produces a clearer failure than a validation error about a field that cannot exist.
  defp atomize(arguments) do
    Map.new(arguments, fn {key, value} -> {safe_atom(key), value} end)
    |> Map.delete(nil)
  end

  defp safe_atom(key) when is_atom(key), do: key

  defp safe_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  # `isError` FIRST. An error response carries prose in the same `content` shape as a
  # success carries JSON, so the success clause matched it, tried to decode the message and
  # reported `:tool_returned_unparseable_json` — an error about our parser, for a tool that
  # had refused perfectly clearly.
  @doc false
  def decode(%{isError: true} = response), do: {:error, {:tool_error, error_text(response)}}

  def decode(%{content: [%{"text" => json} | _]}) do
    case Jason.decode(json) do
      {:ok, payload} -> {:ok, payload}
      {:error, _} -> {:error, :tool_returned_unparseable_json}
    end
  end

  def decode(other), do: {:error, {:unexpected_response, other}}

  defp error_text(%{content: [%{"text" => text} | _]}), do: text
  defp error_text(_), do: "(no detail)"
end
