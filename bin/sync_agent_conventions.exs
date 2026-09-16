defmodule Pramana.AgentConventionSync do
  @moduledoc false

  @root Path.expand("..", __DIR__)
  @conventions_dir Path.join(@root, "docs/agents/code-conventions")
  @manifest_path Path.join(@conventions_dir, "UPSTREAM.exs")
  @lock_path Path.join(@root, "pramana/mix.lock")
  @raw_base "https://raw.githubusercontent.com/phoenixframework/phoenix"

  def main(args) do
    manifest = load_manifest!()
    locked = locked_phoenix_version!()

    case args do
      ["--check"] -> check!(manifest, locked)
      ["--review"] -> review(manifest, locked)
      ["--watch-main"] -> watch_main(manifest)
      ["--help"] -> usage(0)
      [] -> usage(1)
      _ -> usage(1)
    end
  end

  defp load_manifest! do
    {manifest, _binding} = Code.eval_file(@manifest_path)

    unless is_map(manifest) do
      abort("Expected #{@manifest_path} to evaluate to a map.")
    end

    manifest
  end

  defp locked_phoenix_version! do
    lock = File.read!(@lock_path)

    case Regex.run(~r/"phoenix":\s+\{:hex,\s+:phoenix,\s+"([^"]+)"/, lock) do
      [_, version] -> version
      _ -> abort("Could not find the locked :phoenix Hex version in #{@lock_path}.")
    end
  end

  defp check!(manifest, locked) do
    expected_tag = "v#{locked}"

    errors =
      []
      |> add_if(
        manifest.phoenix_version != locked,
        "Locked Phoenix is #{locked}, but conventions were reviewed for #{manifest.phoenix_version}."
      )
      |> add_if(
        manifest.source_tag != expected_tag,
        "Expected source_tag #{expected_tag}, found #{inspect(manifest.source_tag)}."
      )
      |> add_missing_files(manifest.local_files)
      |> add_if(
        map_size(manifest.versioned_sources) == 0,
        "No versioned Phoenix upstream sources are recorded."
      )
      |> add_if(
        map_size(manifest.main_watch.sources) == 0,
        "No Phoenix main watcher sources are recorded."
      )

    if errors == [] do
      IO.puts(
        "Agent conventions match locked Phoenix #{locked}; reviewed #{manifest.reviewed_at}."
      )
    else
      IO.puts(:stderr, "Agent convention metadata is stale or incomplete:")

      Enum.each(Enum.reverse(errors), fn error ->
        IO.puts(:stderr, "  - #{error}")
      end)

      IO.puts(
        :stderr,
        "\nAfter an intentional Phoenix upgrade, run:\n" <>
          "  elixir bin/sync_agent_conventions.exs --review"
      )

      System.halt(1)
    end
  end

  defp review(manifest, locked) do
    ensure_curl!()
    tag = "v#{locked}"

    IO.puts("Reviewing Phoenix #{tag} usage rules against the recorded convention baseline.")
    IO.puts("This command never overwrites local convention files.\n")

    {changes, fetch_errors} =
      compare_sources(tag, manifest.versioned_sources)

    if manifest.phoenix_version != locked do
      IO.puts(
        "LOCK DRIFT: reviewed Phoenix #{manifest.phoenix_version} -> locked Phoenix #{locked}"
      )
    end

    report_changes(changes)
    report_fetch_errors(fetch_errors)

    cond do
      fetch_errors != [] ->
        System.halt(1)

      manifest.phoenix_version != locked or changes != [] ->
        IO.puts(
          "\nSemantic review required. Update local convention files as appropriate, then " <>
            "advance UPSTREAM.exs deliberately."
        )

        System.halt(2)

      true ->
        IO.puts("\nNo upstream drift for the locked Phoenix version.")
    end
  end

  defp watch_main(manifest) do
    ensure_curl!()
    IO.puts("Checking Phoenix main usage rules against the reviewed early-warning baseline.\n")

    {changes, fetch_errors} =
      compare_sources("main", manifest.main_watch.sources)

    report_changes(changes)
    report_fetch_errors(fetch_errors)

    cond do
      fetch_errors != [] ->
        System.halt(1)

      changes != [] ->
        IO.puts(
          "\nPhoenix main changed. Treat this as a review signal only; do not auto-adopt " <>
            "main into the locked project conventions."
        )

        System.halt(2)

      true ->
        IO.puts("Phoenix main agent guidance is unchanged from the reviewed baseline.")
    end
  end

  defp compare_sources(ref, sources) do
    Enum.reduce(Enum.sort(sources), {[], []}, fn {path, expected_sha}, {changes, errors} ->
      case fetch(ref, path) do
        {:ok, body} ->
          actual_sha = git_blob_sha(body)

          if actual_sha == expected_sha do
            {changes, errors}
          else
            {[{path, expected_sha, actual_sha} | changes], errors}
          end

        {:error, reason} ->
          {changes, [{path, reason} | errors]}
      end
    end)
    |> then(fn {changes, errors} ->
      {Enum.reverse(changes), Enum.reverse(errors)}
    end)
  end

  defp fetch(ref, path) do
    url = "#{@raw_base}/#{ref}/#{path}"

    case System.cmd(
           "curl",
           ["--fail", "--silent", "--show-error", "--location", url],
           stderr_to_stdout: true
         ) do
      {body, 0} -> {:ok, body}
      {message, status} -> {:error, "curl exit #{status}: #{String.trim(message)}"}
    end
  end

  defp git_blob_sha(body) do
    :crypto.hash(:sha, ["blob ", Integer.to_string(byte_size(body)), <<0>>, body])
    |> Base.encode16(case: :lower)
  end

  defp report_changes([]), do: IO.puts("No source blob changes detected.")

  defp report_changes(changes) do
    IO.puts("Changed upstream source blobs:")

    Enum.each(changes, fn {path, recorded_sha, current_sha} ->
      IO.puts("  - #{path}")
      IO.puts("      recorded: #{recorded_sha}")
      IO.puts("      current:  #{current_sha}")
    end)
  end

  defp report_fetch_errors([]), do: :ok

  defp report_fetch_errors(errors) do
    IO.puts(:stderr, "\nUnable to fetch upstream sources:")

    Enum.each(errors, fn {path, reason} ->
      IO.puts(:stderr, "  - #{path}: #{reason}")
    end)
  end

  defp add_missing_files(errors, local_files) do
    Enum.reduce(local_files, errors, fn relative, acc ->
      path = Path.join(@conventions_dir, relative)
      add_if(acc, not File.regular?(path), "Missing convention file #{relative}.")
    end)
  end

  defp add_if(errors, true, message), do: [message | errors]
  defp add_if(errors, false, _message), do: errors

  defp ensure_curl! do
    unless System.find_executable("curl") do
      abort("curl is required for --review and --watch-main; --check is network-free.")
    end
  end

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end

  defp usage(status) do
    IO.puts("""
    Usage:
      elixir bin/sync_agent_conventions.exs --check
      elixir bin/sync_agent_conventions.exs --review
      elixir bin/sync_agent_conventions.exs --watch-main

    --check       Network-free CI guard: locked Phoenix version must match reviewed metadata.
    --review      Compare the locked Phoenix tag with reviewed upstream blobs; never overwrites.
    --watch-main  Compare Phoenix main with the early-warning baseline; exit 2 on drift.
    """)

    System.halt(status)
  end
end

Pramana.AgentConventionSync.main(System.argv())
