defmodule PramanaWeb.MCP.ResourcesTest do
  @moduledoc """
  The two MCP resources are how a model learns what this corpus *is* before querying it.

  These tests guard the boundary, not the prose. Two failures here would be invisible in
  normal use and would quietly cost the project its differentiator: a resource that is
  registered but not advertised, and a resource whose `name` is nil because the macro
  generates `name/0` from `use` options and does not mark it overridable — a hand-written
  `def name` is silently shadowed and compiles clean.
  """
  use Pramana.DataCase, async: true

  alias Anubis.Server.Component.Resource
  alias Anubis.Server.Response
  alias PramanaWeb.MCP.Resources.Guide
  alias PramanaWeb.MCP.Resources.Inventory
  alias PramanaWeb.MCP.Server

  @resources [Guide, Inventory]

  # Resources carry a `contents` map, not the `content` list tools use. Going through
  # `to_protocol/3` asserts against the actual wire shape rather than the struct.
  defp read!(mod) do
    {:reply, response, _frame} = mod.read(%{}, %{})

    response
    |> Response.to_protocol(mod.uri(), mod.mime_type())
    |> Map.fetch!("text")
  end

  describe "registration" do
    test "the server advertises the resources capability" do
      # Registering a component without the capability leaves it unreachable: a client
      # never calls resources/list, so nothing errors and nothing is served.
      assert %{"resources" => _} = Server.server_capabilities()
    end

    test "both resources are registered with a usable identity" do
      registered = Server.__components__(:resource)

      assert length(registered) == length(@resources)

      for %Resource{} = resource <- registered do
        assert is_binary(resource.name) and resource.name != ""
        assert is_binary(resource.uri) and resource.uri =~ ~r{^pramana://}
        assert is_binary(resource.description) and resource.description != ""
      end
    end

    test "each module's name and uri survive the macro" do
      # The regression: `def name` in the module body loses to the option default (nil),
      # so the resource lists as a nameless entry.
      for mod <- @resources do
        assert is_binary(mod.name()) and mod.name() != ""
        assert mod.uri() =~ ~r{^pramana://}
      end
    end

    test "URIs are distinct" do
      uris = Enum.map(@resources, & &1.uri())
      assert uris == Enum.uniq(uris)
    end
  end

  describe "pramana://guide" do
    test "reads as markdown naming the tools it describes" do
      assert Guide.mime_type() == "text/markdown"
      body = read!(Guide)

      # Guidance that names a tool the server does not serve is worse than no guidance:
      # the model plans around a call that will fail.
      for tool <- ~w(search survey_corpus get_passage get_outline verify_citation) do
        assert body =~ tool
      end
    end

    test "teaches the provenance axes, which is the point of having it" do
      body = read!(Guide)

      for axis <- ~w(composition_origin text_role division apocryphon) do
        assert body =~ axis
      end
    end
  end

  describe "pramana://inventory" do
    test "reads as JSON carrying live corpus counts" do
      assert Inventory.mime_type() == "application/json"

      data = Jason.decode!(read!(Inventory))

      assert is_map(data["corpus"])
      assert is_map(data["embedding_coverage"])
      assert is_map(data["by_composition_origin"])
      assert is_map(data["by_text_role"])
      assert is_list(data["divisions"])

      # Without this a model cannot tell "the canon does not say that" from "that part
      # of the canon is not loaded", which is the whole reason the resource exists.
      assert data["note"] =~ "not loaded"
    end

    test "works on an empty corpus rather than crashing" do
      # An inventory that only renders once data is present is useless exactly when a
      # model most needs it — on a fresh or partial bake.
      data = Jason.decode!(read!(Inventory))

      assert data["by_composition_origin"] == %{}
      assert data["divisions"] == []
    end
  end
end
