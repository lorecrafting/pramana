defmodule Pramana.Acquire.CBETA.CatalogTest do
  use ExUnit.Case, async: true

  alias Pramana.Acquire.CBETA.Catalog

  defp tree(paths) do
    %{
      "truncated" => false,
      "tree" =>
        Enum.map(paths, fn
          {path, size} -> %{"type" => "blob", "path" => path, "size" => size}
          path -> %{"type" => "blob", "path" => path, "size" => 100}
        end)
    }
  end

  # Acquisition downloads the WHOLE repository tarball once per call — about 2 GB — so
  # fetching the seven alternative-edition collections one at a time is seven downloads of
  # the same archive for 74 works between them.
  describe "several canons in one call" do
    @paths [
      "T/T09/T09n0262.xml",
      "K/K01/K01n0001.xml",
      "A/A01/A01n0001.xml",
      "X/X08/X08n0240.xml"
    ]

    test "a comma-separated list keeps exactly those collections" do
      {:ok, entries} = Catalog.parse_tree(tree(@paths), canon: "K,A")

      assert entries |> Enum.map(& &1.canon) |> Enum.sort() == ["A", "K"]
    end

    test "whitespace around a name does not silently drop it" do
      {:ok, entries} = Catalog.parse_tree(tree(@paths), canon: "K, A")

      assert length(entries) == 2
    end

    test "a single canon still behaves as it always did" do
      {:ok, entries} = Catalog.parse_tree(tree(@paths), canon: "T")

      assert Enum.map(entries, & &1.canon) == ["T"]
    end

    test "no canon means every collection" do
      {:ok, entries} = Catalog.parse_tree(tree(@paths), [])

      assert length(entries) == 4
    end

    # An empty string is not "everything" — it is a caller who built the flag from a
    # variable that turned out blank, and silently acquiring 5,005 works would be an
    # expensive way to find that out. It filters to nothing instead.
    test "an empty list of canons is treated as no filter, not as a match-all surprise" do
      {:ok, entries} = Catalog.parse_tree(tree(@paths), canon: "")

      assert length(entries) == 4
    end
  end

  describe "parse_tree/2" do
    test "derives canon, volume, number and work id from the path alone" do
      {:ok, [entry]} = Catalog.parse_tree(tree(["T/T09/T09n0262.xml"]), [])

      assert entry.canon == "T"
      assert entry.volume == 9
      assert entry.number == "0262"
      assert entry.work_id == "T0262"
      assert entry.path == "T/T09/T09n0262.xml"
    end

    test "handles collections with multi-letter codes" do
      {:ok, [ga]} = Catalog.parse_tree(tree(["GA/GA01/GA01n0001.xml"]), [])
      assert ga.canon == "GA"
      assert ga.volume == 1
    end

    test "handles two-digit and three-digit volumes" do
      {:ok, entries} =
        Catalog.parse_tree(tree(["T/T85/T85n2865.xml", "X/X100/X100n1234.xml"]), [])

      assert Enum.map(entries, & &1.volume) |> Enum.sort() == [85, 100]
    end

    test "filters by canon" do
      paths = ["T/T09/T09n0262.xml", "X/X01/X01n0001.xml", "J/J01/J01n0001.xml"]
      {:ok, entries} = Catalog.parse_tree(tree(paths), canon: "T")

      assert Enum.map(entries, & &1.work_id) == ["T0262"]
    end

    test "ignores trees, non-XML, and schema files" do
      nodes = %{
        "truncated" => false,
        "tree" => [
          %{"type" => "tree", "path" => "T/T09"},
          %{"type" => "blob", "path" => "README.md"},
          %{"type" => "blob", "path" => "schema/cbeta-p5.rnc"},
          %{"type" => "blob", "path" => "T/T09/T09n0262.xml", "size" => 1}
        ]
      }

      assert {:ok, [%{work_id: "T0262"}]} = Catalog.parse_tree(nodes, [])
    end

    test "sorts by canon, volume, then number for a stable enqueue order" do
      paths = ["T/T09/T09n0263.xml", "T/T01/T01n0001.xml", "T/T09/T09n0262.xml"]
      {:ok, entries} = Catalog.parse_tree(tree(paths), [])

      assert Enum.map(entries, & &1.work_id) == ["T0001", "T0262", "T0263"]
    end

    test "carries sizes so a run can be costed before it starts" do
      {:ok, [entry]} = Catalog.parse_tree(tree([{"T/T09/T09n0262.xml", 1_123_303}]), [])
      assert entry.bytes == 1_123_303
    end
  end

  describe "truncation" do
    test "a truncated tree is an ERROR, never a partial catalog" do
      # Silently baking a partial corpus is the failure that surfaces much later as an
      # unexplainable missing citation.
      assert {:error, :tree_truncated} = Catalog.parse_tree(%{"truncated" => true}, [])
    end

    test "an unexpected response shape is an error too" do
      assert {:error, :unexpected_tree_response} = Catalog.parse_tree(%{"nope" => 1}, [])
    end
  end

  describe "unparsed/1" do
    test "surfaces XML paths that do not match the naming convention" do
      nodes = tree(["T/T09/T09n0262.xml", "weird/thing.xml"])
      assert Catalog.unparsed(nodes) == ["weird/thing.xml"]
    end

    test "is empty for the real convention" do
      assert Catalog.unparsed(tree(["T/T09/T09n0262.xml", "X/X01/X01n0001.xml"])) == []
    end
  end

  describe "fetch/2" do
    test "requests the recursive tree at the pinned sha" do
      fetcher = fn url ->
        assert url =~ "git/trees/deadbeef?recursive=1"
        {:ok, Jason.encode!(tree(["T/T09/T09n0262.xml"]))}
      end

      assert {:ok, [%{work_id: "T0262"}]} =
               Catalog.fetch("deadbeef", fetcher: fetcher, repo: "cbeta-org/xml-p5")
    end

    test "propagates transport errors" do
      fetcher = fn _ -> {:error, :timeout} end
      assert {:error, :timeout} = Catalog.fetch("sha", fetcher: fetcher)
    end
  end
end
