defmodule PramanaWeb.MCP.ReplayExecutorTest do
  @moduledoc """
  Re-running a replay record, and refusing to.

  A replay record names a tool and arguments chosen by whoever wrote the report, so this is
  **untrusted input reaching a dispatcher**. Every test here is about a refusal: what is not
  in the whitelist, what cannot become an atom, and which arguments must never reach a tool.
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

    test "unknown argument keys are refused without allocating atoms" do
      key = "replay_unknown_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end

      assert {:error, {:invalid_arguments, :unknown_field}} =
               ReplayExecutor.executor().("survey_corpus", %{"query" => "一切眾生", key => 1})

      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    end

    test "handles atom keys in arguments safely" do
      assert {:ok, payload} = ReplayExecutor.executor().("survey_corpus", %{query: "一切眾生"})
      assert is_map(payload)
    end

    test "a missing required argument is refused before calling the tool" do
      assert {:error, {:invalid_arguments, :schema_mismatch}} =
               ReplayExecutor.executor().("get_passage", %{})
    end
  end

  describe "decode/1" do
    test "decodes valid JSON content into map payload" do
      response = %{content: [%{"text" => ~s({"result": "ok", "count": 42})}]}
      assert {:ok, %{"result" => "ok", "count" => 42}} = ReplayExecutor.decode(response)
    end

    test "returns tool_returned_unparseable_json on malformed JSON" do
      response = %{content: [%{"text" => "{broken json"}]}
      assert {:error, :tool_returned_unparseable_json} = ReplayExecutor.decode(response)
    end

    test "decodes error response with detail text" do
      response = %{isError: true, content: [%{"text" => "Something went wrong"}]}
      assert {:error, {:tool_error, "Something went wrong"}} = ReplayExecutor.decode(response)
    end

    test "decodes error response with fallback detail when content is missing text" do
      response = %{isError: true, content: []}
      assert {:error, {:tool_error, "(no detail)"}} = ReplayExecutor.decode(response)
    end

    test "returns unexpected_response for unknown response shapes" do
      assert {:error, {:unexpected_response, :unknown}} = ReplayExecutor.decode(:unknown)
      assert {:error, {:unexpected_response, %{}}} = ReplayExecutor.decode(%{})
    end
  end
end
