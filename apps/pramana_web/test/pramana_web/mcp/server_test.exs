defmodule PramanaWeb.MCP.ServerTest do
  @moduledoc """
  Tests the MCP server definition, capabilities, components, and lifecycle callbacks.
  """
  use ExUnit.Case, async: true

  alias PramanaWeb.MCP.Server

  describe "server configuration and capabilities" do
    test "server_info/0 returns server name and version" do
      info = Server.server_info()
      assert info["name"] == "pramana"
      assert info["version"] == "0.1.0"
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

  describe "components registration" do
    test "registers all 19 tools and 2 resources" do
      components = Server.__components__()
      assert length(components) == 21

      tools = Server.__components__(:tool)
      assert length(tools) == 19

      resources = Server.__components__(:resource)
      assert length(resources) == 2
    end
  end

  describe "init/2" do
    test "initializes the frame successfully" do
      frame = %{some: "frame"}
      assert {:ok, ^frame} = Server.init(%{}, frame)
    end
  end
end
