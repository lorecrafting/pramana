defmodule Pramana.AgentConventionSync do
  @moduledoc false

  @root Path.expand("..", __DIR__)
  @conventions_dir Path.join(@root, "docs/agents/code-conventions")
  @manifest_path Path.join(@conventions_dir, "UPSTREAM.exs")
  @lock_path Path.join(@root, "pramana/mix.lock")
  @repo_api "https://api.github.com/repos/phoenixframework/phoenix"
  @contents_base "#{@repo_api}/contents"
  @commits_base "#{@repo_api}/commits"
  @http_marker "\n__PRAMANA_HTTP_STATUS__:"

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

    case manifest do
      %{
        phoenix_version: version,
        source_tag: tag,
        source_commit: source_commit,
        reviewed_at: reviewed_at,
        local_files: local_files,
        source_roots: source_roots,
        versioned_sources: versioned_sources,
        main_watch: %{
          reviewed_at: main_reviewed_at,
          source_commit: main_source_commit,
          sources: main_sources
        }
      }
      when is_binary(version) and is_binary(tag) and is_binary(source_commit) and
             is_binary(reviewed_at) and is_list(local_files) and is_list(source_roots) and
             is_map(versioned_sources) and is_binary(main_reviewed_at) and
             is_binary(main_source_commit) and is_map(main_sources) ->
        manifest

      _ ->
        abort("Expected #{@manifest_path} to contain the complete agent-convention manifest.")
    end
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
      |> add_sha_error("source_commit", manifest.source_commit)
      |> add_sha_error("main_watch.source_commit", manifest.main_watch.source_commit)
      |> add_date_error("reviewed_at", manifest.reviewed_at)
      |> add_date_error("main_watch.reviewed_at", manifest.main_watch.reviewed_at)
      |> add_root_errors(manifest.source_roots)
      |> add_local_file_errors(manifest.local_files)
      |> add_source_map_errors(
        "versioned_sources",
        manifest.versioned_sources,
        manifest.source_roots
      )
      |> add_source_map_errors(
        "main_watch.sources",
        manifest.main_watch.sources,
        manifest.source_roots
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

    {resolved_commit, diff, fetch_errors} =
      compare_sources(tag, manifest.source_roots, manifest.versioned_sources)

    lock_drift? = manifest.phoenix_version != locked
    tag_metadata_drift? = manifest.source_tag != tag
    tag_target_drift? = resolved_commit != nil and manifest.source_commit != resolved_commit

    if lock_drift? do
      IO.puts(
        "LOCK DRIFT: reviewed Phoenix #{manifest.phoenix_version} -> locked Phoenix #{locked}"
      )
    end

    if tag_metadata_drift? do
      IO.puts("TAG METADATA DRIFT: recorded #{manifest.source_tag} -> expected #{tag}")
    end

    if tag_target_drift? do
      IO.puts(
        "TAG TARGET DRIFT: recorded #{manifest.source_commit} -> current #{resolved_commit}"
      )
    end

    report_snapshot(manifest.source_commit, resolved_commit)
    report_diff(diff)
    report_fetch_errors(fetch_errors)

    cond do
      fetch_errors != [] ->
        System.halt(1)

      lock_drift? or tag_metadata_drift? or tag_target_drift? or diff?(diff) ->
        IO.puts(
          "\nSemantic review required. Review tag/version provenance, added/removed rule files " <>
            "and changed blobs; update local conventions as appropriate, then advance " <>
            "UPSTREAM.exs deliberately."
        )

        System.halt(2)

      true ->
        IO.puts("\nNo upstream drift for the locked Phoenix version.")
    end
  end

  defp watch_main(manifest) do
    ensure_curl!()
    IO.puts("Checking Phoenix main usage rules against the reviewed early-warning baseline.\n")

    {resolved_commit, diff, fetch_errors} =
      compare_sources("main", manifest.source_roots, manifest.main_watch.sources)

    report_snapshot(manifest.main_watch.source_commit, resolved_commit)
    report_diff(diff)
    report_fetch_errors(fetch_errors)

    cond do
      fetch_errors != [] ->
        System.halt(1)

      diff?(diff) ->
        IO.puts(
          "\nPhoenix main changed. Treat this as a review signal only; do not auto-adopt " <>
            "main into the locked project conventions."
        )

        System.halt(2)

      true ->
        IO.puts("Phoenix main agent guidance is unchanged from the reviewed baseline.")
    end
  end

  defp compare_sources(ref, roots, expected_sources) do
    case resolve_ref(ref) do
      {:ok, commit_sha} ->
        {actual_sources, errors} = fetch_inventory(commit_sha, roots)

        diff =
          if errors == [] do
            source_diff(expected_sources, actual_sources)
          else
            empty_diff()
          end

        {commit_sha, diff, errors}

      {:error, reason} ->
        {nil, empty_diff(), [{"ref #{ref}", reason}]}
    end
  end

  defp resolve_ref(ref) do
    url = "#{@commits_base}/#{URI.encode(ref)}"

    case http_get(url) do
      {:ok, 200, body} ->
        with {:ok, decoded} <- decode_json(body),
             %{"sha" => sha} when is_binary(sha) <- decoded,
             true <- valid_git_sha?(sha) do
          {:ok, sha}
        else
          false -> {:error, "GitHub returned an invalid commit SHA for #{ref}"}
          _ -> {:error, "GitHub commit response for #{ref} did not contain a SHA"}
        end

      {:ok, 404, _body} ->
        {:error, "GitHub ref #{ref} does not exist or is inaccessible"}

      {:ok, status, _body} ->
        {:error, "GitHub API HTTP #{status} while resolving #{ref}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_inventory(commit_sha, roots) do
    Enum.reduce(roots, {%{}, []}, fn root, {inventory, errors} ->
      case fetch_directory(commit_sha, root) do
        {:ok, entries} ->
          {Map.merge(inventory, entries), errors}

        {:error, reason} ->
          {inventory, [{root, reason} | errors]}
      end
    end)
    |> then(fn {inventory, errors} -> {inventory, Enum.reverse(errors)} end)
  end

  defp fetch_directory(commit_sha, path) do
    case fetch_contents(commit_sha, path) do
      {:ok, :missing} ->
        {:ok, %{}}

      {:ok, entries} when is_list(entries) ->
        Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, inventory} ->
          case entry do
            %{"type" => "dir", "path" => child} when is_binary(child) ->
              case fetch_directory(commit_sha, child) do
                {:ok, child_entries} ->
                  {:cont, {:ok, Map.merge(inventory, child_entries)}}

                {:error, reason} ->
                  {:halt, {:error, "#{child}: #{reason}"}}
              end

            %{"path" => child, "sha" => sha, "type" => type}
            when is_binary(child) and is_binary(sha) and is_binary(type) ->
              {:cont, {:ok, Map.put(inventory, child, sha)}}

            other ->
              {:halt, {:error, "unexpected GitHub contents entry #{inspect(other)}"}}
          end
        end)

      {:ok, other} ->
        {:error, "expected a directory listing, got #{inspect(other)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_contents(commit_sha, path) do
    encoded_path =
      path
      |> String.split("/")
      |> Enum.map_join("/", &URI.encode/1)

    contents_url =
      if encoded_path == "" do
        @contents_base
      else
        "#{@contents_base}/#{encoded_path}"
      end

    url = "#{contents_url}?ref=#{URI.encode_www_form(commit_sha)}"

    case http_get(url) do
      {:ok, 200, body} -> decode_json(body)
      {:ok, 404, _body} -> {:ok, :missing}
      {:ok, status, _body} -> {:error, "GitHub API HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_json(body) do
    try do
      {:ok, :json.decode(body)}
    rescue
      error -> {:error, "invalid GitHub API JSON: #{Exception.message(error)}"}
    end
  end

  defp http_get(url) do
    args =
      [
        "--silent",
        "--show-error",
        "--location",
        "--connect-timeout",
        "10",
        "--max-time",
        "30",
        "--retry",
        "2",
        "--retry-all-errors",
        "--header",
        "Accept: application/vnd.github+json",
        "--header",
        "X-GitHub-Api-Version: 2022-11-28",
        "--header",
        "User-Agent: pramana-agent-convention-watch"
      ] ++ auth_args() ++ ["--write-out", "#{@http_marker}%{http_code}", url]

    case System.cmd("curl", args, stderr_to_stdout: true) do
      {output, 0} ->
        case String.split(output, @http_marker, parts: 2) do
          [body, status_text] ->
            case Integer.parse(String.trim(status_text)) do
              {status, ""} -> {:ok, status, body}
              _ -> {:error, "curl returned an invalid HTTP status"}
            end

          _ ->
            {:error, "curl response did not include an HTTP status"}
        end

      {message, status} ->
        {:error, "curl exit #{status}: #{String.trim(message)}"}
    end
  end

  defp auth_args do
    case System.get_env("PRAMANA_GITHUB_TOKEN") do
      token when is_binary(token) and token != "" ->
        ["--header", "Authorization: Bearer #{token}"]

      _ ->
        []
    end
  end

  defp source_diff(expected, actual) do
    expected_paths = Map.keys(expected) |> MapSet.new()
    actual_paths = Map.keys(actual) |> MapSet.new()

    added =
      actual_paths
      |> MapSet.difference(expected_paths)
      |> Enum.sort()
      |> Enum.map(fn path -> {path, Map.fetch!(actual, path)} end)

    removed =
      expected_paths
      |> MapSet.difference(actual_paths)
      |> Enum.sort()
      |> Enum.map(fn path -> {path, Map.fetch!(expected, path)} end)

    changed =
      expected_paths
      |> MapSet.intersection(actual_paths)
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        recorded_sha = Map.fetch!(expected, path)
        current_sha = Map.fetch!(actual, path)

        if recorded_sha == current_sha do
          []
        else
          [{path, recorded_sha, current_sha}]
        end
      end)

    %{added: added, removed: removed, changed: changed}
  end

  defp empty_diff, do: %{added: [], removed: [], changed: []}

  defp diff?(%{added: added, removed: removed, changed: changed}) do
    added != [] or removed != [] or changed != []
  end

  defp report_snapshot(recorded_commit, resolved_commit) do
    if resolved_commit do
      IO.puts("Recorded upstream snapshot: #{recorded_commit}")
      IO.puts("Resolved upstream snapshot: #{resolved_commit}\n")
    end
  end

  defp report_diff(diff) do
    if diff?(diff) do
      report_pairs("Added upstream source files:", diff.added, "current")
      report_pairs("Removed upstream source files:", diff.removed, "recorded")

      if diff.changed != [] do
        IO.puts("Changed upstream source blobs:")

        Enum.each(diff.changed, fn {path, recorded_sha, current_sha} ->
          IO.puts("  - #{path}")
          IO.puts("      recorded: #{recorded_sha}")
          IO.puts("      current:  #{current_sha}")
        end)
      end
    else
      IO.puts("No source inventory or blob changes detected.")
    end
  end

  defp report_pairs(_heading, [], _label), do: :ok

  defp report_pairs(heading, entries, label) do
    IO.puts(heading)

    Enum.each(entries, fn {path, sha} ->
      IO.puts("  - #{path}")
      IO.puts("      #{label}: #{sha}")
    end)
  end

  defp report_fetch_errors([]), do: :ok

  defp report_fetch_errors(errors) do
    IO.puts(:stderr, "\nUnable to fetch upstream source inventory:")

    Enum.each(errors, fn {path, reason} ->
      IO.puts(:stderr, "  - #{path}: #{reason}")
    end)
  end

  defp add_date_error(errors, label, value) do
    case Date.from_iso8601(value) do
      {:ok, _date} -> errors
      {:error, _reason} -> ["#{label} must be an ISO date, found #{inspect(value)}." | errors]
    end
  end

  defp add_sha_error(errors, label, value) do
    add_if(errors, not valid_git_sha?(value), "#{label} must be a 40-character Git SHA.")
  end

  defp add_root_errors(errors, roots) do
    errors
    |> add_if(roots == [], "No upstream source_roots are recorded.")
    |> add_if(length(Enum.uniq(roots)) != length(roots), "source_roots contains duplicates.")
    |> then(fn acc ->
      Enum.reduce(roots, acc, fn root, inner ->
        add_if(
          inner,
          not safe_relative_path?(root),
          "Invalid upstream source root #{inspect(root)}."
        )
      end)
    end)
  end

  defp add_local_file_errors(errors, local_files) do
    actual_files =
      @conventions_dir
      |> Path.join("**/*.md")
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, @conventions_dir))
      |> Enum.sort()

    recorded_files = Enum.filter(local_files, &is_binary/1) |> Enum.sort()

    errors
    |> add_if(local_files == [], "No local convention files are recorded.")
    |> add_if(
      length(Enum.uniq(local_files)) != length(local_files),
      "local_files contains duplicates."
    )
    |> then(fn acc ->
      Enum.reduce(local_files, acc, fn relative, inner ->
        add_if(
          inner,
          not safe_relative_path?(relative),
          "Invalid convention file path #{inspect(relative)}."
        )
      end)
    end)
    |> then(fn acc ->
      Enum.reduce(actual_files -- recorded_files, acc, fn relative, inner ->
        ["Unrecorded local convention file #{relative}." | inner]
      end)
    end)
    |> then(fn acc ->
      Enum.reduce(recorded_files -- actual_files, acc, fn relative, inner ->
        ["Manifest references missing local convention file #{relative}." | inner]
      end)
    end)
  end

  defp add_source_map_errors(errors, label, sources, roots) do
    errors
    |> add_if(map_size(sources) == 0, "No #{label} entries are recorded.")
    |> then(fn acc ->
      Enum.reduce(sources, acc, fn {path, sha}, inner ->
        cond do
          not is_binary(path) or not safe_relative_path?(path) ->
            ["#{label} contains invalid path #{inspect(path)}." | inner]

          not source_under_roots?(path, roots) ->
            ["#{label} path #{path} is outside source_roots." | inner]

          not valid_git_sha?(sha) ->
            ["#{label} path #{path} has invalid blob SHA #{inspect(sha)}." | inner]

          true ->
            inner
        end
      end)
    end)
    |> then(fn acc ->
      Enum.reduce(roots, acc, fn root, inner ->
        has_source? = Enum.any?(Map.keys(sources), &source_under_root?(&1, root))
        add_if(inner, not has_source?, "#{label} has no recorded sources under #{root}.")
      end)
    end)
  end

  defp source_under_roots?(path, roots), do: Enum.any?(roots, &source_under_root?(path, &1))

  defp source_under_root?(path, root) when is_binary(path) and is_binary(root) do
    path == root or String.starts_with?(path, root <> "/")
  end

  defp source_under_root?(_path, _root), do: false

  defp safe_relative_path?(path) when is_binary(path) do
    path != "" and Path.type(path) == :relative and ".." not in Path.split(path)
  end

  defp safe_relative_path?(_path), do: false

  defp valid_git_sha?(sha) when is_binary(sha), do: String.match?(sha, ~r/\A[0-9a-f]{40}\z/)
  defp valid_git_sha?(_sha), do: false

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

    --check       Network-free CI guard: lock, local inventory and reviewed metadata must agree.
    --review      Resolve the locked Phoenix tag once, then compare its rule inventory/blobs.
    --watch-main  Resolve Phoenix main once, then compare its rule inventory/blobs.
    """)

    System.halt(status)
  end
end

Pramana.AgentConventionSync.main(System.argv())