defmodule PramanaFoundry.CITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias PramanaFoundry.CI

  test "plan is Foundry-only and excludes provider-backed tests" do
    root = Path.expand("../..", __DIR__)
    run_root = Path.join(System.tmp_dir!(), "fr21-plan-only")
    plan = CI.plan(root, run_root)
    argvs = Enum.map(plan, & &1.argv)

    assert ["mix", "deps.get", "--check-locked"] in argvs
    assert Enum.any?(argvs, &(&1 == ["mix", "compile", "--force", "--warnings-as-errors"]))

    assert Enum.any?(argvs, fn argv ->
             argv
             |> Enum.chunk_every(2, 1, :discard)
             |> Enum.any?(&(&1 == ["--exclude", "live_provider"]))
           end)

    refute Enum.any?(argvs, fn
             ["mix", task | _args] ->
               String.starts_with?(task, "ecto.") or task == "pramana.gate"

             _ ->
               false
           end)

    refute Enum.any?(argvs, fn [executable | _args] ->
             executable in ["herdr", "python", "python3"]
           end)
  end

  test "each run receives exclusive paths and disables runtime/provider authority" do
    parent =
      Path.join(System.tmp_dir!(), "fr21-ci-contract-#{System.unique_integer([:positive])}")

    File.mkdir_p!(parent)
    on_exit(fn -> File.rm_rf!(parent) end)

    assert {:ok, first} = CI.create_run_root(parent)
    assert {:ok, second} = CI.create_run_root(parent)
    assert first != second
    assert File.dir?(first)
    assert File.dir?(second)

    environment = Map.new(CI.environment(first))
    assert environment["MIX_BUILD_PATH"] == Path.join(first, "build")
    assert environment["MIX_DEPS_PATH"] == Path.join(first, "deps")
    assert environment["TMPDIR"] == Path.join(first, "tmp")
    assert environment["PRAMANA_RUNTIME_ROOT"] == nil
    assert environment["COORDINATOR_TICK"] == nil
    assert environment["HERDR_ENV"] == nil
  end

  test "workflow uses immutable official action revisions and no corpus service" do
    workflow = File.read!(Path.expand("../../../.github/workflows/foundry-ci.yml", __DIR__))
    {toolchain, _binding} = Code.eval_file(Path.expand("../../ci/toolchain.exs", __DIR__))
    refs = Regex.scan(~r/uses:\s+[^@\s]+@([^\s]+)/, workflow, capture: :all_but_first)

    assert length(refs) == 3
    assert Enum.all?(refs, fn [revision] -> String.match?(revision, ~r/\A[0-9a-f]{40}\z/) end)
    assert workflow =~ "working-directory: foundry"
    assert workflow =~ ~s(otp-version: "#{toolchain.otp}")
    assert workflow =~ ~s(elixir-version: "#{toolchain.elixir_distribution}")
    refute workflow =~ "postgres"
    refute workflow =~ "services:"
  end

  test "exclusions publish missing live evidence instead of claiming it passed" do
    root = Path.expand("../..", __DIR__)
    exclusions = CI.exclusions(root)

    assert Enum.any?(exclusions, fn item ->
             item.id == "real-provider" and item.status == "absent" and
               item.declared_test_matches == 0
           end)

    assert Enum.any?(exclusions, fn item ->
             item.id == "python-tiktoken-recomputation" and item.status == "excluded" and
               item.declared_test_matches == 1
           end)

    assert Enum.any?(exclusions, fn item ->
             item.id == "live-daemon-and-activation" and item.status == "absent" and
               item.declared_test_matches == 0
           end)
  end

  test "dirty or unavailable source is rejected before work" do
    assert :ok = CI.validate_source(%{available: true, dirty_paths: []})

    assert {:error, {:dirty_source, ["?? lib/pramana_foundry/forged.ex"]}} =
             CI.validate_source(%{
               available: true,
               dirty_paths: ["?? lib/pramana_foundry/forged.ex"]
             })

    assert {:error, {:source_unavailable, :git_missing}} =
             CI.validate_source(%{available: false, error: :git_missing, dirty_paths: []})
  end

  test "exact Elixir OTP and ERTS versions must all match" do
    expected = %{elixir: "1.20.3", otp: "29.0.5", erts: "17.0.5"}
    assert :ok = CI.validate_toolchain(expected, expected)

    for key <- [:elixir, :otp, :erts] do
      wrong = Map.put(expected, key, "wrong")
      assert {:error, {:toolchain_mismatch, [^key]}} = CI.validate_toolchain(wrong, expected)
    end
  end

  test "dependency policy rejects path git unlocked nonisolated and tracked inputs" do
    valid = %{
      resolved: [
        %{
          name: "owl",
          scm: "Hex.SCM",
          lock_kind: "hex",
          lock_matches: true,
          destination_isolated: true
        }
      ],
      tracked_dependency_sources: [],
      prebuilt_escript_tracked: false
    }

    assert :ok = CI.validate_dependency_inventory(valid)

    for {field, value} <- [
          {:scm, "Mix.SCM.Path"},
          {:scm, "Mix.SCM.Git"},
          {:lock_kind, "unlocked"},
          {:lock_matches, false},
          {:destination_isolated, false}
        ] do
      [dependency] = valid.resolved
      invalid = %{valid | resolved: [Map.put(dependency, field, value)]}
      assert {:error, {:prohibited_dependencies, [_]}} = CI.validate_dependency_inventory(invalid)
    end

    assert {:error, {:tracked_dependency_sources, ["deps/owl/lib/owl.ex"]}} =
             valid
             |> Map.put(:tracked_dependency_sources, ["deps/owl/lib/owl.ex"])
             |> CI.validate_dependency_inventory()

    assert {:error, :tracked_prebuilt_escript} =
             valid
             |> Map.put(:prebuilt_escript_tracked, true)
             |> CI.validate_dependency_inventory()
  end

  test "invalid invocation still emits attributable skeletal provenance" do
    output =
      Path.join(System.tmp_dir!(), "fr21-invalid-args-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(output) end)
    assert 2 == CI.main(["--output", output, "--unexpected"])

    manifest = output |> Path.join("provenance.json") |> File.read!() |> :json.decode()
    assert manifest["result"] == "failed"
    assert manifest["exit_code"] == 2
    assert manifest["stage"] == "arguments"
    assert manifest["commands"] == []
    assert is_binary(manifest["source"]["commit"])
    assert is_binary(manifest["source"]["tree"])
    assert is_map(manifest["toolchain"])
    assert is_map(manifest["dependencies"]["lockfile"])
  end

  test "unreplaceable initial manifest reports transport failure once" do
    output =
      Path.join(
        System.tmp_dir!(),
        "fr21-unreplaceable-manifest-#{System.unique_integer([:positive])}"
      )

    destination = Path.join(output, "provenance.json")
    File.mkdir_p!(destination)
    on_exit(fn -> File.rm_rf!(output) end)

    stderr =
      capture_io(:stderr, fn ->
        assert 70 == CI.main(["--output", output])
      end)

    assert stderr =~ "cannot write provenance manifest #{destination}:"
    assert stderr =~ ":eisdir"
    assert length(String.split(stderr, "cannot write provenance manifest")) - 1 == 1
    assert File.dir?(destination)
  end

  test "command spawn failure has an explicit attributable receipt" do
    root = Path.expand("../..", __DIR__)
    run_root = Path.join(System.tmp_dir!(), "fr21-spawn-probe")
    missing = "fr21-command-that-does-not-exist"
    receipt = CI.command_probe([missing, "argument"], root, run_root)

    assert receipt.status == "spawn_or_stage_failed"
    assert receipt.exit_code == nil
    assert receipt.argv == [missing, "argument"]
    assert is_binary(receipt.error)
    assert receipt.output_sha256 == sha256("")
    assert receipt.environment.mix_build_path == Path.join(run_root, "build")
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
