defmodule PramanaFoundry.DurableStore.Owner do
  @moduledoc false

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Encoding, PathIdentity}

  defstruct [:conn, :marker_path, :epoch, :identity]

  def acquire(database_or_identity, opts \\ [])

  def acquire(%PathIdentity{} = identity, opts), do: acquire_identity(identity, opts)

  def acquire(database_path, opts) when is_binary(database_path) do
    with {:ok, identity} <- PathIdentity.existing(database_path),
         do: acquire_identity(identity, opts)
  end

  defp acquire_identity(identity, opts) do
    database_path = identity.path
    owner_path = database_path <> ".owner.sqlite3"
    marker_path = database_path <> ".owner.unclean"
    epoch = random_id()

    with :ok <- PathIdentity.revalidate(identity),
         :ok <- PathIdentity.validate_store_namespace(identity),
         :ok <- validate_recovery_archives(database_path),
         {:ok, conn} <- Sqlite3.open(owner_path) do
      result =
        with :ok <- Sqlite3.execute(conn, "PRAGMA busy_timeout = 0"),
             :ok <-
               Sqlite3.execute(
                 conn,
                 "CREATE TABLE IF NOT EXISTS owner_lock(id INTEGER PRIMARY KEY CHECK(id = 1))"
               ),
             :ok <- Sqlite3.execute(conn, "BEGIN EXCLUSIVE"),
             :ok <- PathIdentity.revalidate(identity),
             :ok <- resolve_previous_marker(marker_path, Keyword.get(opts, :recovery_evidence)),
             :ok <- durable_marker(marker_path, epoch) do
          {:ok,
           %__MODULE__{conn: conn, marker_path: marker_path, epoch: epoch, identity: identity}}
        end

      case result do
        {:ok, _owner} = ok ->
          ok

        {:error, reason} ->
          _ = Sqlite3.execute(conn, "ROLLBACK")
          _ = Sqlite3.close(conn)
          {:error, {:store_owner_unavailable, reason}}
      end
    else
      {:ok, conn} ->
        _ = Sqlite3.close(conn)
        {:error, :database_identity_changed}

      {:error, reason} ->
        {:error, {:store_owner_unavailable, reason}}
    end
  end

  def release(%__MODULE__{} = owner) do
    marker_result = remove_owned_marker(owner)
    commit_result = Sqlite3.execute(owner.conn, "COMMIT")
    close_result = Sqlite3.close(owner.conn)

    with :ok <- marker_result, :ok <- commit_result, :ok <- close_result, do: :ok
  end

  def sidecars(database_path) do
    database_path |> PathIdentity.store_namespace() |> tl()
  end

  defp resolve_previous_marker(marker_path, nil) do
    case File.read(marker_path) do
      {:error, :enoent} -> :ok
      {:ok, bytes} -> {:error, {:ambiguous_previous_owner, marker_path, Encoding.digest(bytes)}}
      {:error, reason} -> {:error, {:owner_marker_read_failed, reason}}
    end
  end

  defp resolve_previous_marker(marker_path, evidence)
       when is_binary(evidence) and evidence != "" do
    case File.read(marker_path) do
      {:error, :enoent} -> :ok
      {:ok, bytes} -> archive_previous_marker(marker_path, bytes, evidence)
      {:error, reason} -> {:error, {:owner_marker_read_failed, reason}}
    end
  end

  defp resolve_previous_marker(_marker_path, _evidence), do: {:error, :invalid_recovery_evidence}

  defp validate_recovery_archives(database_path) do
    directory = Path.dirname(database_path)
    prefix = Path.basename(database_path <> ".owner.unclean.recovered.")

    with {:ok, names} <- File.ls(directory) do
      names
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Enum.reduce_while(:ok, fn name, :ok ->
        digest = String.replace_prefix(name, prefix, "")
        path = Path.join(directory, name)

        with true <- byte_size(digest) == 64 and digest == String.downcase(digest),
             {:ok, identity} <- PathIdentity.existing(path),
             {:ok, bytes} <- File.read(path),
             [marker, evidence] <- :binary.split(bytes, "recovery_evidence="),
             true <- evidence != "" and String.ends_with?(evidence, "\n"),
             true <- Encoding.digest(marker) == digest,
             :ok <- PathIdentity.revalidate(identity) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:invalid_recovery_archive, path}}}
        end
      end)
    end
  end

  defp archive_previous_marker(marker_path, bytes, evidence) do
    digest = Encoding.digest(bytes)
    archive = marker_path <> ".recovered." <> digest
    record = IO.iodata_to_binary([bytes, "recovery_evidence=", evidence, "\n"])

    with {:ok, target} <- PathIdentity.target(archive) do
      case target.mode do
        :new ->
          case File.open(archive, [:write, :binary, :exclusive]) do
            {:ok, file} ->
              result = with :ok <- IO.binwrite(file, record), do: :file.sync(file)
              close_result = File.close(file)

              with :ok <- result,
                   :ok <- close_result,
                   {:ok, written} <- PathIdentity.existing(archive),
                   :ok <- PathIdentity.revalidate(written),
                   :ok <- remove_exact_marker(marker_path, bytes) do
                :ok
              end

            {:error, reason} ->
              {:error, reason}
          end

        :existing ->
          with :ok <- PathIdentity.revalidate(target),
               {:ok, ^record} <- File.read(archive),
               :ok <- remove_exact_marker(marker_path, bytes) do
            :ok
          else
            {:ok, _other} -> {:error, :recovery_archive_mismatch}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  defp durable_marker(path, epoch) do
    bytes = marker_bytes(epoch)

    with {:ok, file} <- File.open(path, [:write, :binary, :exclusive]),
         :ok <- IO.binwrite(file, bytes),
         :ok <- :file.sync(file),
         :ok <- File.close(file) do
      :ok
    end
  end

  defp remove_owned_marker(owner) do
    remove_exact_marker(owner.marker_path, marker_bytes(owner.epoch))
  end

  defp remove_exact_marker(path, expected) do
    with {:ok, identity} <- PathIdentity.existing(path),
         {:ok, ^expected} <- File.read(path),
         :ok <- PathIdentity.revalidate(identity),
         :ok <- File.rm(path) do
      :ok
    else
      {:ok, _other} -> {:error, :replacement_owner_marker}
      {:error, reason} -> {:error, reason}
    end
  end

  defp marker_bytes(epoch), do: "schema_version=1\nepoch=#{epoch}\npid=#{System.pid()}\n"

  defp random_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
