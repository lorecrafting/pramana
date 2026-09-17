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

  ## A replay must not silently become another query

  Arguments are checked before `execute/2`, which normally receives validated MCP input.
  Unknown top-level fields, ambiguous atom/string keys, missing required values and wrong
  declared types are refused as `:invalid_arguments`, not dropped or coerced. Field names
  and the validator come from the selected component's schema, never the global atom table
  or a second list of tool parameters. No atoms are allocated from report input.

  Valid calls retain the component's validation/default behavior and the tool's own caps.
  This enforces declared constraints, not every restriction mentioned only in descriptions.
  A rejected replay is an execution error and leaves its report incomplete unless separate
  evidence genuinely fails; it is not a verified request or a refutation of the claim.
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

  defp invoke(module, arguments) do
    # Schemas and their atom keys must be loaded before inspecting them. A direct
    # execute/2 call bypasses the MCP dispatcher's normal validation boundary.
    Code.ensure_loaded!(module)

    with {:ok, params} <- normalize_arguments(arguments, module.__mcp_raw_schema__()),
         {:ok, params} <- validate_arguments(module, params) do
      case module.execute(params, %{}) do
        {:reply, response, _frame} -> decode(response)
        other -> {:error, {:unexpected_reply, other}}
      end
    end
  rescue
    error -> {:error, {:tool_raised, Exception.message(error)}}
  end

  defp normalize_arguments(arguments, schema)
       when is_map(arguments) and not is_struct(arguments) do
    fields = Map.new(schema, fn {field, _type} -> {Atom.to_string(field), field} end)

    Enum.reduce_while(arguments, {:ok, %{}}, fn {key, value}, {:ok, params} ->
      case Map.fetch(fields, field_name(key)) do
        {:ok, field} -> put_argument(params, field, value)
        :error -> {:halt, invalid_arguments(:unknown_field)}
      end
    end)
  end

  defp normalize_arguments(_arguments, _schema), do: invalid_arguments(:expected_object)

  # Atom keys are retained for existing in-process callers. Supplying both forms
  # of one field is ambiguous even when their values agree: never choose a winner.
  defp put_argument(params, field, value) do
    if Map.has_key?(params, field),
      do: {:halt, invalid_arguments(:duplicate_field)},
      else: {:cont, {:ok, Map.put(params, field, value)}}
  end

  defp field_name(key) when is_binary(key), do: key
  defp field_name(key) when is_atom(key), do: Atom.to_string(key)
  defp field_name(_key), do: nil

  defp validate_arguments(module, params) do
    case module.mcp_schema(params) do
      {:ok, validated} -> {:ok, validated}
      # Peri errors may contain supplied values. Return a stable refusal reason,
      # not pasted report data or a validation exception disguised as a tool error.
      {:error, _errors} -> invalid_arguments(:schema_mismatch)
    end
  end

  defp invalid_arguments(reason), do: {:error, {:invalid_arguments, reason}}

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
