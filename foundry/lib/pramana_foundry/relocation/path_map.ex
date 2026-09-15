defmodule PramanaFoundry.Relocation.PathMap do
  @moduledoc """
  Versioned old-path mapping for historical evidence.

  Instead of mutating historical prompts, artifacts, or handoff records (which
  would invalidate immutable SHA-256 digests), historical paths are mapped
  through versioned mappings.
  """

  @schema_version 1

  defstruct [
    :relocation_id,
    :created_at,
    schema_version: @schema_version,
    mappings: []
  ]

  @type mapping :: %{
          source: binary(),
          destination: binary(),
          kind: :directory | :worktree
        }

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          relocation_id: binary(),
          created_at: binary(),
          mappings: [mapping()]
        }

  @doc """
  Creates a new PathMap instance.
  """
  @spec new(binary(), [mapping()], keyword()) :: t()
  def new(relocation_id, mappings \\ [], opts \\ []) do
    created_at =
      Keyword.get_lazy(opts, :created_at, fn ->
        DateTime.utc_now() |> DateTime.to_iso8601()
      end)

    normalized_mappings = Enum.map(mappings, &normalize_mapping/1)

    %__MODULE__{
      schema_version: @schema_version,
      relocation_id: relocation_id,
      created_at: created_at,
      mappings: normalized_mappings
    }
  end

  @doc """
  Adds a mapping from source to destination.
  """
  @spec add_mapping(t(), binary(), binary(), :directory | :worktree) :: t()
  def add_mapping(
        %__MODULE__{mappings: mappings} = path_map,
        source,
        destination,
        kind \\ :directory
      ) do
    new_m = normalize_mapping(%{source: source, destination: destination, kind: kind})
    %__MODULE__{path_map | mappings: mappings ++ [new_m]}
  end

  @doc """
  Resolves an old path using the mapping table. If the path was not moved, returns it unchanged.
  If multiple mappings match, matches the longest prefix.
  """
  @spec resolve(t() | Path.t(), binary()) :: binary()
  def resolve(%__MODULE__{mappings: mappings}, path) when is_binary(path) do
    norm_path = Path.expand(path)

    matching =
      mappings
      |> Enum.filter(fn %{source: src} ->
        path_matches_prefix?(norm_path, src)
      end)
      |> Enum.sort_by(fn %{source: src} -> byte_size(src) end, :desc)

    case matching do
      [%{source: src, destination: dst} | _] ->
        rel = Path.relative_to(norm_path, src)
        if rel == ".", do: dst, else: Path.join(dst, rel)

      [] ->
        norm_path
    end
  end

  def resolve(path_map_file, path) when is_binary(path_map_file) and is_binary(path) do
    case load(path_map_file) do
      {:ok, path_map} -> resolve(path_map, path)
      {:error, _} -> Path.expand(path)
    end
  end

  @doc """
  Reverse-resolves a new path back to its historical location.
  """
  @spec reverse_resolve(t(), binary()) :: binary()
  def reverse_resolve(%__MODULE__{mappings: mappings}, path) when is_binary(path) do
    norm_path = Path.expand(path)

    matching =
      mappings
      |> Enum.filter(fn %{destination: dst} ->
        path_matches_prefix?(norm_path, dst)
      end)
      |> Enum.sort_by(fn %{destination: dst} -> byte_size(dst) end, :desc)

    case matching do
      [%{source: src, destination: dst} | _] ->
        rel = Path.relative_to(norm_path, dst)
        if rel == ".", do: src, else: Path.join(src, rel)

      [] ->
        norm_path
    end
  end

  @doc """
  Saves the path map to a file atomically with fsync.
  """
  @spec save(t(), Path.t()) :: :ok | {:error, term()}
  def save(%__MODULE__{} = path_map, file_path) do
    data = to_map(path_map)
    encoded = IO.iodata_to_binary([:json.encode(data), "\n"])
    dir = Path.dirname(file_path)

    with :ok <- File.mkdir_p(dir),
         {:ok, file} <- :file.open(String.to_charlist(file_path), [:write, :binary, :raw]),
         :ok <- :file.write(file, encoded),
         :ok <- :file.sync(file),
         :ok <- :file.close(file) do
      :ok
    end
  end

  @doc """
  Loads a path map from a file.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, data} <- decode_json(content),
         {:ok, path_map} <- from_map(data) do
      {:ok, path_map}
    end
  end

  @doc """
  Chains an earlier PathMap with a later PathMap, so paths mapped in the earlier
  map continue to resolve through later relocations.
  """
  @spec chain(t(), t(), binary()) :: t()
  def chain(%__MODULE__{} = earlier, %__MODULE__{} = later, new_relocation_id) do
    chained_earlier =
      Enum.map(earlier.mappings, fn m ->
        resolved_dst = resolve(later, m.destination)
        %{m | destination: resolved_dst}
      end)

    combined = chained_earlier ++ later.mappings
    new(new_relocation_id, Enum.uniq_by(combined, &{&1.source, &1.destination}))
  end

  defp path_matches_prefix?(path, prefix) do
    path == prefix or String.starts_with?(path, prefix <> "/")
  end

  defp normalize_mapping(%{source: src, destination: dst} = m) do
    %{
      source: Path.expand(to_string(src)),
      destination: Path.expand(to_string(dst)),
      kind: Map.get(m, :kind, :directory)
    }
  end

  defp normalize_mapping(%{"source" => src, "destination" => dst} = m) do
    kind =
      case Map.get(m, "kind") do
        "worktree" -> :worktree
        :worktree -> :worktree
        _ -> :directory
      end

    %{
      source: Path.expand(to_string(src)),
      destination: Path.expand(to_string(dst)),
      kind: kind
    }
  end

  def to_map(%__MODULE__{} = pm) do
    %{
      "schema_version" => pm.schema_version,
      "relocation_id" => pm.relocation_id,
      "created_at" => pm.created_at,
      "mappings" =>
        Enum.map(pm.mappings, fn m ->
          %{
            "source" => m.source,
            "destination" => m.destination,
            "kind" => Atom.to_string(m.kind)
          }
        end)
    }
  end

  def from_map(%{"relocation_id" => rel_id, "mappings" => mappings} = data) do
    version = Map.get(data, "schema_version", 1)
    created_at = Map.get(data, "created_at", "")

    parsed_mappings =
      Enum.map(mappings, fn m ->
        kind =
          case m["kind"] do
            "worktree" -> :worktree
            _ -> :directory
          end

        %{
          source: m["source"],
          destination: m["destination"],
          kind: kind
        }
      end)

    {:ok,
     %__MODULE__{
       schema_version: version,
       relocation_id: rel_id,
       created_at: created_at,
       mappings: parsed_mappings
     }}
  end

  def from_map(_), do: {:error, :invalid_path_map_format}

  defp decode_json(content) do
    try do
      {:ok, :json.decode(content)}
    rescue
      _ -> {:error, :malformed_json}
    catch
      _, _ -> {:error, :malformed_json}
    end
  end
end
