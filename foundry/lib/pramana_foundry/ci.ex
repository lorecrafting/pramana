defmodule PramanaFoundry.CI do
  @moduledoc """
  Isolated, provider-free Foundry continuous-integration runner.

  The runner establishes and records provenance before compilation, rejects dirty source
  and non-Hex dependencies, and atomically updates one manifest through every stage.
  """

  @schema "pramana-foundry-ci-provenance/v2"
  @excluded_tags ~w(live_provider real_provider python_tiktoken_recompute)
  @error_exit 70

  @spec main([String.t()]) :: non_neg_integer()
  def main(args) do
    root = project_root()
    {output_dir, valid_args?} = output_target(args)

    case File.mkdir_p(output_dir) do
      :ok ->
        execute(root, output_dir, valid_args?)

      {:error, reason} ->
        IO.puts(:stderr, "cannot create provenance output #{output_dir}: #{inspect(reason)}")
        @error_exit
    end
  end

  @spec plan(Path.t(), Path.t()) :: [map()]
  def plan(root, run_root) do
    formatted_paths = formatted_paths(root)

    [
      %{name: "locked dependencies", argv: ["mix", "deps.get", "--check-locked"]},
      %{
        name: "warnings-as-errors compile",
        argv: ["mix", "compile", "--force", "--warnings-as-errors"]
      },
      %{
        name: "format outside pinned baseline debt",
        argv: ["mix", "format", "--check-formatted" | formatted_paths]
      },
      %{
        name: "model-free test suite",
        argv:
          ["mix", "test"] ++ Enum.flat_map(@excluded_tags, &["--exclude", &1]) ++ ["--seed", "0"]
      },
      %{name: "dependency inventory", argv: ["mix", "deps"]},
      %{
        name: "escript build",
        argv: ["mix", "escript.build", "--force"],
        artifact: Path.join(run_root, "artifacts/pramana_foundry")
      }
    ]
  end

  @spec create_run_root(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def create_run_root(parent \\ System.tmp_dir!()) do
    suffix = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    root = Path.join(parent, "pramana-foundry-ci-#{suffix}")

    case File.mkdir(root) do
      :ok -> {:ok, root}
      {:error, :eexist} -> create_run_root(parent)
      {:error, reason} -> {:error, {:create_run_root, root, reason}}
    end
  end

  @spec environment(Path.t()) :: [{String.t(), String.t() | nil}]
  def environment(run_root) do
    [
      {"MIX_ENV", "test"},
      {"MIX_BUILD_PATH", Path.join(run_root, "build")},
      {"MIX_DEPS_PATH", Path.join(run_root, "deps")},
      {"TMPDIR", Path.join(run_root, "tmp")},
      {"PRAMANA_OPERATOR_RUNTIME_ROOT", Path.join(run_root, "operator")},
      {"PRAMANA_RUNTIME_ROOT", nil},
      {"PRAMANA_RUNTIME_ROOT_FRESH", "1"},
      {"COORDINATOR_TICK", nil},
      {"HERDR_ENV", nil}
    ]
  end

  @spec exclusions(Path.t()) :: [map()]
  def exclusions(root) do
    counts = excluded_tag_counts(root)

    [
      %{
        id: "real-provider",
        status: "absent",
        test_tags: ["live_provider", "real_provider"],
        declared_test_matches: counts["live_provider"] + counts["real_provider"],
        reason: "FR-09/FR-15a/FR-22 require a separately authorized bounded profile"
      },
      %{
        id: "python-tiktoken-recomputation",
        status: "excluded",
        test_tags: ["python_tiktoken_recompute"],
        declared_test_matches: counts["python_tiktoken_recompute"],
        reason:
          "recorded measurement is checked in Elixir; optional recomputation has external inputs"
      },
      %{
        id: "live-daemon-and-activation",
        status: "absent",
        test_tags: [],
        declared_test_matches: 0,
        reason: "FR-17/FR-22 own activation and live lifecycle acceptance"
      },
      %{
        id: "corpus-and-services",
        status: "not-required",
        test_tags: [],
        declared_test_matches: 0,
        reason: "Foundry is standalone and this job starts no database or corpus service"
      }
    ]
  end

  @spec validate_source(map()) :: :ok | {:error, term()}
  def validate_source(%{available: true, dirty_paths: []}), do: :ok

  def validate_source(%{available: true, dirty_paths: paths}),
    do: {:error, {:dirty_source, paths}}

  def validate_source(source), do: {:error, {:source_unavailable, source[:error]}}

  @spec validate_toolchain(map(), map()) :: :ok | {:error, term()}
  def validate_toolchain(actual, expected) do
    mismatches =
      ~w(elixir otp erts)a
      |> Enum.reject(&(Map.get(actual, &1) == Map.get(expected, &1)))

    if mismatches == [], do: :ok, else: {:error, {:toolchain_mismatch, mismatches}}
  end

  @spec validate_dependency_inventory(map()) :: :ok | {:error, term()}
  def validate_dependency_inventory(inventory) do
    invalid =
      Enum.reject(inventory.resolved, fn dependency ->
        dependency.scm == "Hex.SCM" and dependency.lock_kind == "hex" and
          dependency.lock_matches and dependency.destination_isolated
      end)

    cond do
      inventory.tracked_dependency_sources != [] ->
        {:error, {:tracked_dependency_sources, inventory.tracked_dependency_sources}}

      inventory.prebuilt_escript_tracked ->
        {:error, :tracked_prebuilt_escript}

      invalid != [] ->
        {:error, {:prohibited_dependencies, invalid}}

      true ->
        :ok
    end
  end

  @doc false
  def command_probe(argv, root, run_root) do
    command_receipt(%{name: "probe", argv: argv}, root, environment(run_root), run_root)
  end

  defp execute(root, output_dir, valid_args?) do
    manifest = skeleton(root)

    with :ok <- initial_manifest(output_dir, manifest),
         :ok <- require_stage(valid_args?, :arguments, :invalid_arguments),
         :ok <-
           require_stage(File.regular?(Path.join(root, "mix.exs")), :project, :missing_mix_exs),
         :ok <- require_stage(validate_source(manifest.source), :source_preflight),
         :ok <-
           require_stage(
             validate_toolchain(manifest.toolchain.actual, manifest.toolchain.expected),
             :toolchain
           ),
         :ok <- require_stage(manifest.dependencies, :lockfile),
         :ok <-
           require_stage(
             validate_dependency_inventory(manifest.dependencies),
             :dependency_preflight
           ),
         {:ok, run_root} <- create_run_root(),
         env = environment(run_root),
         :ok <- prepare_directories(env, run_root) do
      manifest =
        manifest
        |> Map.put(:isolation, isolation_provenance(env, run_root))
        |> add_stage(:setup, "passed")

      :ok = atomic_manifest(output_dir, manifest)
      run_commands(manifest, root, run_root, output_dir, env)
    else
      {:manifest_transport_error, reason} ->
        manifest_transport_failure(output_dir, reason)

      {:stage_error, stage, reason} ->
        fail_manifest(manifest, output_dir, stage, reason, 2)

      {:error, {:create_run_root, _path, _reason} = reason} ->
        fail_manifest(manifest, output_dir, :isolation, reason, 2)

      {:error, reason} ->
        fail_manifest(manifest, output_dir, :setup, reason, 2)
    end
  rescue
    error ->
      fail_manifest(
        skeleton(root),
        output_dir,
        :setup_exception,
        Exception.message(error),
        @error_exit
      )
  catch
    kind, reason ->
      fail_manifest(skeleton(root), output_dir, :setup_throw, {kind, reason}, @error_exit)
  end

  defp run_commands(manifest, root, run_root, output_dir, env) do
    [deps_get | remaining] = plan(root, run_root)
    {manifest, receipt} = execute_command(manifest, deps_get, root, env, run_root)
    :ok = atomic_manifest(output_dir, manifest)

    if receipt.status != "passed" do
      finish_failed(manifest, output_dir, receipt_exit(receipt))
    else
      with {:ok, resolved} <- resolved_dependencies(root, env, run_root) do
        inventory = Map.put(manifest.dependencies, :resolved, resolved)

        case validate_dependency_inventory(inventory) do
          :ok ->
            manifest =
              manifest
              |> Map.put(:dependencies, inventory)
              |> add_stage(:resolved_dependency_policy, "passed")

            :ok = atomic_manifest(output_dir, manifest)
            run_remaining(manifest, remaining, root, run_root, output_dir, env)

          {:error, reason} ->
            fail_manifest(
              Map.put(manifest, :dependencies, inventory),
              output_dir,
              :resolved_dependency_policy,
              reason,
              2
            )
        end
      else
        {:error, reason} ->
          fail_manifest(manifest, output_dir, :resolved_dependency_inspection, reason, 2)
      end
    end
  end

  defp run_remaining(manifest, commands, root, run_root, output_dir, env) do
    Enum.reduce_while(commands, {:continue, manifest}, fn command, {:continue, current} ->
      {next, receipt} = execute_command(current, command, root, env, run_root)
      :ok = atomic_manifest(output_dir, next)

      if receipt.status == "passed" do
        {:cont, {:continue, next}}
      else
        {:halt, {:failed, next, receipt_exit(receipt)}}
      end
    end)
    |> case do
      {:failed, failed, exit_code} ->
        finish_failed(failed, output_dir, exit_code)

      {:continue, completed} ->
        post_source = source_provenance(root)

        case validate_post_source(completed.source, post_source) do
          :ok ->
            completed
            |> Map.put(:post_source, post_source)
            |> Map.put(:artifact, artifact_provenance(run_root, output_dir, root))
            |> Map.put(:result, "passed")
            |> Map.put(:exit_code, 0)
            |> Map.put(:finished_at, timestamp())
            |> add_stage(:source_postflight, "passed")
            |> then(fn final ->
              :ok = atomic_manifest(output_dir, final)
              IO.puts("Foundry CI provenance: #{manifest_path(output_dir)}")
              0
            end)

          {:error, reason} ->
            completed
            |> Map.put(:post_source, post_source)
            |> fail_manifest(output_dir, :source_postflight, reason, 2)
        end
    end
  end

  defp execute_command(manifest, command, root, env, run_root) do
    receipt = command_receipt(command, root, env, run_root)

    updated =
      manifest
      |> Map.put(:stage, "command:#{command.name}")
      |> Map.update!(:commands, &(&1 ++ [receipt]))

    {updated, receipt}
  end

  defp command_receipt(%{argv: [executable | args]} = command, root, env, run_root) do
    started = System.monotonic_time(:millisecond)

    try do
      {output, exit_code} =
        System.cmd(executable, args, cd: root, env: env, stderr_to_stdout: true)

      IO.write(output)

      if exit_code == 0 and command[:artifact] do
        source = Path.join(root, "pramana_foundry")
        File.mkdir_p!(Path.dirname(command.artifact))
        File.cp!(source, command.artifact)
      end

      %{
        name: command.name,
        argv: [executable | args],
        status: if(exit_code == 0, do: "passed", else: "failed"),
        exit_code: exit_code,
        error: nil,
        duration_ms: System.monotonic_time(:millisecond) - started,
        output_sha256: sha256(output),
        environment: command_environment(run_root)
      }
    rescue
      error ->
        %{
          name: command.name,
          argv: [executable | args],
          status: "spawn_or_stage_failed",
          exit_code: nil,
          error: Exception.message(error),
          duration_ms: System.monotonic_time(:millisecond) - started,
          output_sha256: sha256(""),
          environment: command_environment(run_root)
        }
    after
      if command[:artifact], do: File.rm(Path.join(root, "pramana_foundry"))
    end
  end

  defp skeleton(root) do
    source = source_provenance(root)
    expected = expected_toolchain(root)
    actual = actual_toolchain()

    %{
      schema: @schema,
      started_at: timestamp(),
      finished_at: nil,
      result: "running",
      exit_code: nil,
      stage: "bootstrap",
      stages: [],
      commands: [],
      source: source,
      post_source: nil,
      toolchain: %{
        expected: expected,
        actual: actual,
        matches_policy: validate_toolchain(actual, expected) == :ok
      },
      dependencies: dependency_skeleton(root),
      isolation: %{status: "not-established"},
      exclusions: exclusions(root),
      format_debt: safe_value(fn -> verify_format_debt(root, load_format_debt!(root)) end),
      artifact: %{kind: "escript", status: "not-built"}
    }
  end

  defp dependency_skeleton(root) do
    lock = safe_value(fn -> read_lock(root) end)
    tracked = git_lines(root, ["ls-files", "deps"])
    escript = git_lines(root, ["ls-files", "pramana_foundry"])

    %{
      policy:
        "all resolved dependencies must be locked Hex sources in the isolated dependency root",
      lockfile: %{
        path: "mix.lock",
        sha256: safe_value(fn -> file_sha(root, "mix.lock") end),
        packages: lock_packages(lock)
      },
      tracked_dependency_sources: value_or_empty(tracked),
      prebuilt_escript_tracked: value_or_empty(escript) != [],
      resolved: []
    }
  end

  defp resolved_dependencies(root, env, run_root) do
    with_process_environment(env, fn ->
      File.cd!(root, fn ->
        Mix.start()
        Mix.Dep.clear_cached()

        Mix.Project.in_project(:pramana_foundry, root, [env: :test], fn _module ->
          lock = Mix.Dep.Lock.read()

          Mix.Dep.load_and_cache()
          |> Enum.map(fn dependency ->
            dep_lock = Keyword.get(dependency.opts, :lock)
            destination = Keyword.get(dependency.opts, :dest, "")

            %{
              name: Atom.to_string(dependency.app),
              requirement: inspect(dependency.requirement),
              scm: inspect(dependency.scm),
              status: inspect(dependency.status),
              lock_kind: lock_kind(dep_lock),
              lock_matches: not is_nil(dep_lock) and dep_lock == Map.get(lock, dependency.app),
              destination: destination,
              destination_isolated: within?(destination, Path.join(run_root, "deps"))
            }
          end)
        end)
      end)
    end)
    |> case do
      {:error, _reason} = error -> error
      dependencies when is_list(dependencies) -> {:ok, dependencies}
      other -> {:error, {:unexpected_dependency_inventory, other}}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp read_lock(root) do
    File.cd!(root, fn ->
      Mix.start()
      Mix.Dep.Lock.read()
    end)
  end

  defp lock_packages(%{error: _reason} = error), do: error

  defp lock_packages(lock) when is_map(lock) do
    Map.new(lock, fn {name, entry} ->
      case entry do
        {:hex, package, version, checksum, _managers, _dependencies, repo, outer_checksum} ->
          {Atom.to_string(name),
           %{
             kind: "hex",
             package: Atom.to_string(package),
             version: version,
             checksum: checksum,
             repo: repo,
             outer_checksum: outer_checksum
           }}

        other ->
          {Atom.to_string(name), %{kind: lock_kind(other), value: inspect(other)}}
      end
    end)
  end

  defp lock_packages(error), do: %{error: error}

  defp lock_kind(lock) when is_tuple(lock) and tuple_size(lock) > 0,
    do: lock |> elem(0) |> Atom.to_string()

  defp lock_kind(_lock), do: "unlocked"

  defp source_provenance(root) do
    status = git_raw(root, ["status", "--porcelain=v1", "--untracked-files=all"])

    case status do
      {:ok, dirty} ->
        %{
          available: true,
          commit: git_value(root, ["rev-parse", "HEAD"]),
          tree: git_value(root, ["rev-parse", "HEAD^{tree}"]),
          dirty_paths: String.split(dirty, "\n", trim: true),
          dirty_status_sha256: sha256(dirty),
          runner_sha256: safe_value(fn -> file_sha(root, "lib/pramana_foundry/ci.ex") end),
          workflow_sha256:
            safe_value(fn -> file_sha(root, "../.github/workflows/foundry-ci.yml") end)
        }

      {:error, reason} ->
        %{available: false, error: reason, dirty_paths: []}
    end
  end

  defp expected_toolchain(root) do
    safe_value(fn ->
      {policy, _binding} = Code.eval_file(Path.join(root, "ci/toolchain.exs"))
      Map.take(policy, ~w(elixir otp erts)a)
    end)
  end

  defp actual_toolchain do
    %{
      elixir: System.version(),
      otp: safe_value(&exact_otp_version/0),
      erts: :erlang.system_info(:version) |> List.to_string(),
      emulator: :erlang.system_info(:system_version) |> List.to_string() |> String.trim()
    }
  end

  defp exact_otp_version do
    Path.join([to_string(:code.root_dir()), "releases", System.otp_release(), "OTP_VERSION"])
    |> File.read!()
    |> String.trim()
  end

  defp validate_post_source(initial, final) do
    with :ok <- validate_source(final),
         true <- initial.commit == final.commit || {:error, :commit_changed},
         true <- initial.tree == final.tree || {:error, :tree_changed} do
      :ok
    else
      {:error, _reason} = error -> error
    end
  end

  defp excluded_tag_counts(root) do
    test_sources =
      root
      |> Path.join("test")
      |> Path.join("**/*.{ex,exs}")
      |> Path.wildcard()
      |> Enum.map(&File.read!/1)

    Map.new(@excluded_tags, fn tag ->
      pattern = ~r/@(?:module)?tag\s+:#{Regex.escape(tag)}\b/
      {tag, Enum.sum(Enum.map(test_sources, &length(Regex.scan(pattern, &1))))}
    end)
  end

  defp formatted_paths(root) do
    debt_paths = load_format_debt!(root) |> MapSet.new(& &1.path)

    root
    |> formatter_paths()
    |> Enum.reject(&MapSet.member?(debt_paths, &1))
  end

  defp formatter_paths(root) do
    root
    |> git_value(["ls-files"])
    |> String.split("\n", trim: true)
    |> Enum.filter(fn path ->
      path in ["mix.exs", ".formatter.exs"] or
        (String.ends_with?(path, [".ex", ".exs"]) and
           Enum.any?(~w(config/ lib/ test/ ci/), &String.starts_with?(path, &1)))
    end)
    |> Enum.sort()
  end

  defp load_format_debt!(root) do
    {debt, _binding} = Code.eval_file(Path.join(root, "ci/format_debt.exs"))
    debt
  end

  defp verify_format_debt(root, debt) do
    entries =
      Enum.map(debt, fn %{path: path, sha256: expected} ->
        actual = root |> Path.join(path) |> File.read!() |> sha256()

        %{
          path: path,
          expected_sha256: expected,
          actual_sha256: actual,
          matched: actual == expected
        }
      end)

    unless Enum.all?(entries, & &1.matched), do: raise("format-debt baseline changed")
    entries
  end

  defp artifact_provenance(run_root, output_dir, root) do
    source = Path.join(run_root, "artifacts/pramana_foundry")

    if File.regular?(source) do
      destination = Path.join(output_dir, "pramana_foundry")
      File.cp!(source, destination)

      %{
        kind: "escript",
        path: "pramana_foundry",
        sha256: source |> File.read!() |> sha256(),
        source_commit: git_value(root, ["rev-parse", "HEAD"])
      }
    else
      %{kind: "escript", status: "not-built"}
    end
  end

  defp prepare_directories(env, run_root) do
    env
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.filter(fn {key, _value} -> key in ~w(MIX_BUILD_PATH MIX_DEPS_PATH TMPDIR) end)
    |> Enum.each(fn {_key, value} -> File.mkdir_p!(value) end)

    File.mkdir_p!(Path.join(run_root, "artifacts"))
  end

  defp dependency_error?(value), do: is_map(value) and Map.has_key?(value, :error)

  defp require_stage(true, _stage, _reason), do: :ok
  defp require_stage(false, stage, reason), do: {:stage_error, stage, reason}
  defp require_stage(:ok, _stage), do: :ok
  defp require_stage({:error, reason}, stage), do: {:stage_error, stage, reason}

  defp require_stage(%{lockfile: %{packages: packages}}, stage) do
    if dependency_error?(packages), do: {:stage_error, stage, packages}, else: :ok
  end

  defp add_stage(manifest, name, status, error \\ nil) do
    stage = %{
      name: Atom.to_string(name),
      status: status,
      error: encode_term(error),
      at: timestamp()
    }

    manifest |> Map.put(:stage, Atom.to_string(name)) |> Map.update!(:stages, &(&1 ++ [stage]))
  end

  defp fail_manifest(manifest, output_dir, stage, reason, exit_code) do
    final =
      manifest
      |> Map.put(:result, "failed")
      |> Map.put(:exit_code, exit_code)
      |> Map.put(:finished_at, timestamp())
      |> add_stage(stage, "failed", reason)

    case atomic_manifest(output_dir, final) do
      :ok ->
        IO.puts(:stderr, "Foundry CI failed at #{stage}: #{inspect(reason)}")
        exit_code

      {:error, transport_reason} ->
        manifest_transport_failure(output_dir, transport_reason)
    end
  end

  defp finish_failed(manifest, output_dir, exit_code) do
    final =
      manifest
      |> Map.put(:result, "failed")
      |> Map.put(:exit_code, exit_code)
      |> Map.put(:finished_at, timestamp())

    :ok = atomic_manifest(output_dir, final)
    exit_code
  end

  defp atomic_manifest(output_dir, manifest) do
    destination = manifest_path(output_dir)
    temporary = destination <> ".tmp-#{System.unique_integer([:positive, :monotonic])}"

    with :ok <- File.write(temporary, [:json.encode(json_value(manifest)), "\n"]),
         :ok <- File.rename(temporary, destination) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  defp initial_manifest(output_dir, manifest) do
    case atomic_manifest(output_dir, manifest) do
      :ok -> :ok
      {:error, reason} -> {:manifest_transport_error, reason}
    end
  end

  defp manifest_transport_failure(output_dir, reason) do
    IO.puts(
      :stderr,
      "cannot write provenance manifest #{manifest_path(output_dir)}: #{inspect(reason)}"
    )

    @error_exit
  end

  defp output_target(["--output", path]) when is_binary(path), do: {Path.expand(path), true}
  defp output_target([]), do: {Path.expand("ci-artifacts"), true}

  defp output_target(args) do
    path =
      case Enum.chunk_every(args, 2, 1, :discard) |> Enum.find(&match?(["--output", _], &1)) do
        ["--output", candidate] -> Path.expand(candidate)
        _ -> Path.expand("ci-artifacts")
      end

    {path, false}
  end

  defp project_root, do: Path.expand("../..", __DIR__)
  defp manifest_path(output_dir), do: Path.join(output_dir, "provenance.json")

  defp with_process_environment(env, function) do
    previous = Map.new(env, fn {key, _value} -> {key, System.get_env(key)} end)

    try do
      Enum.each(env, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      function.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end

  defp within?(path, parent) when is_binary(path) do
    expanded = Path.expand(path)
    parent = Path.expand(parent)
    expanded == parent or String.starts_with?(expanded, parent <> "/")
  end

  defp within?(_path, _parent), do: false

  defp command_environment(run_root) do
    %{
      mix_build_path: Path.join(run_root, "build"),
      mix_deps_path: Path.join(run_root, "deps"),
      tmpdir: Path.join(run_root, "tmp"),
      coordinator_tick: "unset",
      herdr_env: "unset"
    }
  end

  defp isolation_provenance(env, run_root) do
    %{
      status: "established",
      run_root: run_root,
      environment: Map.new(env, fn {key, value} -> {key, value || "<unset>"} end),
      provider_launch: "disabled",
      foreign_pane_cleanup: "not invoked"
    }
  end

  defp receipt_exit(%{exit_code: exit_code}) when is_integer(exit_code), do: exit_code
  defp receipt_exit(_receipt), do: @error_exit

  defp git_value(root, args) do
    case git_raw(root, args) do
      {:ok, output} -> String.trim(output)
      {:error, reason} -> %{error: reason}
    end
  end

  defp git_lines(root, args) do
    case git_raw(root, args) do
      {:ok, output} -> String.split(output, "\n", trim: true)
      {:error, reason} -> [%{error: reason}]
    end
  end

  defp git_raw(root, args) do
    try do
      case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, status} -> {:error, %{argv: ["git" | args], exit_code: status, output: output}}
      end
    rescue
      error -> {:error, %{argv: ["git" | args], spawn_error: Exception.message(error)}}
    end
  end

  defp safe_value(function) do
    function.()
  rescue
    error -> %{error: Exception.message(error)}
  catch
    kind, reason -> %{error: inspect({kind, reason})}
  end

  defp value_or_empty(value) when is_list(value), do: value
  defp value_or_empty(_value), do: []
  defp json_value(nil), do: :null

  defp json_value(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, json_value(item)} end)

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
  defp json_value(value), do: value
  defp encode_term(nil), do: nil
  defp encode_term(term) when is_binary(term) or is_number(term) or is_boolean(term), do: term
  defp encode_term(term), do: inspect(term)
  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp file_sha(root, path), do: root |> Path.join(path) |> File.read!() |> sha256()
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
