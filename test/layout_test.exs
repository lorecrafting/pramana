defmodule Repository.LayoutTest do
  @moduledoc "Model-free regression checks for the repository layout."
  use ExUnit.Case, async: true

  alias Pramana.Docs.Sync

  @root Path.expand("..", __DIR__)

  test "the repository root is one Pramāṇa Mix app and Foundry has moved out" do
    for file <- ["mix.exs", "mix.lock", "config/config.exs"] do
      assert File.regular?(Path.join(@root, file))
    end

    project = File.read!(Path.join(@root, "mix.exs"))
    assert project =~ "app: :pramana"
    refute project =~ "apps_path:"

    for dir <- ["foundry", "pramana"] do
      assert {"", 0} == System.cmd("git", ["ls-files", "--", dir], cd: @root)
    end

    assert {"", 0} == System.cmd("git", ["ls-files", "--", "apps"], cd: @root)
  end

  test "source inputs and companion manifests remain under the product root" do
    for file <- [
          "sources.lock.json",
          "evals/baseline.json",
          "native/pramana_native/Cargo.toml",
          "native/pramana_native/Cargo.lock",
          "native/quotations/Cargo.toml",
          "native/quotations/Cargo.lock"
        ] do
      assert File.regular?(Path.join(@root, file))
    end

    assert Path.wildcard(Path.join(@root, "evals/gold/*.jsonl")) != []
    assert Path.wildcard(Path.join(@root, "priv/embed/*.py")) != []
  end

  test "figure discovery covers status and the plan without scanning arbitrary parents" do
    paths = Sync.documents(@root)
    assert Path.join(@root, "docs/STATUS.md") in paths
    assert Path.join(@root, "docs/PLAN.md") in paths
    assert Sync.documents([@root, @root]) == paths
    assert Sync.documents(Path.join(@root, "lib")) == []
  end

  test "Git root stays the same from a source directory" do
    for dir <- [@root, Path.join(@root, "lib/pramana")] do
      {out, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"], cd: dir)
      assert String.trim(out) == @root
    end
  end

  test "test entry prepares the database before application startup" do
    text = File.read!(Path.join(@root, "mix.exs"))
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

  test "CI runs at the repository root with independently addressed native manifests" do
    ci = File.read!(Path.join(@root, ".github/workflows/ci.yml"))
    refute ci =~ "working-directory: pramana"
    assert ci =~ "\n            deps\n            _build\n"
    assert ci =~ "cargo audit --file native/quotations/Cargo.lock"
    assert ci =~ "cargo audit --file native/pramana_native/Cargo.lock"
    refute File.exists?(Path.join(@root, ".github/workflows/foundry-ci.yml"))
  end

  test "heavy CI is path-scoped and reusable caches do not replace exact candidate builds" do
    ci = File.read!(Path.join(@root, ".github/workflows/ci.yml"))
    container = File.read!(Path.join(@root, ".github/workflows/pramana-container.yml"))
    postgres = File.read!(Path.join(@root, "ci/postgres.Dockerfile"))

    assert ci =~ ~s(- "**")
    assert ci =~ ~s(- "!docs/**")
    assert ci =~ ~s(- "!**/*.md")
    refute ci =~ "services:\n      postgres:"
    refute ci =~ "Install pg_bigm"
    assert ci =~ "file: ci/postgres.Dockerfile"
    assert ci =~ "Build cached PostgreSQL fixture (PR restore only)"
    assert ci =~ "Build cached PostgreSQL fixture (trusted cache writer)"
    assert ci =~ "cache-from: type=gha,scope=pramana-postgres-pg18-pgbigm"

    assert length(
             Regex.scan(~r/cache-to: type=gha,mode=max,scope=pramana-postgres-pg18-pgbigm/, ci)
           ) == 1

    assert ci =~ "pull: true"
    assert ci =~ "mix compile --force --warnings-as-errors"
    assert ci =~ "run: mix test --cover"
    assert ci =~ "mix release --overwrite"

    refute container =~ ~s(- "**")
    assert container =~ ~s(- "lib/**")
    assert container =~ ~s(- "native/pramana_native/**")
    assert container =~ ~s(- "ci/release_smoke.py")
    assert container =~ ~s(- "ci/serving_privileges.exs")
    refute container =~ ~s(- "ci/**")
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
    assert postgres =~ "sha256:2ba9ca5f2e7daa0f0e7723cba1ee9167bab54efd3640516a44ac1a928dd67e7a"
    assert postgres =~ "COPY --from=builder"
  end
end
