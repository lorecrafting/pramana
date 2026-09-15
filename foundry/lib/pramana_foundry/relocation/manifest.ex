defmodule PramanaFoundry.Relocation.Manifest do
  @moduledoc """
  Dry-run inventory manifest analyzing `pramana-*` directories and legacy external state/worktrees.

  Collects:
  - Git common-dir, branch/ref/HEAD, dirty tracked bytes, untracked and ignored content
  - Live handles and processes referencing directories
  - Symlinks (relative, absolute, broken)
  - Destination collisions
  - Disk usage and filesystem headroom
  """

  alias PramanaFoundry.Relocation.Worktree

  defstruct [
    :timestamp,
    :directories,
    :total_source_bytes,
    :destination_headroom_bytes,
    :sufficient_headroom,
    :can_relocate,
    :warnings
  ]

  @type t :: %__MODULE__{
          timestamp: binary(),
          directories: [map()],
          total_source_bytes: non_neg_integer(),
          destination_headroom_bytes: non_neg_integer(),
          sufficient_headroom: boolean(),
          can_relocate: boolean(),
          warnings: [binary()]
        }

  @doc """
  Builds a dry-run inventory manifest.

  Options:
  - `:root`: root directory to discover `pramana-*` directories (defaults to parent of current working dir).
  - `:paths`: explicit list of directory paths to analyze.
  - `:destinations`: map of `%{source_path => destination_path}` or `:destination_root`.
  - `:destination_headroom_bytes`: explicit headroom override in bytes.
  - `:original_checkout`: path to original checkout.
  - `:root_chat_dir`: path to root chat working directory.
  - `:mock_live_handles`: map of `%{path => [%{pid: ..., path: ...}]}` for tests.
  """
  @spec build(keyword()) :: {:ok, t()} | {:error, term()}
  def build(opts \\ []) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    target_paths = discover_paths(opts)
    destinations = resolve_destinations(target_paths, opts)

    directories =
      Enum.map(target_paths, fn path ->
        dest = Map.get(destinations, path)
        analyze_directory(path, dest, opts)
      end)

    movable_directories =
      Enum.filter(directories, fn d ->
        d.safety.movable and d.destination.path != nil
      end)

    total_source_bytes =
      Enum.reduce(movable_directories, 0, fn d, acc ->
        acc + d.disk_use_bytes
      end)

    sample_dest =
      case movable_directories do
        [first | _] -> first.destination.path
        [] -> Keyword.get(opts, :destination_root, File.cwd!())
      end

    headroom_bytes = resolve_headroom(sample_dest, opts)
    sufficient_headroom = headroom_bytes >= total_source_bytes

    collisions =
      Enum.filter(directories, fn d ->
        d.destination.collision
      end)

    can_relocate =
      sufficient_headroom and
        collisions == [] and
        (movable_directories != [] or directories == [])

    warnings =
      generate_warnings(directories, sufficient_headroom, total_source_bytes, headroom_bytes)

    manifest = %__MODULE__{
      timestamp: timestamp,
      directories: directories,
      total_source_bytes: total_source_bytes,
      destination_headroom_bytes: headroom_bytes,
      sufficient_headroom: sufficient_headroom,
      can_relocate: can_relocate,
      warnings: warnings
    }

    {:ok, manifest}
  end

  @doc """
  Converts manifest to a JSON-serializable map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = m) do
    %{
      "timestamp" => m.timestamp,
      "directories" => m.directories,
      "total_source_bytes" => m.total_source_bytes,
      "destination_headroom_bytes" => m.destination_headroom_bytes,
      "sufficient_headroom" => m.sufficient_headroom,
      "can_relocate" => m.can_relocate,
      "warnings" => m.warnings
    }
  end

  @doc """
  Formats the manifest as a human-readable summary text.
  """
  @spec format(t()) :: binary()
  def format(%__MODULE__{} = m) do
    lines = [
      "=== Pramana Workspace Relocation Inventory Manifest ===",
      "Timestamp: #{m.timestamp}",
      "Can Relocate: #{m.can_relocate}",
      "Total Source Bytes: #{m.total_source_bytes}",
      "Destination Headroom: #{m.destination_headroom_bytes} bytes",
      "Sufficient Headroom: #{m.sufficient_headroom}",
      "",
      "Directories (#{length(m.directories)}):"
    ]

    dir_lines =
      Enum.flat_map(m.directories, fn d ->
        [
          "  * #{d.name} (#{d.kind}) - #{d.path}",
          "    Movable: #{d.safety.movable}#{if d.safety.reasons != [], do: " (Reasons: #{inspect(d.safety.reasons)})", else: ""}",
          "    Destination: #{d.destination.path || "none"} (Collision: #{d.destination.collision})",
          "    Disk Use: #{d.disk_use_bytes} bytes",
          "    Git: is_git=#{d.git.is_git}, branch=#{d.git.branch || "none"}, dirty_tracked=#{d.git.dirty_tracked.count} files (#{d.git.dirty_tracked.bytes} bytes), untracked=#{d.git.untracked.count} files, ignored=#{d.git.ignored.count} files",
          "    Symlinks: #{length(d.symlinks)}, Live Handles: #{length(d.live_handles)}"
        ]
      end)

    warning_lines =
      if m.warnings != [] do
        ["", "Warnings:"] ++ Enum.map(m.warnings, &"  ! #{&1}")
      else
        []
      end

    Enum.join(lines ++ dir_lines ++ warning_lines, "\n")
  end

  defp discover_paths(opts) do
    case Keyword.get(opts, :paths) do
      paths when is_list(paths) and paths != [] ->
        Enum.map(paths, &Path.expand/1)

      _ ->
        root = Keyword.get_lazy(opts, :root, fn -> Path.dirname(File.cwd!()) end) |> Path.expand()

        discovered =
          case File.ls(root) do
            {:ok, entries} ->
              entries
              |> Enum.filter(fn entry ->
                String.starts_with?(entry, "pramana-") or
                  entry in [".pramana-supervisor", ".pramana", "pramana_tasks"]
              end)
              |> Enum.map(&Path.join(root, &1))
              |> Enum.filter(&File.dir?/1)

            _ ->
              []
          end

        # Also check current directory if it starts with pramana
        cwd = File.cwd!()
        cwd_name = Path.basename(cwd)

        all_paths =
          if String.starts_with?(cwd_name, "pramana-") do
            [cwd | discovered]
          else
            discovered
          end

        Enum.uniq(all_paths)
    end
  end

  defp resolve_destinations(paths, opts) do
    dest_map = Keyword.get(opts, :destinations, %{})

    case Keyword.get(opts, :destination_root) do
      dest_root when is_binary(dest_root) ->
        abs_dest_root = Path.expand(dest_root)

        Enum.reduce(paths, %{}, fn path, acc ->
          name = Path.basename(path)
          Map.put(acc, path, Map.get(dest_map, path, Path.join(abs_dest_root, name)))
        end)

      _ ->
        Enum.reduce(paths, %{}, fn path, acc ->
          Map.put(acc, path, Map.get(dest_map, path))
        end)
    end
  end

  defp analyze_directory(path, destination, opts) do
    abs_path = Path.expand(path)
    name = Path.basename(abs_path)
    is_worktree = Worktree.worktree?(abs_path)
    is_orig = Worktree.original_checkout?(abs_path, opts)
    is_root_chat = Worktree.root_chat_directory?(abs_path, opts)

    kind =
      cond do
        is_orig -> :original_checkout
        is_worktree -> :worktree
        File.exists?(Path.join(abs_path, ".git")) -> :git_repo
        String.contains?(name, "supervisor") or String.contains?(name, "state") -> :legacy_state
        true -> :directory
      end

    git_info = inspect_git(abs_path)
    symlinks = inspect_symlinks(abs_path)
    live_handles = inspect_live_handles(abs_path, opts)
    disk_use = compute_disk_usage(abs_path)

    dest_info =
      case destination do
        nil ->
          %{path: nil, collision: false}

        dest_path ->
          abs_dest = Path.expand(dest_path)
          %{path: abs_dest, collision: destination_collides?(abs_dest)}
      end

    {movable, reasons} =
      check_movability(abs_path, dest_info, is_orig, is_root_chat)

    %{
      path: abs_path,
      name: name,
      kind: kind,
      git: git_info,
      symlinks: symlinks,
      live_handles: live_handles,
      disk_use_bytes: disk_use,
      destination: dest_info,
      safety: %{
        is_original_checkout: is_orig,
        is_root_chat_dir: is_root_chat,
        movable: movable,
        reasons: reasons
      }
    }
  end

  defp check_movability(src, dest_info, is_orig, is_root_chat) do
    reasons =
      []
      |> then(fn acc -> if is_orig, do: [:original_checkout | acc], else: acc end)
      |> then(fn acc -> if is_root_chat, do: [:root_chat_directory | acc], else: acc end)
      |> then(fn acc ->
        if dest_info.collision, do: [:destination_collision | acc], else: acc
      end)
      |> then(fn acc ->
        if not File.exists?(src), do: [:source_not_found | acc], else: acc
      end)

    movable = reasons == []
    {movable, Enum.reverse(reasons)}
  end

  defp destination_collides?(abs_dest) do
    if File.exists?(abs_dest) do
      case File.ls(abs_dest) do
        {:ok, []} -> false
        {:ok, _entries} -> true
        _ -> true
      end
    else
      false
    end
  end

  defp inspect_git(abs_path) do
    if File.exists?(Path.join(abs_path, ".git")) do
      common_dir =
        case System.cmd("git", ["rev-parse", "--git-common-dir"],
               cd: abs_path,
               stderr_to_stdout: true
             ) do
          {dir, 0} -> Path.expand(String.trim(dir), abs_path)
          _ -> nil
        end

      git_dir =
        case System.cmd("git", ["rev-parse", "--git-dir"], cd: abs_path, stderr_to_stdout: true) do
          {dir, 0} -> Path.expand(String.trim(dir), abs_path)
          _ -> nil
        end

      head =
        case System.cmd("git", ["rev-parse", "HEAD"], cd: abs_path, stderr_to_stdout: true) do
          {h, 0} -> String.trim(h)
          _ -> nil
        end

      branch =
        case System.cmd("git", ["symbolic-ref", "--short", "HEAD"],
               cd: abs_path,
               stderr_to_stdout: true
             ) do
          {b, 0} ->
            String.trim(b)

          _ ->
            case head do
              nil -> nil
              h -> "HEAD (detached: #{String.slice(h, 0, 7)})"
            end
        end

      dirty_tracked = compute_dirty_tracked(abs_path)
      untracked = compute_untracked(abs_path)
      ignored = compute_ignored(abs_path)

      %{
        is_git: true,
        git_common_dir: common_dir,
        git_dir: git_dir,
        head: head,
        branch: branch,
        dirty_tracked: dirty_tracked,
        untracked: untracked,
        ignored: ignored
      }
    else
      %{
        is_git: false,
        git_common_dir: nil,
        git_dir: nil,
        head: nil,
        branch: nil,
        dirty_tracked: %{count: 0, bytes: 0},
        untracked: %{count: 0, bytes: 0},
        ignored: %{count: 0, bytes: 0}
      }
    end
  end

  defp compute_dirty_tracked(abs_path) do
    case System.cmd("git", ["diff", "--name-only", "HEAD"], cd: abs_path, stderr_to_stdout: true) do
      {output, 0} ->
        files = String.split(output, "\n", trim: true)

        bytes =
          Enum.reduce(files, 0, fn file, acc ->
            case File.stat(Path.join(abs_path, file)) do
              {:ok, %File.Stat{size: s}} -> acc + s
              _ -> acc
            end
          end)

        %{count: length(files), bytes: bytes}

      _ ->
        %{count: 0, bytes: 0}
    end
  end

  defp compute_untracked(abs_path) do
    case System.cmd("git", ["status", "--porcelain=v1"], cd: abs_path, stderr_to_stdout: true) do
      {output, 0} ->
        untracked_paths =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, "?? "))
          |> Enum.map(&String.trim_leading(&1, "?? "))

        bytes =
          Enum.reduce(untracked_paths, 0, fn rel_path, acc ->
            full_path = Path.join(abs_path, rel_path)
            acc + compute_disk_usage(full_path)
          end)

        %{count: length(untracked_paths), bytes: bytes}

      _ ->
        %{count: 0, bytes: 0}
    end
  end

  defp compute_ignored(abs_path) do
    case System.cmd("git", ["status", "--porcelain=v1", "--ignored"],
           cd: abs_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        ignored_paths =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, "!! "))
          |> Enum.map(&String.trim_leading(&1, "!! "))

        bytes =
          Enum.reduce(ignored_paths, 0, fn rel_path, acc ->
            full_path = Path.join(abs_path, rel_path)
            acc + compute_disk_usage(full_path)
          end)

        %{count: length(ignored_paths), bytes: bytes}

      _ ->
        %{count: 0, bytes: 0}
    end
  end

  defp inspect_symlinks(abs_path) do
    list_symlinks_recursively(abs_path, abs_path, 0, 8)
  end

  defp list_symlinks_recursively(_current, _base, depth, max_depth) when depth > max_depth, do: []

  defp list_symlinks_recursively(current, base, depth, max_depth) do
    case File.ls(current) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          if entry == ".git" do
            []
          else
            full = Path.join(current, entry)

            case File.lstat(full) do
              {:ok, %File.Stat{type: :symlink}} ->
                target =
                  case File.read_link(full) do
                    {:ok, t} -> t
                    _ -> ""
                  end

                is_abs = String.starts_with?(target, "/")

                resolved_target =
                  if is_abs, do: target, else: Path.expand(target, Path.dirname(full))

                broken = not File.exists?(resolved_target)

                [
                  %{
                    path: Path.relative_to(full, base),
                    target: target,
                    absolute: is_abs,
                    broken: broken
                  }
                ]

              {:ok, %File.Stat{type: :directory}} ->
                list_symlinks_recursively(full, base, depth + 1, max_depth)

              _ ->
                []
            end
          end
        end)

      _ ->
        []
    end
  end

  defp inspect_live_handles(abs_path, opts) do
    case Keyword.get(opts, :mock_live_handles) do
      mock when is_map(mock) ->
        Map.get(mock, abs_path, [])

      _ ->
        case System.find_executable("lsof") do
          nil ->
            []

          _ ->
            case System.cmd("lsof", ["-t", "+D", abs_path], stderr_to_stdout: true) do
              {output, 0} ->
                output
                |> String.split("\n", trim: true)
                |> Enum.map(fn pid_str ->
                  case Integer.parse(pid_str) do
                    {pid, ""} -> %{pid: pid, path: abs_path}
                    _ -> nil
                  end
                end)
                |> Enum.reject(&is_nil/1)

              _ ->
                []
            end
        end
    end
  end

  defp compute_disk_usage(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} ->
        size

      {:ok, %File.Stat{type: :directory}} ->
        case File.ls(path) do
          {:ok, entries} ->
            Enum.reduce(entries, 0, fn entry, acc ->
              if entry == ".git" do
                acc
              else
                acc + compute_disk_usage(Path.join(path, entry))
              end
            end)

          _ ->
            0
        end

      _ ->
        0
    end
  end

  defp resolve_headroom(dest_path, opts) do
    case Keyword.get(opts, :destination_headroom_bytes) do
      bytes when is_integer(bytes) and bytes >= 0 ->
        bytes

      _ ->
        dir = if File.exists?(dest_path), do: dest_path, else: Path.dirname(dest_path)

        case System.cmd("df", ["-k", dir], stderr_to_stdout: true) do
          {output, 0} ->
            lines = String.split(output, "\n", trim: true)

            case Enum.at(lines, 1) do
              nil ->
                1_000_000_000

              row ->
                parts = String.split(row, ~r/\s+/)

                case Enum.at(parts, 3) do
                  nil ->
                    1_000_000_000

                  avail_kb_str ->
                    case Integer.parse(avail_kb_str) do
                      {kb, ""} -> kb * 1024
                      _ -> 1_000_000_000
                    end
                end
            end

          _ ->
            1_000_000_000
        end
    end
  end

  defp generate_warnings(directories, sufficient_headroom, total_source_bytes, headroom_bytes) do
    warnings = []

    warnings =
      if not sufficient_headroom do
        [
          "Insufficient destination headroom: required #{total_source_bytes} bytes, but only #{headroom_bytes} bytes available"
          | warnings
        ]
      else
        warnings
      end

    Enum.reduce(directories, warnings, fn d, acc ->
      acc_new =
        if d.destination.collision do
          [
            "Destination collision for #{d.name}: #{d.destination.path} already exists and is non-empty"
            | acc
          ]
        else
          acc
        end

      acc_new =
        if d.git.dirty_tracked.count > 0 do
          [
            "Dirty tracked changes detected in #{d.name}: #{d.git.dirty_tracked.count} files (#{d.git.dirty_tracked.bytes} bytes)"
            | acc_new
          ]
        else
          acc_new
        end

      acc_new =
        if d.live_handles != [] do
          [
            "Live process handles detected in #{d.name}: #{length(d.live_handles)} handles"
            | acc_new
          ]
        else
          acc_new
        end

      broken_symlinks = Enum.filter(d.symlinks, & &1.broken)

      if broken_symlinks != [] do
        [
          "Broken symlinks detected in #{d.name}: #{length(broken_symlinks)} broken symlinks"
          | acc_new
        ]
      else
        acc_new
      end
    end)
    |> Enum.reverse()
  end
end
