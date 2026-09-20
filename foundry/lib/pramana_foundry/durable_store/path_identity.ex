defmodule PramanaFoundry.DurableStore.PathIdentity do
  @moduledoc false

  defstruct [
    :path,
    :mode,
    :major_device,
    :inode,
    :parent_major_device,
    :parent_inode,
    :basename
  ]

  @type t :: %__MODULE__{}

  def store_namespace(database_path) do
    owner = database_path <> ".owner.sqlite3"

    [
      database_path,
      database_path <> "-wal",
      database_path <> "-shm",
      database_path <> "-journal",
      owner,
      owner <> "-wal",
      owner <> "-shm",
      owner <> "-journal",
      database_path <> ".owner.unclean"
    ]
  end

  def validate_store_namespace(%__MODULE__{} = database) do
    recovered_prefix = database.path <> ".owner.unclean.recovered."

    with :ok <- revalidate(database),
         :ok <- validate_namespace_paths(store_namespace(database.path)),
         {:ok, names} <- File.ls(Path.dirname(database.path)),
         :ok <-
           names
           |> Enum.filter(&String.starts_with?(&1, Path.basename(recovered_prefix)))
           |> Enum.map(&Path.join(Path.dirname(database.path), &1))
           |> validate_namespace_paths() do
      :ok
    end
  end

  def validate_new_database(%__MODULE__{mode: :new} = target) do
    with :ok <-
           target.path
           |> store_namespace()
           |> Enum.reduce_while(:ok, fn path, :ok ->
             case File.lstat(path) do
               {:error, :enoent} -> {:cont, :ok}
               {:ok, _stat} -> {:halt, {:error, {:prospective_sidecar_exists, path}}}
               {:error, reason} ->
                 {:halt, {:error, {:sidecar_identity_unavailable, path, reason}}}
             end
           end),
         {:ok, names} <- File.ls(Path.dirname(target.path)),
         nil <-
           Enum.find(names, fn name ->
             String.starts_with?(
               name,
               Path.basename(target.path <> ".owner.unclean.recovered.")
             )
           end) do
      :ok
    else
      name when is_binary(name) ->
        {:error,
         {:prospective_sidecar_exists, Path.join(Path.dirname(target.path), name)}}

      {:error, _reason} = error ->
        error
    end
  end

  def validate_publication(%__MODULE__{} = database, candidates) when is_list(candidates) do
    with :ok <- validate_store_namespace(database),
         {:ok, protected} <- namespace_identities(database.path),
         false <- publication_pair_collision?(candidates),
         false <- Enum.any?(candidates, &reserved_family_collision?(database.path, &1.path)),
         false <-
           Enum.any?(candidates, fn candidate ->
             Enum.any?(protected, &collision?(candidate, &1))
           end) do
      :ok
    else
      true -> {:error, :store_path_collision}
      {:error, _reason} = error -> error
    end
  end

  def existing(path) do
    with {:ok, parts} <- raw_parts(path),
         {:ok, parent} <- walk_parent(parts),
         {:ok, leaf} <- File.lstat(path),
         :ok <- regular_single_link(leaf) do
      {:ok,
       %__MODULE__{
         path: path,
         mode: :existing,
         major_device: leaf.major_device,
         inode: leaf.inode,
         parent_major_device: parent.major_device,
         parent_inode: parent.inode,
         basename: List.last(parts)
       }}
    else
      {:error, :enoent} -> {:error, :database_not_found}
      {:error, _reason} = error -> error
    end
  end

  def new(path) do
    with {:ok, parts} <- raw_parts(path),
         {:ok, parent} <- walk_parent(parts),
         {:error, :enoent} <- File.lstat(path) do
      {:ok,
       %__MODULE__{
         path: path,
         mode: :new,
         parent_major_device: parent.major_device,
         parent_inode: parent.inode,
         basename: List.last(parts)
       }}
    else
      {:ok, _stat} -> {:error, :target_exists}
      {:error, _reason} = error -> error
    end
  end

  def target(path) do
    case existing(path) do
      {:ok, identity} -> {:ok, identity}
      {:error, :database_not_found} -> new(path)
      {:error, reason} -> {:error, reason}
    end
  end

  def directory(path) do
    with {:ok, parts} <- raw_parts(path),
         {:ok, _parent} <- walk_parent(parts),
         {:ok, %{type: :directory} = stat} <- File.lstat(path) do
      {:ok,
       %__MODULE__{
         path: path,
         mode: :directory,
         major_device: stat.major_device,
         inode: stat.inode,
         basename: List.last(parts)
       }}
    else
      {:ok, _stat} -> {:error, :path_not_directory}
      {:error, reason} -> {:error, reason}
    end
  end

  def directory(path) do
    with {:ok, parts} <- raw_parts(path),
         {:ok, _parent} <- walk_parent(parts),
         {:ok, %{type: :directory} = stat} <- File.lstat(path) do
      {:ok,
       %__MODULE__{
         path: path,
         mode: :directory,
         major_device: stat.major_device,
         inode: stat.inode,
         basename: List.last(parts)
       }}
    else
      {:ok, _stat} -> {:error, :path_not_directory}
      {:error, reason} -> {:error, reason}
    end
  end

  def revalidate(%__MODULE__{mode: :existing} = expected) do
    with {:ok, actual} <- existing(expected.path),
         true <- same?(expected, actual) do
      :ok
    else
      false -> {:error, :database_identity_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  def revalidate(%__MODULE__{mode: :new} = expected) do
    with {:ok, actual} <- new(expected.path),
         true <- same?(expected, actual) do
      :ok
    else
      false -> {:error, :database_identity_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  def same?(%__MODULE__{mode: :existing} = first, %__MODULE__{mode: :existing} = second) do
    first.major_device == second.major_device and first.inode == second.inode
  end

  def same?(%__MODULE__{mode: :directory} = first, %__MODULE__{mode: :directory} = second),
    do: first.major_device == second.major_device and first.inode == second.inode

  def same?(%__MODULE__{mode: :directory} = first, %__MODULE__{mode: :directory} = second),
    do: first.major_device == second.major_device and first.inode == second.inode

  def same?(%__MODULE__{mode: :new} = first, %__MODULE__{mode: :new} = second) do
    first.parent_major_device == second.parent_major_device and
      first.parent_inode == second.parent_inode and first.basename == second.basename
  end

  def same?(_first, _second), do: false

  def collision?(first, second) do
    same?(first, second) or first.path == second.path or
      String.downcase(first.path) == String.downcase(second.path)
  end

  def validate_sidecar(path) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, stat} -> regular_single_link(stat)
      {:error, reason} -> {:error, {:sidecar_identity_unavailable, reason}}
    end
  end

  defp validate_namespace_paths(paths) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case validate_sidecar(path) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_store_sidecar, path, reason}}}
      end
    end)
  end

  defp namespace_identities(database_path) do
    store_namespace(database_path)
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case target(path) do
        {:ok, identity} -> {:cont, {:ok, [identity | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reserved_family_collision?(database_path, candidate_path) do
    String.starts_with?(candidate_path, database_path <> ".owner.unclean.recovered.") or
      Enum.any?(store_namespace(candidate_path), fn path ->
        path in store_namespace(database_path) or
          String.starts_with?(path, database_path <> ".owner.unclean.recovered.")
      end)
  end

  defp publication_pair_collision?(identities) do
    identities
    |> Enum.with_index()
    |> Enum.any?(fn {identity, index} ->
      identities
      |> Enum.drop(index + 1)
      |> Enum.any?(&collision?(identity, &1))
    end)
  end

  defp raw_parts(path) when is_binary(path) and path != "" do
    parts = String.split(path, "/", trim: false)
    components = tl(parts)

    cond do
      not String.valid?(path) or :binary.match(path, <<0>>) != :nomatch ->
        {:error, :invalid_database_path}

      not String.starts_with?(path, "/") ->
        {:error, :database_path_not_absolute}

      components == [] or Enum.any?(components, &(&1 in ["", ".", ".."])) ->
        {:error, :noncanonical_database_path}

      "/" <> Enum.join(components, "/") != path ->
        {:error, :noncanonical_database_path}

      true ->
        {:ok, components}
    end
  end

  defp raw_parts(_path), do: {:error, :invalid_database_path}

  defp walk_parent(parts) do
    parts
    |> Enum.drop(-1)
    |> Enum.reduce_while({:ok, "/", File.lstat!("/")}, fn component, {:ok, path, _stat} ->
      next = if path == "/", do: path <> component, else: path <> "/" <> component

      case File.lstat(next) do
        {:ok, %{type: :directory} = stat} -> {:cont, {:ok, next, stat}}
        {:ok, %{type: :symlink}} -> {:halt, {:error, :database_parent_symlink_not_allowed}}
        {:ok, _stat} -> {:halt, {:error, :database_parent_not_directory}}
        {:error, reason} -> {:halt, {:error, {:database_parent_unavailable, reason}}}
      end
    end)
    |> case do
      {:ok, _path, stat} -> {:ok, stat}
      error -> error
    end
  end

  defp regular_single_link(%{type: :symlink}), do: {:error, :database_symlink_not_allowed}

  defp regular_single_link(%{type: type}) when type != :regular,
    do: {:error, :database_not_regular}

  defp regular_single_link(%{links: 1}), do: :ok

  defp regular_single_link(%{links: links}) when links > 1,
    do: {:error, :database_hardlink_not_allowed}

  defp regular_single_link(_stat), do: {:error, :database_identity_unavailable}
end
