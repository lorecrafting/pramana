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

  test "Git root stays the same from either product directory" do
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

  test "heavy CI is path-scoped and reusable caches do not replace exact candidate builds" do
    ci = File.read!(Path.join(@root, ".github/workflows/ci.yml"))
    container = File.read!(Path.join(@root, ".github/workflows/pramana-container.yml"))
    postgres = File.read!(Path.join(@project, "ci/postgres.Dockerfile"))

    assert ci =~ ~s(- "pramana/**")
    assert ci =~ ~s(- "!pramana/docs/**")
    assert ci =~ ~s(- "test/**")
    assert ci =~ ~s(- "bin/**")
    refute ci =~ "services:\n      postgres:"
    refute ci =~ "Install pg_bigm"
    assert ci =~ "pramana/ci/postgres.Dockerfile"
    assert ci =~ "Build cached PostgreSQL fixture (PR restore only)"
    assert ci =~ "Build cached PostgreSQL fixture (trusted cache writer)"
    assert ci =~ "cache-from: type=gha,scope=pramana-postgres-pg18-pgbigm"

    assert length(
             Regex.scan(~r/cache-to: type=gha,mode=max,scope=pramana-postgres-pg18-pgbigm/, ci)
           ) == 1

    assert ci =~ "pull: true"
    assert ci =~ "mix compile --force --warnings-as-errors"
    assert ci =~ "mix test"
    assert ci =~ "mix release --overwrite"

    refute container =~ ~s(- "pramana/**")
    assert container =~ ~s(- "pramana/apps/**")
    assert container =~ ~s(- "pramana/ci/release_smoke.py")
    assert container =~ ~s(- "pramana/ci/serving_privileges.exs")
    refute container =~ ~s(- "pramana/ci/**")
    assert container =~ "Build exact Pramana runtime image (PR restore only)"
    assert container =~ "Build exact Pramana runtime image (trusted cache writer)"
    assert container =~ "cache-from: type=gha,scope=pramana-runtime-image"

    assert length(
             Regex.scan(~r/cache-to: type=gha,mode=max,scope=pramana-runtime-image/, container)
           ) == 1

    assert container =~ "pull: true"
    assert container =~ "load: true"
    assert container =~ "release_smoke.py"

    assert postgres =~ "735dceba0ecdd8ac1aaaaa207226a7102b6bbd71"
    assert postgres =~ "COPY --from=builder"
  end
end
