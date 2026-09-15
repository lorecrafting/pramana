defmodule Pramana.Paths do
  @moduledoc """
  Explicit project, repository and local-data roots for the sibling layout.

  Source/configuration belongs to `pramana/`. `PRAMANA_DATA_ROOT`, when set,
  selects existing local `raw/`, `priv/models/` and `sources/local/*/text/` without
  moving or copying them. It must be absolute. Relative provenance stays logical
  (`raw/...`), not tied to a checkout name. Explicit absolute source paths survive.
  """

  @project_root Path.expand("../../../..", __DIR__)
  @repository_root Path.expand("../../../../..", __DIR__)

  @spec project_root() :: String.t()
  def project_root, do: Application.get_env(:pramana, :project_root, @project_root)

  @spec repository_root() :: String.t()
  def repository_root, do: Application.get_env(:pramana, :repository_root, @repository_root)

  @spec project(String.t()) :: String.t()
  def project(path), do: Path.expand(path, project_root())

  @spec data_root() :: String.t()
  def data_root do
    case Application.get_env(:pramana, :data_root) || System.get_env("PRAMANA_DATA_ROOT") do
      nil ->
        ensure_explicit_legacy_choice!(project_root())
        project_root()

      :project ->
        # Test fixtures rebind :project_root. Never inherit an operator data root.
        project_root()

      root when is_binary(root) ->
        if Path.type(root) != :absolute or String.contains?(root, <<0>>) do
          raise ArgumentError, "PRAMANA_DATA_ROOT must be a nonempty absolute path"
        end

        Path.expand(root)

      _ ->
        raise ArgumentError, "data root must be :project or an absolute path"
    end
  end

  @spec data(String.t()) :: String.t()
  def data(path), do: Path.expand(path, data_root())

  @doc "Resolve a recorded source location; explicit absolute paths are unchanged."
  @spec source(String.t()) :: String.t()
  def source(path) do
    logical = String.replace(path, ~r/^(?:\.\/)+/, "")

    cond do
      Path.type(path) == :absolute -> path
      logical == "raw" or String.starts_with?(logical, "raw/") -> data(logical)
      true -> project(path)
    end
  end

  @doc "Keep raw provenance relative to its logical data root, even after relocation."
  @spec record_source(String.t()) :: String.t()
  def record_source(path) do
    absolute = Path.expand(path)
    logical = Path.relative_to(absolute, data_root())

    if logical == "raw" or String.starts_with?(logical, "raw/"),
      do: logical,
      else: absolute
  end

  @doc "Repository-managed local manifests and private text may have different roots."
  @spec local_text_dir(String.t()) :: String.t()
  def local_text_dir(dir) do
    absolute = Path.expand(dir)
    relative = Path.relative_to(absolute, project_root())

    if String.starts_with?(relative, "sources/local/") do
      data(Path.join(relative, "text"))
    else
      Path.join(absolute, "text")
    end
  end

  @doc false
  def ensure_explicit_legacy_choice!(project) do
    parent = Path.dirname(project)

    # Only recognize this repository's old layout, not an arbitrary parent folder.
    if File.regular?(Path.join(parent, "AGENTS.md")) and File.dir?(Path.join(parent, "foundry")) do
      legacy =
        Enum.filter(["raw", "priv/models", "priv/embed/.venv", "sources/local"], fn path ->
          nonempty_or_unreadable?(Path.join(parent, path))
        end)

      if legacy != [] do
        raise ArgumentError, """
        Legacy local data exists above the Pramana project: #{Enum.join(legacy, ", ")}.
        No files were moved. Explicitly choose PRAMANA_DATA_ROOT=#{parent} to keep using
        it, or PRAMANA_DATA_ROOT=#{project} for a separate project-local dataset.
        See docs/LAYOUT_MIGRATION.md at the repository root before running corpus work.
        """
      end
    end

    :ok
  end

  defp nonempty_or_unreadable?(path) do
    case File.ls(path) do
      {:ok, []} -> false
      {:ok, _entries} -> true
      {:error, :enoent} -> false
      {:error, _reason} -> true
    end
  end
end
