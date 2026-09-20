defmodule PramanaFoundry.DurableStore.LegacyImport do
  @moduledoc """
  Offline, rerun-safe JSONL import retaining both the original bytes and per-line evidence.

  This module never starts the Foundry application or effects. SQLite's immediate
  transaction refuses a concurrent writer. Invalid input remains archived and recorded;
  it is not converted into authoritative domain events.
  """

  alias PramanaFoundry.{AtomicFile, Schema}
  alias PramanaFoundry.DurableStore.{Database, Encoding, Owner}

  def run(database_path, source_path, archive_dir, opts \\ []) do
    manifest_path =
      Keyword.get(opts, :manifest_path, Path.join(archive_dir, "import-manifest.json"))

    with {:ok, source_stat} <- File.stat(source_path),
         true <- source_stat.type == :regular,
         {:ok, digest} <- file_digest(source_path),
         archived_path <- Path.join(archive_dir, digest <> ".jsonl"),
         :ok <- validate_paths(database_path, source_path, archive_dir, archived_path, manifest_path),
         {:ok, owner} <- Owner.acquire(database_path, opts) do
      try do
        run_owned(
          database_path,
          source_path,
          archived_path,
          manifest_path,
          digest,
          opts
        )
      after
        Owner.release(owner)
      end
    else
      false -> {:error, :source_not_regular}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_owned(database_path, source_path, archived_path, manifest_path, digest, opts) do
    with :ok <- preserve_original(source_path, archived_path, digest),
         {:ok, archive_stat} <- File.stat(archived_path),
         :ok <- verify_digest(archived_path, digest),
         {:ok, conn} <- Database.open(database_path),
         result <-
           import_or_replay(
             conn,
             source_path,
             archived_path,
             digest,
             archive_stat.size,
             opts
           ),
         :ok <- Database.close(conn),
         {:ok, manifest} <- result,
         :ok <- AtomicFile.write(manifest_path, manifest, Keyword.get(opts, :manifest_write_opts, [])) do
      {:ok, Map.put(manifest, "manifest_path", manifest_path)}
    end
  end

  defp import_or_replay(conn, source_path, archived_path, digest, size, opts) do
    case existing_manifest(conn, digest) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, :not_found} -> import(conn, source_path, archived_path, digest, size, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp import(conn, source_path, archived_path, digest, size, opts) do
    Database.transaction(conn, fn ->
      placeholder = %{"schema_version" => 1, "status" => "importing", "source_digest" => digest}

      with {:ok, encoded_placeholder} <- Encoding.json(placeholder),
           :ok <-
             Database.execute(
               conn,
               "INSERT INTO import_runs(source_digest, source_path, archived_path, source_bytes, line_count, valid_count, invalid_count, manifest) VALUES (?, ?, ?, ?, 0, 0, 0, ?)",
               [digest, source_path, archived_path, size, {:blob, encoded_placeholder}]
             ),
           {:ok, summary} <- import_lines(conn, archived_path, digest, opts),
           manifest <- manifest(source_path, archived_path, digest, size, summary),
           {:ok, encoded_manifest} <- Encoding.json(manifest),
           :ok <-
             Database.execute(
               conn,
               "UPDATE import_runs SET line_count = ?, valid_count = ?, invalid_count = ?, manifest = ? WHERE source_digest = ?",
               [summary.lines, summary.valid, summary.invalid, {:blob, encoded_manifest}, digest]
             ) do
        {:ok, manifest}
      end
    end)
  end

  defp import_lines(conn, source_path, source_digest, opts) do
    source_path
    |> File.stream!(:line, [])
    |> Enum.reduce_while(
      {:ok, %{offset: 0, lines: 0, valid: 0, invalid: 0, errors: []}},
      fn bytes, {:ok, acc} ->
        fail_after = Keyword.get(opts, :fail_after_lines)

        if is_integer(fail_after) and acc.lines >= fail_after do
          {:halt, {:error, {:injected_import_interruption, fail_after}}}
        else
        line_number = acc.lines + 1
        byte_start = acc.offset
        byte_end = byte_start + byte_size(bytes)
        {valid, error} = validate_line(bytes)
        record_digest = Encoding.digest(bytes)

        result =
          Database.execute(
            conn,
            "INSERT INTO legacy_records(source_digest, line_number, byte_start, byte_end, record_digest, valid, error, raw_record) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [
              source_digest,
              line_number,
              byte_start,
              byte_end,
              record_digest,
              if(valid, do: 1, else: 0),
              error,
              {:blob, bytes}
            ]
          )

        case result do
          :ok ->
            next = %{
              offset: byte_end,
              lines: line_number,
              valid: acc.valid + if(valid, do: 1, else: 0),
              invalid: acc.invalid + if(valid, do: 0, else: 1),
              errors:
                maybe_error(
                  acc.errors,
                  valid,
                  line_number,
                  byte_start,
                  byte_end,
                  record_digest,
                  error
                )
            }

            {:cont, {:ok, next}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
        end
      end
    )
  rescue
    exception -> {:error, {:source_read_failed, exception}}
  end

  defp validate_line(bytes) do
    cond do
      not String.valid?(bytes) -> {false, "invalid_utf8"}
      not String.ends_with?(bytes, "\n") -> {false, "unterminated_jsonl"}
      true -> decode_line(String.trim_trailing(bytes, "\n"))
    end
  end

  defp decode_line("") do
    {false, "empty_record"}
  end

  defp decode_line(line) do
    decoded = :json.decode(line)

    case Schema.validate(:event, decoded) do
      {:ok, _record} -> {true, nil}
      {:error, error} -> {false, "schema:" <> inspect(error.reason)}
    end
  rescue
    _ -> {false, "malformed_json"}
  catch
    _, _ -> {false, "malformed_json"}
  end

  defp maybe_error(errors, true, _line, _start, _end, _digest, _error), do: errors

  defp maybe_error(errors, false, line, start_byte, end_byte, digest, error) do
    [
      %{
        "line" => line,
        "byte_start" => start_byte,
        "byte_end" => end_byte,
        "record_digest" => digest,
        "error" => error
      }
      | errors
    ]
  end

  defp manifest(source_path, archived_path, digest, size, summary) do
    %{
      "schema_version" => 1,
      "source_path" => source_path,
      "archived_path" => archived_path,
      "source_digest" => digest,
      "source_bytes" => size,
      "byte_range" => %{"start" => 0, "end" => summary.offset},
      "line_count" => summary.lines,
      "valid_count" => summary.valid,
      "invalid_count" => summary.invalid,
      "errors" => Enum.reverse(summary.errors)
    }
  end

  defp existing_manifest(conn, digest) do
    case Database.query(conn, "SELECT manifest FROM import_runs WHERE source_digest = ?", [digest]) do
      {:ok, [[encoded]]} -> decode_manifest(encoded)
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_manifest(encoded) do
    {:ok, :json.decode(encoded)}
  rescue
    _ -> {:error, :corrupt_import_manifest}
  end

  defp preserve_original(source_path, archived_path, expected_digest) do
    with :ok <- File.mkdir_p(Path.dirname(archived_path)) do
      case File.stat(archived_path) do
        {:ok, _stat} -> verify_digest(archived_path, expected_digest)
        {:error, :enoent} -> copy_and_sync(source_path, archived_path, expected_digest)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp copy_and_sync(source_path, archived_path, expected_digest) do
    temp = archived_path <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive]))

    with {:ok, _bytes} <- File.copy(source_path, temp),
         :ok <- sync_file(temp),
         :ok <- verify_digest(temp, expected_digest),
         :ok <- File.rename(temp, archived_path),
         :ok <- sync_directory(Path.dirname(archived_path)),
         :ok <- verify_digest(archived_path, expected_digest) do
      :ok
    else
      {:error, reason} = error ->
        _ = File.rm(temp)
        if reason == :eexist, do: verify_digest(archived_path, expected_digest), else: error
    end
  end

  defp verify_digest(path, expected) do
    case file_digest(path) do
      {:ok, ^expected} -> :ok
      {:ok, actual} -> {:error, {:archive_digest_mismatch, actual, expected}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp file_digest(path) do
    context =
      path
      |> File.stream!(64 * 1024, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))

    {:ok, context |> :crypto.hash_final() |> Base.encode16(case: :lower)}
  rescue
    exception -> {:error, {:digest_failed, exception}}
  end

  defp sync_file(path) do
    with {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]),
         :ok <- :file.sync(file),
         :ok <- :file.close(file) do
      :ok
    end
  end

  defp sync_directory(path) do
    with {:ok, file} <- :file.open(String.to_charlist(path), [:read, :raw, :directory]),
         :ok <- :file.sync(file),
         :ok <- :file.close(file) do
      :ok
    end
  end

  defp validate_paths(database_path, source_path, archive_dir, archived_path, manifest_path) do
    with :ok <- File.mkdir_p(archive_dir),
         {:ok, database} <- canonical_existing(database_path),
         {:ok, source} <- canonical_existing(source_path),
         {:ok, archive_root} <- canonical_existing(archive_dir),
         {:ok, archive} <- canonical_target(archived_path),
         {:ok, manifest} <- canonical_target(manifest_path) do
      protected_paths =
        [database | Owner.sidecars(database_path)]
        |> Enum.map(fn path -> canonical_target(path) end)
        |> Enum.flat_map(fn
          {:ok, path} -> [path]
          _error -> []
        end)

      output_paths = [archive, manifest]
      all_paths = [source, archive_root | output_paths]
      protected_sources = [database_path | Owner.sidecars(database_path)]

      cond do
        length(Enum.uniq(all_paths)) != length(all_paths) -> {:error, :import_path_collision}
        Enum.any?([source | output_paths], &(&1 in protected_paths)) ->
          {:error, :store_path_collision}

        Enum.any?([source_path, archived_path, manifest_path], fn import_path ->
          Enum.any?(protected_sources, &same_file?(import_path, &1))
        end) ->
          {:error, :store_path_alias}

        same_file?(source_path, manifest_path) or same_file?(source_path, archived_path) or
            same_file?(archived_path, manifest_path) ->
          {:error, :import_path_alias}

        true -> :ok
      end
    end
  end

  defp canonical_existing(path), do: canonicalize(Path.expand(path), 0)

  defp canonical_target(path) do
    expanded = Path.expand(path)

    case File.lstat(expanded) do
      {:ok, _stat} -> canonical_existing(expanded)
      {:error, :enoent} ->
        with {:ok, parent} <- canonical_existing(Path.dirname(expanded)) do
          {:ok, Path.join(parent, Path.basename(expanded))}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonicalize(_path, hops) when hops > 40, do: {:error, :too_many_symlinks}

  defp canonicalize(path, hops) do
    parts = Path.split(path)
    [root | rest] = parts

    Enum.reduce_while(rest, {:ok, root}, fn part, {:ok, current} ->
      next = Path.join(current, part)

      case File.lstat(next) do
        {:ok, %{type: :symlink}} ->
          case File.read_link(next) do
            {:ok, target} ->
              resolved = if Path.type(target) == :absolute, do: target, else: Path.join(current, target)

              case canonicalize(resolved, hops + 1) do
                {:ok, value} -> {:cont, {:ok, value}}
                {:error, reason} -> {:halt, {:error, reason}}
              end

            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:ok, _stat} -> {:cont, {:ok, next}}
        {:error, :enoent} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp same_file?(first, second) do
    with {:ok, first_stat} <- File.stat(first),
         {:ok, second_stat} <- File.stat(second) do
      {first_stat.major_device, first_stat.inode} == {second_stat.major_device, second_stat.inode}
    else
      _ -> false
    end
  end
end
