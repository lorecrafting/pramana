defmodule Pramana.Acquire.Lockfile do
  @moduledoc """
  Read, write, and verify `sources.lock.json` — the record of exactly which upstream
  bytes a bake was built from.

  See `docs/ARCHITECTURE.md`, "Stage 0 — Acquire". This file is what makes invariant
  #3 in `CLAUDE.md` enforceable: *if a bake can't be reproduced from
  `sources.lock.json`, it's not a bake.* It also feeds `bake_id`, so two people with
  the same lockfile and pipeline version hold byte-identical corpora.
  """

  alias Pramana.Sources

  @schema_version 1

  @type entry :: %{
          required(:path) => String.t(),
          required(:sha256) => String.t(),
          required(:bytes) => non_neg_integer()
        }

  @doc "Default lockfile path, relative to the umbrella root."
  @spec path() :: String.t()
  def path, do: Path.join(root(), "sources.lock.json")

  @doc "The `raw/` directory. Append-only; never edited, never committed."
  @spec raw_dir() :: String.t()
  def raw_dir, do: Path.join(root(), "raw")

  defp root do
    Application.get_env(:pramana, :project_root) || File.cwd!()
  end

  @doc """
  Builds a lockfile source entry.

  `files` must be a list of `%{path:, sha256:, bytes:}`, where `path` is relative to
  `raw/<source_id>/`.
  """
  @spec build_entry(Sources.t(), keyword()) :: map()
  def build_entry(source, opts) do
    files = opts |> Keyword.fetch!(:files) |> Enum.sort_by(& &1.path)
    pin = Keyword.fetch!(opts, :pin)
    retrieved_at = Keyword.get(opts, :retrieved_at, DateTime.utc_now())

    %{
      "id" => source.id,
      "name" => source.name,
      "upstream" => source.upstream_url,
      "pin" => pin,
      "retrieved_at" => DateTime.to_iso8601(retrieved_at),
      "license" => %{
        "spdx" => source.license.spdx,
        "class" => source.license.class,
        "commercial_use" => source.license.commercial_use,
        "redistributable" => source.license.redistributable
      },
      "file_count" => length(files),
      "files_sha256" => manifest_hash(files),
      "files" =>
        Enum.map(files, fn f ->
          %{"path" => f.path, "sha256" => f.sha256, "bytes" => f.bytes}
        end)
    }
  end

  @doc """
  A single hash covering an entire file set.

  Computed over sorted `path:sha256` lines, so it is stable regardless of the order
  files were fetched in. This is the value that feeds `bake_id` — reordering a
  download must not change the identity of a corpus.
  """
  @spec manifest_hash([entry()]) :: String.t()
  def manifest_hash(files) do
    files
    |> Enum.sort_by(& &1.path)
    |> Enum.map_join("\n", fn f -> "#{f.path}:#{f.sha256}" end)
    |> sha256()
  end

  @doc "Hex-encoded SHA-256 of a binary."
  @spec sha256(binary()) :: String.t()
  def sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  @doc "Reads the lockfile, returning an empty skeleton when absent."
  @spec read() :: {:ok, map()} | {:error, term()}
  def read do
    case File.read(path()) do
      {:ok, contents} -> Jason.decode(contents)
      {:error, :enoent} -> {:ok, empty()}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Writes or replaces a single source entry, leaving other sources untouched."
  @spec put_source(map()) :: :ok | {:error, term()}
  def put_source(entry) do
    with {:ok, lock} <- read() do
      others = Enum.reject(lock["sources"] || [], &(&1["id"] == entry["id"]))
      sources = Enum.sort_by([entry | others], & &1["id"])
      write(%{lock | "sources" => sources})
    end
  end

  @doc "Fetches one source entry from the lockfile."
  @spec get_source(String.t()) :: {:ok, map()} | {:error, :not_locked}
  def get_source(source_id) do
    with {:ok, lock} <- read() do
      case Enum.find(lock["sources"] || [], &(&1["id"] == source_id)) do
        nil -> {:error, :not_locked}
        entry -> {:ok, entry}
      end
    end
  end

  @doc """
  Re-hashes every file recorded for a source and compares against the lockfile.

  This is what makes acquisition idempotent and tamper-evident: a second
  `mix pramana.acquire` verifies rather than blindly refetching, and any edit to
  `raw/` is detected. `raw/` being append-only is an invariant, not a convention.

  Returns `{:ok, count}` or `{:error, {:mismatches, [...]}}`.
  """
  @spec verify(String.t()) ::
          {:ok, non_neg_integer()} | {:error, :not_locked | {:mismatches, [map()]}}
  def verify(source_id) do
    with {:ok, entry} <- get_source(source_id) do
      base = Path.join(raw_dir(), source_id)

      mismatches =
        entry["files"]
        |> Enum.map(fn f -> {f, Path.join(base, f["path"])} end)
        |> Enum.flat_map(fn {f, abs_path} -> check_file(f, abs_path) end)

      if mismatches == [] do
        {:ok, length(entry["files"])}
      else
        {:error, {:mismatches, mismatches}}
      end
    end
  end

  defp check_file(f, abs_path) do
    case File.read(abs_path) do
      {:ok, bytes} ->
        actual = sha256(bytes)

        if actual == f["sha256"],
          do: [],
          else: [
            %{path: f["path"], reason: :hash_mismatch, expected: f["sha256"], actual: actual}
          ]

      {:error, reason} ->
        [%{path: f["path"], reason: reason}]
    end
  end

  defp write(lock) do
    File.write(path(), Jason.encode!(lock, pretty: true) <> "\n")
  end

  defp empty, do: %{"bake_schema" => @schema_version, "sources" => []}
end
