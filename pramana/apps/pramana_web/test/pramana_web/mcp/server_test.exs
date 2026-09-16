defmodule PramanaWeb.MCP.ServerTest do
  @moduledoc """
  Tests the MCP server definition, capabilities, components, and lifecycle callbacks.
  """
  use Pramana.DataCase, async: true

  alias Anubis.MCP.Error, as: MCPError
  alias Anubis.Server.Frame
  alias PramanaWeb.MCP.Server

  describe "server configuration and capabilities" do
    test "server_info/0 returns server name and version" do
      info = Server.server_info()
      assert info["name"] == "pramana"
      assert {:ok, _} = Version.parse(info["version"])
    end

    test "server_capabilities/0 declares tools and resources" do
      caps = Server.server_capabilities()
      assert Map.has_key?(caps, "tools")
      assert Map.has_key?(caps, "resources")
    end

    test "supported_protocol_versions/0 returns supported MCP protocol versions" do
      versions = Server.supported_protocol_versions()
      assert is_list(versions)
      assert "2025-11-25" in versions
    end
  end

  describe "handle_request/2" do
    setup do
      frame = Frame.new(Server)
      {:ok, frame: frame}
    end

    test "handles tools/list request", %{frame: frame} do
      req = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "params" => %{}}
      assert {:reply, %{"tools" => tools}, _updated_frame} = Server.handle_request(req, frame)
      assert tools != []
      registered = Server.__components__(:tool)
      assert MapSet.new(Enum.map(tools, & &1.name)) == MapSet.new(Enum.map(registered, & &1.name))
      tool_names = Enum.map(tools, & &1.name)
      assert "search" in tool_names
      assert "verify_report" in tool_names
    end

    test "handles resources/list request", %{frame: frame} do
      req = %{"jsonrpc" => "2.0", "id" => 2, "method" => "resources/list", "params" => %{}}

      assert {:reply, %{"resources" => resources}, _updated_frame} =
               Server.handle_request(req, frame)

      assert Enum.sort(Enum.map(resources, & &1.uri)) == [
               "pramana://guide",
               "pramana://inventory"
             ]
    end

    test "handles resources/read request for pramana://guide", %{frame: frame} do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "resources/read",
        "params" => %{"uri" => "pramana://guide"}
      }

      assert {:reply, %{"contents" => [%{"text" => text, "uri" => "pramana://guide"}]}, _} =
               Server.handle_request(req, frame)

      assert text =~ "Querying the Pramāṇa corpus"
    end

    test "handles resources/read request for pramana://inventory", %{frame: frame} do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "resources/read",
        "params" => %{"uri" => "pramana://inventory"}
      }

      assert {:reply, %{"contents" => [%{"text" => text, "uri" => "pramana://inventory"}]}, _} =
               Server.handle_request(req, frame)

      assert {:ok, inventory} = Jason.decode(text)
      assert Map.has_key?(inventory, "bake_id")
      assert Map.has_key?(inventory, "corpus")
    end

    test "handles tools/call request for define_from_canon", %{frame: frame} do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "define_from_canon", "arguments" => %{"term" => "涅槃"}}
      }

      assert {:reply, %{"content" => [%{"text" => text}], "isError" => false}, _} =
               Server.handle_request(req, frame)

      assert {:ok, decoded} = Jason.decode(text)
      assert decoded["term"] == "涅槃"
      assert is_list(decoded["groups"])
    end

    test "returns method_not_found error for unknown method", %{frame: frame} do
      req = %{"jsonrpc" => "2.0", "id" => 6, "method" => "unknown/method", "params" => %{}}
      assert {:error, %MCPError{reason: :method_not_found}, _} = Server.handle_request(req, frame)
    end
  end
end
