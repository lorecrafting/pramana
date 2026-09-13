defmodule PramanaFoundry.Relocation.PathMapTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Relocation.PathMap

  @moduletag :path_map

  setup do
    tmp = Path.join(System.tmp_dir!(), "path-map-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)
    {:ok, tmp_dir: tmp}
  end

  test "new and resolve path mapping" do
    pm =
      PathMap.new("tx-001", [
        %{source: "/old/workspace/tasks", destination: "/new/workspace/tasks", kind: :worktree}
      ])

    # Direct match
    assert PathMap.resolve(pm, "/old/workspace/tasks") == "/new/workspace/tasks"

    # Child path resolution
    assert PathMap.resolve(pm, "/old/workspace/tasks/run1/prompt.json") ==
             "/new/workspace/tasks/run1/prompt.json"

    # Unmapped path stays unchanged
    assert PathMap.resolve(pm, "/some/other/path/file.txt") == "/some/other/path/file.txt"
  end

  test "longest prefix takes precedence" do
    pm =
      PathMap.new("tx-002", [
        %{source: "/workspace", destination: "/new_workspace", kind: :directory},
        %{
          source: "/workspace/tasks/special",
          destination: "/dedicated/tasks/special",
          kind: :worktree
        }
      ])

    assert PathMap.resolve(pm, "/workspace/tasks/special/item.txt") ==
             "/dedicated/tasks/special/item.txt"

    assert PathMap.resolve(pm, "/workspace/other/item.txt") ==
             "/new_workspace/other/item.txt"
  end

  test "reverse_resolve maps relocated paths back to historical locations" do
    pm =
      PathMap.new("tx-003", [
        %{source: "/legacy/root/runs", destination: "/archived/runs", kind: :directory}
      ])

    assert PathMap.reverse_resolve(pm, "/archived/runs/001/evidence.json") ==
             "/legacy/root/runs/001/evidence.json"
  end

  test "save and load round-trip with JSON persistence", %{tmp_dir: tmp} do
    file = Path.join(tmp, "path_map.json")

    pm =
      PathMap.new("tx-004", [
        %{source: "/src/dir", destination: "/dst/dir", kind: :directory}
      ])

    assert :ok = PathMap.save(pm, file)
    assert {:ok, loaded} = PathMap.load(file)

    assert loaded.relocation_id == "tx-004"
    assert loaded.schema_version == 1
    assert length(loaded.mappings) == 1
    assert hd(loaded.mappings).source == "/src/dir"
    assert hd(loaded.mappings).destination == "/dst/dir"
    assert hd(loaded.mappings).kind == :directory
  end

  test "chain maps paths through multiple relocations" do
    m1 =
      PathMap.new("tx-1", [
        %{source: "/step1/a", destination: "/step2/a", kind: :directory}
      ])

    m2 =
      PathMap.new("tx-2", [
        %{source: "/step2/a", destination: "/step3/a", kind: :directory}
      ])

    chained = PathMap.chain(m1, m2, "tx-combined")

    assert PathMap.resolve(chained, "/step1/a/file.txt") == "/step3/a/file.txt"
    assert PathMap.resolve(chained, "/step2/a/file.txt") == "/step3/a/file.txt"
  end
end
