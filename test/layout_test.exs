defmodule Repository.LayoutTest do
  @moduledoc "Model-free regression checks for the two independent project roots."
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @project Path.join(@root, "pramana")

  test "the Git root is neutral and both projects retain independent manifests" do
    refute File.exists?(Path.join(@root, "mix.exs"))
    refute File.exists?(Path.join(@root, "mix.lock"))

    for project <- ["pramana", "foundry"], file <- ["mix.exs", "mix.lock", "config/config.exs"] do
      assert File.regular?(Path.join([@root, project, file]))
    end

    umbrella = File.read!(Path.join(@project, "mix.exs"))
    foundry = File.read!(Path.join(@root, "foundry/mix.exs"))
    assert umbrella =~ ~s(apps_path: "apps")
    refute foundry =~ "in_umbrella: true"
    refute foundry =~ "apps_path:"
    refute File.exists?(Path.join(@project, "apps/foundry"))
  end

  test "each Pramana child resolves its build configuration within its own product" do
    for app <- ~w(pramana pramana_web pramana_native) do
      child = Path.join([@project, "apps", app])
      text = File.read!(Path.join(child, "mix.exs"))

      for {key, relative} <- [
            {"build_path", "../../_build"},
            {"deps_path", "../../deps"},
            {"config_path", "../../config/config.exs"},
            {"lockfile", "../../mix.lock"}
          ] do
        assert text =~ ~s(#{key}: "#{relative}")
        resolved = Path.expand(relative, child)

        assert Path.dirname(resolved) == @project or
                 resolved == Path.join(@project, "config/config.exs")
      end
    end
  end

  test "source inputs and companion manifests remain under the product root" do
    for file <- [
          "sources.lock.json",
          "evals/baseline.json",
          "apps/pramana_native/native/pramana_native/Cargo.toml",
          "apps/pramana_native/native/pramana_native/Cargo.lock",
          "native/quotations/Cargo.toml",
          "native/quotations/Cargo.lock"
        ] do
      assert File.regular?(Path.join(@project, file))
    end

    assert Path.wildcard(Path.join(@project, "evals/gold/*.jsonl")) != []
    assert Path.wildcard(Path.join(@project, "priv/embed/*.py")) != []
  end

  test "figure discovery covers project status and the shared plan without scanning arbitrary parents" do
    paths = Pramana.Docs.Sync.documents([@project, @root])
    assert Path.join(@project, "docs/STATUS.md") in paths
    assert Path.join(@root, "docs/PLAN.md") in paths
    assert length(paths) == length(Enum.uniq(paths))
    refute Path.join(@root, "docs/PLAN.md") in Pramana.Docs.Sync.documents(@project)
    assert Pramana.Docs.Sync.documents([@project, @root, @project]) == paths
  end

  test "Git root stays the same from either product directory, including a worktree" do
    for dir <- [@root, @project, Path.join(@root, "foundry")] do
      {out, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"], cd: dir)
      assert String.trim(out) == @root
    end
  end

  test "umbrella test entry prepares the database before recursive application startup" do
    text = File.read!(Path.join(@project, "mix.exs"))
    ast = Code.string_to_quoted!(text)

    {_ast, test_aliases} =
      Macro.prewalk(ast, [], fn
        {:test, ["ecto.create --quiet", "ecto.migrate --quiet", "test"]} = node, found ->
          {node, [node | found]}

        node, found ->
          {node, found}
      end)

    assert length(test_aliases) == 1
    assert text =~ "preferred_envs: [test: :test"
  end

  test "CI uses product working directories and independently addressed native manifests" do
    ci = File.read!(Path.join(@root, ".github/workflows/ci.yml"))
    assert ci =~ "working-directory: pramana"
    assert ci =~ "pramana/deps"
    assert ci =~ "pramana/_build"
    assert ci =~ "cargo audit --file native/quotations/Cargo.lock"
    assert ci =~ "cargo audit --file apps/pramana_native/native/pramana_native/Cargo.lock"
    foundry = File.read!(Path.join(@root, ".github/workflows/foundry-ci.yml"))
    assert foundry =~ "working-directory: foundry"
    assert foundry =~ "elixir ci/run.exs"
  end
end
