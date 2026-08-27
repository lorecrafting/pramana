defmodule Pramana.Acquire.CBETA do
  @moduledoc """
  Fetches CBETA TEI P5 sources into `raw/cbeta/`, pinned to an immutable git commit.

  The upstream repository is ~1.2 GB, so we fetch individual files rather than clone.
  CBETA stores one file per work: `T/T09/T09n0262.xml` holds all seven juan of the
  Lotus Sūtra.

  License: **non-commercial, header must remain intact** (`docs/SOURCES.md`). The TEI
  header carries that notice, which is one more reason normalization must not discard
  it.

  Network access is injected via the `:fetcher` option so tests never touch the wire.
  """

  @behaviour Pramana.Pipeline.Acquirer

  alias Pramana.Acquire.Lockfile
  alias Pramana.Sources

  @source_id "cbeta"
  @api "https://api.github.com"
  @raw "https://raw.githubusercontent.com"

  @type file_result :: %{path: String.t(), sha256: String.t(), bytes: non_neg_integer()}

  @doc """
  Resolves the current commit SHA of the upstream default branch.

  Acquisition pins to this SHA; every later fetch uses it, so a bake is reproducible
  even after upstream moves.
  """
  @spec resolve_pin(keyword()) :: {:ok, String.t()} | {:error, term()}
  def resolve_pin(opts \\ []) do
    {:ok, source} = Sources.fetch(@source_id)
    fetcher = fetcher(opts)
    branch = Keyword.get(opts, :branch, "master")

    with {:ok, body} <- fetcher.("#{@api}/repos/#{source.repo}/commits/#{branch}"),
         {:ok, %{"sha" => sha}} <- Jason.decode(body) do
      {:ok, sha}
    else
      {:ok, _} -> {:error, :unexpected_api_response}
      error -> error
    end
  end

  @doc """
  Resolves the upstream pin. Behaviour wrapper around `resolve_pin/1`.
  """
  @impl Pramana.Pipeline.Acquirer
  @spec pin(keyword()) :: {:ok, map()} | {:error, term()}
  def pin(opts \\ []) do
    with {:ok, sha} <- resolve_pin(opts) do
      {:ok, %{"type" => "git", "commit" => sha}}
    end
  end

  @doc """
  Where a target's bytes live under `raw/cbeta/`.

  A CBETA target is `%{canon:, volume:, number:}`. The volume is catalogue data and is
  not derivable from the work number, so it must be supplied — guessing it would
  produce a confidently wrong citation.
  """
  @impl Pramana.Pipeline.Acquirer
  @spec raw_path(map()) :: String.t()
  def raw_path(%{canon: canon, volume: volume, number: number}),
    do: work_path(canon, volume, number)

  @doc """
  Fetches targets at a pin, per the Acquirer behaviour.

  Distinct from `fetch_paths/3`: this takes a pin map and source-specific *targets*,
  which is the shape the pipeline speaks. `fetch_paths/3` is the CBETA-specific layer
  underneath that deals in repository paths.
  """
  @impl Pramana.Pipeline.Acquirer
  @spec fetch(map(), [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def fetch(%{"commit" => sha}, targets, opts) do
    fetch_paths(sha, Enum.map(targets, &raw_path/1), opts)
  end

  @doc """
  Builds the repository path for a Taishō work.

      iex> Pramana.Acquire.CBETA.work_path("T", 9, "0262")
      "T/T09/T09n0262.xml"

  The volume is *not* derivable from the work number — it is catalogue data — so it
  must be supplied. Guessing it would produce a confidently wrong citation, which is
  the failure mode this project exists to prevent.
  """
  @spec work_path(String.t(), pos_integer(), String.t()) :: String.t()
  def work_path(canon, volume, number) when is_integer(volume) do
    vol = volume |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{canon}/#{canon}#{vol}/#{canon}#{vol}n#{number}.xml"
  end

  @doc """
  Fetches the given repository paths at `sha` into `raw/cbeta/`, then records them in
  `sources.lock.json`.

  Idempotent: if the lockfile already covers the same pin and the files on disk still
  hash correctly, nothing is refetched.
  """
  @spec fetch_paths(String.t(), [String.t()], keyword()) ::
          {:ok, %{pin: String.t(), files: [file_result()], refetched: boolean()}}
          | {:error, term()}
  def fetch_paths(sha, paths, opts \\ []) when is_binary(sha) and is_list(paths) do
    {:ok, source} = Sources.fetch(@source_id)

    if up_to_date?(sha, paths),
      do: cached_result(sha),
      else: download_and_lock(source, sha, paths, opts)
  end

  defp cached_result(sha) do
    {:ok, entry} = Lockfile.get_source(@source_id)
    {:ok, %{pin: sha, files: entry["files"], refetched: false}}
  end

  # MERGE, never replace. CBETA is acquired one collection at a time, and each
  # collection is a separate run of this: writing the entry whole meant acquiring X
  # deleted the Taishō's 2,471 files from the lockfile, leaving a corpus that could not
  # be reproduced from `sources.lock.json`. See `Lockfile.merge_source/1`.
  defp download_and_lock(source, sha, paths, opts) do
    with {:ok, files} <- download_all(source, sha, paths, opts),
         entry = lock_entry(source, sha, files, opts),
         :ok <- Lockfile.merge_source(entry) do
      {:ok, %{pin: sha, files: files, refetched: true}}
    end
  end

  defp lock_entry(source, sha, files, opts) do
    Lockfile.build_entry(source,
      files: files,
      pin: %{"type" => "git", "commit" => sha},
      retrieved_at: Keyword.get(opts, :retrieved_at, DateTime.utc_now())
    )
  end

  defp up_to_date?(sha, paths) do
    with {:ok, entry} <- Lockfile.get_source(@source_id),
         true <- get_in(entry, ["pin", "commit"]) == sha,
         locked = MapSet.new(Enum.map(entry["files"], & &1["path"])),
         true <- MapSet.subset?(MapSet.new(paths), locked),
         {:ok, _count} <- Lockfile.verify(@source_id) do
      true
    else
      _ -> false
    end
  end

  defp download_all(source, sha, paths, opts) do
    fetcher = fetcher(opts)
    base = Path.join(Lockfile.raw_dir(), @source_id)

    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case fetcher.("#{@raw}/#{source.repo}/#{sha}/#{path}") do
        {:ok, body} ->
          target = Path.join(base, path)
          File.mkdir_p!(Path.dirname(target))
          File.write!(target, body)

          result = %{
            path: path,
            sha256: Lockfile.sha256(body),
            bytes: byte_size(body)
          }

          {:cont, {:ok, [result | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:fetch_failed, path, reason}}}
      end
    end)
    |> case do
      {:ok, files} -> {:ok, Enum.reverse(files)}
      error -> error
    end
  end

  defp fetcher(opts) do
    Keyword.get(opts, :fetcher, &default_fetcher/1)
  end

  defp default_fetcher(url) do
    case Req.get(url, headers: [{"user-agent", "pramana-acquire"}], max_retries: 3) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> {:ok, Jason.encode!(body)}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
