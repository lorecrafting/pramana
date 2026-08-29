defmodule PramanaWeb.MCP.ReplayExecutorTest do
  @moduledoc """
  Re-running a replay record, and refusing to.

  A replay record names a tool and arguments chosen by whoever wrote the report, so this is
  **untrusted input reaching a dispatcher**. Every test here is about a refusal: what is not
  in the whitelist, what cannot become an atom, and what a raising tool does.
  """
  use Pramana.DataCase, async: true

  alias PramanaWeb.MCP.ReplayExecutor

  describe "tools/0" do
    test "is an explicit whitelist of reads, not the server registry" do
      tools = ReplayExecutor.tools()

      assert "search" in tools
      assert "survey_corpus" in tools
      assert "get_person" in tools

      # Not itself: a report asking to verify a report is a loop over untrusted input.
      refute "verify_report" in tools
    end

    test "every whitelisted name is a tool the server actually registers" do
      registered =
        "apps/pramana_web/lib/pramana_web/mcp/server.ex"
        |> Path.expand(Path.expand("../../../../..", __DIR__))
        |> File.read!()
        |> then(&Regex.scan(~r/component\(PramanaWeb\.MCP\.Tools\.(\w+)\)/, &1))
        |> Enum.map(fn [_, module] -> Macro.underscore(module) end)
        |> MapSet.new()

      # A whitelist naming a tool that no longer exists fails at report-verification time,
      # in front of a caller, rather than here.
      for tool <- ReplayExecutor.tools() do
        assert MapSet.member?(registered, tool), "#{tool} is whitelisted but not registered"
      end
    end
  end

  describe "executor/0" do
    test "runs a whitelisted tool with string keys and returns its decoded payload" do
      assert {:ok, payload} = ReplayExecutor.executor().("survey_corpus", %{"query" => "一切眾生"})

      assert is_map(payload)
      # The replay stamp rides on it, so a verified claim can itself be re-cited.
      assert payload["replay"]["tool"] == "survey_corpus"
    end

    test "a tool that refuses reaches the caller as an error, not an empty success" do
      # No such person. `get_person` returns an MCP error response, and the executor must
      # not turn that into `{:ok, %{}}`.
      assert {:error, {:tool_error, text}} =
               ReplayExecutor.executor().("get_person", %{"authority_id" => "A_NOPE"})

      assert text =~ "authority person"
    end

    test "an unwhitelisted tool is refused by name" do
      assert {:error, {:unknown_tool, "rm_rf"}} = ReplayExecutor.executor().("rm_rf", %{})
    end

    test "an argument key no tool declares is dropped, not converted to an atom" do
      # `to_existing_atom`: a report must not be able to grow the atom table by naming
      # arbitrary keys.
      assert {:ok, _} =
               ReplayExecutor.executor().("survey_corpus", %{
                 "query" => "一切眾生",
                 "definitely_not_a_declared_field_xyzzy" => 1
               })
    end
  end
end
