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
  def raw_dir, do: Pramana.Paths.data("raw")

  defp root do
    Pramana.Paths.project_root()
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
      # WHERE these paths are rooted, under `raw/`. Declared rather than inferred from the
      # id, because a source id names a PUBLICATION and a directory holds a CHECKOUT, and
      # those are not one-to-one: `sc`, `sc-data` and `sc-translations` are three sources
      # — three licences, three pins — extracted from one sparse checkout of bilara-data.
      # Inferring `raw/<id>/` left 4,998 files recorded at a path nothing was ever written
      # to, so `verify/1` reported them all missing and stayed permanently red. A check
      # that is always red is a check nobody reads.
      "raw_root" => Keyword.get(opts, :raw_root, source.id),
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

  @doc """
  Adds files to what a source already records, instead of replacing them.

  `put_source/1` writes a source entry whole, which is right for a source acquired in
  one pass and **wrong for one acquired a collection at a time**. Acquiring CBETA's X
  collection replaced the `cbeta` entry with X's 1,236 files and dropped the Taishō's
  2,471 — so a corpus holding 3,701 baked CBETA texts had a lockfile that could
  reproduce 1,230 of them. Nothing failed: `mix pramana.verify` re-derives from the
  file a text names on disk, `raw/` still held every byte, and `mix pramana.acquire`
  reported success. The one thing that broke is the invariant the lockfile exists for —
  *if a bake cannot be reproduced from `sources.lock.json`, it is not a bake* — and it
  broke silently.

  Files are merged by path, the incoming copy winning, and `files_sha256`/`file_count`
  are recomputed over the union so `bake_id` covers everything the source holds.

  A pin that has MOVED is handled by what the new fetch covers, not by refusing outright.
  The pin says which upstream commit these bytes came from, and one entry listing files
  fetched at two commits states something untrue about every one of them — so:

  - the incoming files cover every path already locked → the source really was
    re-acquired at the new commit, and the entry is replaced;
  - they do not → refused, because merging would leave the paths this fetch did not
    touch labelled with a commit they never came from. Re-acquire the whole source.
  """
  @spec merge_source(map()) :: :ok | {:error, {:pin_conflict, map(), map()}}
  def merge_source(entry) do
    case get_source(entry["id"]) do
      {:error, :not_locked} ->
        put_source(entry)

      {:ok, existing} ->
        cond do
          existing["files"] in [nil, []] -> put_source(entry)
          existing["pin"] == entry["pin"] -> put_source(merge_entries(existing, entry))
          supersedes?(existing, entry) -> put_source(entry)
          true -> {:error, {:pin_conflict, existing["pin"], entry["pin"]}}
        end
    end
  end

  defp supersedes?(existing, entry) do
    locked = MapSet.new(existing["files"], & &1["path"])
    incoming = MapSet.new(entry["files"], & &1["path"])
    MapSet.subset?(locked, incoming)
  end

  defp merge_entries(existing, entry) do
    files =
      (existing["files"] ++ entry["files"])
      |> Map.new(&{&1["path"], &1})
      |> Map.values()
      |> Enum.sort_by(& &1["path"])

    hashable = Enum.map(files, &%{path: &1["path"], sha256: &1["sha256"]})

    entry
    |> Map.put("files", files)
    |> Map.put("file_count", length(files))
    |> Map.put("files_sha256", manifest_hash(hashable))
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

  Files are resolved under `raw/<raw_root>/`, which the entry declares. Older entries
  without one fall back to the source id, which is what it always was.
  """
  @spec verify(String.t()) ::
          {:ok, non_neg_integer()} | {:error, :not_locked | {:mismatches, [map()]}}
  def verify(source_id) do
    with {:ok, entry} <- get_source(source_id) do
      base = Path.join(raw_dir(), entry["raw_root"] || source_id)

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
