defmodule Pramana.PathsTest do
  @moduledoc "Path and data-isolation regression tests; owned temporary directories only."
  use ExUnit.Case, async: false

  alias Pramana.Paths

  setup do
    keys = [:project_root, :repository_root, :data_root]
    saved = Map.new(keys, &{&1, Application.fetch_env(:pramana, &1)})
    env = System.get_env("PRAMANA_DATA_ROOT")
    System.delete_env("PRAMANA_DATA_ROOT")
    Application.delete_env(:pramana, :data_root)
    root = Path.join(System.tmp_dir!(), "pramana-paths-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "pramana"))
    Application.put_env(:pramana, :project_root, Path.join(root, "pramana"))
    Application.put_env(:pramana, :repository_root, root)

    on_exit(fn ->
      for {key, previous} <- saved do
        case previous do
          {:ok, value} -> Application.put_env(:pramana, key, value)
          :error -> Application.delete_env(:pramana, key)
        end
      end

      if env,
        do: System.put_env("PRAMANA_DATA_ROOT", env),
        else: System.delete_env("PRAMANA_DATA_ROOT")

      File.rm_rf!(root)
    end)

    %{root: root, project: Path.join(root, "pramana")}
  end

  test "fresh checkout separates repository and project roots", %{root: root, project: project} do
    assert Paths.repository_root() == root
    assert Paths.project_root() == project
    assert Paths.data_root() == project
    assert Paths.project("sources.lock.json") == Path.join(project, "sources.lock.json")
  end

  test "external data changes raw paths, not tracked source paths", %{
    root: root,
    project: project
  } do
    data = Path.join(root, "existing data")
    System.put_env("PRAMANA_DATA_ROOT", data)
    assert Paths.data("raw/sc") == Path.join(data, "raw/sc")
    assert Paths.source("./raw/sc/a.json") == Path.join(data, "raw/sc/a.json")
    assert Paths.source("raw/sc/a.json") == Path.join(data, "raw/sc/a.json")
    assert Paths.source("sources/example.json") == Path.join(project, "sources/example.json")
    absolute = Path.join(root, "outside/custom.xml")
    assert Paths.source(absolute) == absolute
    refute File.exists?(data)
  end

  test "recorded raw provenance remains logical and external sources remain absolute", %{
    root: root
  } do
    System.put_env("PRAMANA_DATA_ROOT", root)
    raw = Path.join(root, "raw/cbeta/例.xml")
    assert Paths.record_source(raw) == "raw/cbeta/例.xml"
    assert Paths.source(Paths.record_source(raw)) == raw
    external = Path.join(root, "outside.xml")
    assert Paths.record_source(external) == external
  end

  test "legacy data fails closed until an explicit root is chosen", %{
    root: root,
    project: project
  } do
    File.write!(Path.join(root, "AGENTS.md"), "router")
    File.mkdir_p!(Path.join(root, "foundry"))
    File.mkdir_p!(Path.join(root, "raw"))
    assert Paths.data_root() == project
    File.write!(Path.join(root, "raw/evidence.xml"), "original")
    assert_raise ArgumentError, ~r/Legacy local data/, fn -> Paths.data_root() end
    System.put_env("PRAMANA_DATA_ROOT", root)
    assert Paths.data_root() == root
    System.put_env("PRAMANA_DATA_ROOT", project)
    assert Paths.data_root() == project
    assert File.read!(Path.join(root, "raw/evidence.xml")) == "original"
  end

  test "invalid roots cannot silently select a relative directory" do
    for value <- ["relative", "", "~/data", "/tmp/invalid" <> <<0>>] do
      Application.put_env(:pramana, :data_root, value)
      assert_raise ArgumentError, fn -> Paths.data_root() end
    end

    Application.put_env(:pramana, :data_root, 7)
    assert_raise ArgumentError, fn -> Paths.data_root() end
  end

  test "fixture isolation overrides an inherited operator environment", %{
    root: root,
    project: project
  } do
    live = Path.join(root, "live")
    System.put_env("PRAMANA_DATA_ROOT", live)
    Application.put_env(:pramana, :data_root, :project)
    assert Paths.data("raw") == Path.join(project, "raw")
    other_fixture = Path.join(root, "another-fixture")
    Application.put_env(:pramana, :project_root, other_fixture)
    assert Paths.data("raw") == Path.join(other_fixture, "raw")
    refute File.exists?(live)
  end

  test "tracked local manifest and ignored text roots can differ", %{root: root, project: project} do
    System.put_env("PRAMANA_DATA_ROOT", root)
    manifest = Path.join(project, "sources/local/example")
    assert Paths.local_text_dir(manifest) == Path.join(root, "sources/local/example/text")
    external = Path.join(root, "user-supplied-manifest")
    assert Paths.local_text_dir(external) == Path.join(external, "text")
  end
end
