defmodule PramanaFoundry.DurableStore.LegacyImport do
  @moduledoc """
  Offline, rerun-safe JSONL import retaining both the original bytes and per-line evidence.

  This module never starts the Foundry application or effects. SQLite's immediate
  transaction refuses a concurrent writer. Invalid input remains archived and recorded;
  it is not converted into authoritative domain events.
  """

  alias PramanaFoundry.AtomicFile

  alias PramanaFoundry.DurableStore.{
    Authority,
    Database,
    Encoding,
    LegacyLine,
    Owner,
    PathIdentity,
    RecordCodec
  }

  def run(database_path, source_path, archive_dir, opts \\ []) do
    manifest_path =
      Keyword.get(opts, :manifest_path, Path.join(archive_dir, "import-manifest.json"))

    with {:ok, database} <- database_identity(database_path),
         {:ok, source} <- PathIdentity.existing(source_path),
         :ok <- preflight_archive_root(database, source, archive_dir),
         :ok <- ensure_archive_dir(archive_dir),
         {:ok, digest} <- file_digest(source_path),
         archived_path <- Path.join(archive_dir, digest <> ".jsonl"),
         {:ok, paths} <-
           validate_paths(database, source, archive_dir, archived_path, manifest_path),
         :ok <- PathIdentity.revalidate(source),
         {:ok, owner} <- Owner.acquire(database, opts) do
      try do
        run_owned(
          owner.identity,
          source.path,
          paths.archive.path,
          paths.manifest.path,
          digest,
          opts
        )
      after
        Owner.release(owner)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp database_identity(path) do
    PathIdentity.existing(path)
  end

  defp run_owned(database_identity, source_path, archived_path, manifest_path, digest, opts) do
    manifest_opts =
      opts
      |> Keyword.get(:manifest_write_opts, [])
      |> Keyword.put(:txid, String.slice(digest, 0, 16))

    txid = Keyword.fetch!(manifest_opts, :txid)

    with :ok <- preserve_original(source_path, archived_path, digest),
         {:ok, archive_stat} <- File.stat(archived_path),
         :ok <- verify_digest(archived_path, digest),
         {:ok, conn} <- Database.open(database_identity),
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
         :ok <- prepare_manifest_publication(manifest_path, manifest, txid),
         :ok <- AtomicFile.write(manifest_path, manifest, manifest_opts) do
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

      with {:ok, encoded_placeholder} <- RecordCodec.encode(:import_placeholder, placeholder),
           :ok <-
             Database.execute(
               conn,
               "INSERT INTO import_runs(source_digest, source_path, archived_path, source_bytes, line_count, valid_count, invalid_count, manifest) VALUES (?, ?, ?, ?, 0, 0, 0, ?)",
               [digest, source_path, archived_path, size, {:blob, encoded_placeholder}]
             ),
           :ok <- inject(opts, :after_placeholder),
           {:ok, summary} <- import_lines(conn, archived_path, digest, opts),
           :ok <- invoke_hook(opts, :after_import_lines, archived_path),
           :ok <- inject(opts, :after_import_lines),
           manifest <- manifest(source_path, archived_path, digest, size, summary),
           {:ok, encoded_manifest} <- RecordCodec.encode(:import_manifest, manifest),
           :ok <-
             Database.execute(
               conn,
               "UPDATE import_runs SET line_count = ?, valid_count = ?, invalid_count = ?, manifest = ? WHERE source_digest = ?",
               [summary.lines, summary.valid, summary.invalid, {:blob, encoded_manifest}, digest]
             ),
           :ok <- inject(opts, :after_manifest_update),
           :ok <- verify_digest(archived_path, digest),
           {:ok, ^manifest} <- Authority.read(conn, {:import, digest}) do
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
          {valid, error} = LegacyLine.classify(bytes)
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
    case Authority.read(conn, {:import, digest}) do
      {:ok, :absent} -> {:error, :not_found}
      {:ok, manifest} -> {:ok, manifest}
      {:error, _reason} = error -> error
    end
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
    temp = archived_path <> ".tmp-" <> String.slice(expected_digest, 0, 16)

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

  defp prepare_manifest_publication(path, manifest, txid) do
    directory = Path.dirname(path)
    name = Path.basename(path)
    temp = Path.join(directory, ".#{name}.#{txid}.tmp")
    intent = Path.join(directory, ".#{name}.#{txid}.intent")
    encoded = IO.iodata_to_binary([:json.encode(manifest), "\n"])
    expected_digest = Encoding.digest(encoded)

    with :ok <- validate_exact_temp(temp, encoded),
         :ok <- validate_exact_intent(intent, path, temp, expected_digest),
         :ok <- remove_exact_if_present(temp),
         :ok <- remove_exact_if_present(intent),
         :ok <- sync_directory(directory) do
      :ok
    end
  end

  defp validate_exact_temp(path, expected) do
    case read_exact_publication_file(path) do
      {:ok, ^expected} -> :ok
      {:ok, _other} -> {:error, {:publication_temp_mismatch, path}}
      :absent -> :ok
      {:error, reason} -> {:error, {:publication_temp_unavailable, path, reason}}
    end
  end

  defp validate_exact_intent(path, target, temp, expected_digest) do
    case read_exact_publication_file(path) do
      :absent ->
        :ok

      {:ok, bytes} ->
        try do
          case :json.decode(bytes) do
            %{
              "schema_version" => 1,
              "target" => ^target,
              "temp" => ^temp,
              "sha256" => ^expected_digest
            } = value
            when map_size(value) == 4 ->
              :ok

            _other ->
              {:error, {:publication_intent_mismatch, path}}
          end
        rescue
          _ -> {:error, {:publication_intent_mismatch, path}}
        catch
          _, _ -> {:error, {:publication_intent_mismatch, path}}
        end

      {:error, reason} ->
        {:error, {:publication_intent_unavailable, path, reason}}
    end
  end

  defp read_exact_publication_file(path) do
    case PathIdentity.existing(path) do
      {:ok, identity} ->
        with {:ok, bytes} <- File.read(path),
             :ok <- PathIdentity.revalidate(identity) do
          {:ok, bytes}
        end

      {:error, :database_not_found} ->
        :absent

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_exact_if_present(path) do
    case PathIdentity.existing(path) do
      {:ok, identity} ->
        with :ok <- PathIdentity.revalidate(identity),
             :ok <- File.rm(path) do
          :ok
        end

      {:error, :database_not_found} ->
        :ok

      {:error, reason} ->
        {:error, {:publication_cleanup_failed, path, reason}}
    end
  end

  defp inject(opts, point) do
    if Keyword.get(opts, :fail_at) == point,
      do: {:error, {:injected_import_interruption, point}},
      else: :ok
  end

  defp invoke_hook(opts, point, path) do
    case Keyword.get(opts, point) do
      nil -> :ok
      fun when is_function(fun, 1) -> fun.(path)
      _ -> {:error, :invalid_import_hook}
    end
  end

  defp ensure_archive_dir(path) do
    case PathIdentity.directory(path) do
      {:ok, _identity} -> :ok
      {:error, :enoent} -> create_archive_dir(path)
      {:error, {:database_parent_unavailable, :enoent}} -> {:error, :archive_parent_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_archive_dir(path) do
    with {:ok, identity} <- PathIdentity.new(path),
         :ok <- File.mkdir(identity.path),
         {:ok, _directory} <- PathIdentity.directory(identity.path) do
      :ok
    end
  end

  defp validate_paths(database, source, archive_dir, archived_path, manifest_path) do
    with {:ok, archive_root} <- PathIdentity.directory(archive_dir),
         {:ok, archive} <- import_target(archived_path),
         {:ok, manifest} <- import_target(manifest_path) do
      cond do
        pair_collision?([source, archive_root, archive, manifest]) ->
          {:error, :import_path_collision}

        true ->
          with :ok <- validate_planned_publication(database, source, archive, manifest) do
            {:ok, %{archive: archive, manifest: manifest}}
          end
      end
    end
  end

  defp validate_planned_publication(database, source, archive, manifest) do
    txid = String.slice(Path.basename(archive.path), 0, 16)
    manifest_dir = Path.dirname(manifest.path)
    manifest_name = Path.basename(manifest.path)

    planned_paths = [
      archive.path <> ".tmp-" <> txid,
      Path.join(manifest_dir, ".#{manifest_name}.#{txid}.tmp"),
      Path.join(manifest_dir, ".#{manifest_name}.#{txid}.intent")
    ]

    with {:ok, planned} <- target_identities(planned_paths),
         :ok <- PathIdentity.validate_publication(database, [source, archive, manifest | planned]) do
      :ok
    end
  end

  defp preflight_archive_root(database, source, archive_dir) do
    with {:ok, root} <- directory_target(archive_dir),
         :ok <- PathIdentity.validate_publication(database, [source, root]) do
      :ok
    end
  end

  defp directory_target(path) do
    case PathIdentity.directory(path) do
      {:ok, identity} -> {:ok, identity}
      {:error, :enoent} -> PathIdentity.new(path)
      {:error, reason} -> {:error, reason}
    end
  end

  defp target_identities(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case PathIdentity.target(path) do
        {:ok, identity} -> {:cont, {:ok, [identity | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp import_target(path) do
    PathIdentity.target(path)
  end

  defp pair_collision?(identities) do
    identities
    |> Enum.with_index()
    |> Enum.any?(fn {identity, index} ->
      identities
      |> Enum.drop(index + 1)
      |> Enum.any?(&PathIdentity.collision?(identity, &1))
    end)
  end
end
