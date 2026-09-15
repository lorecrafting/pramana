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
  alias Pramana.Cbeta.Collections
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
  Builds the repository path for a CBETA work.

      iex> Pramana.Acquire.CBETA.work_path("T", 9, "0262")
      "T/T09/T09n0262.xml"

      iex> Pramana.Acquire.CBETA.work_path("A", 91, "1057")
      "A/A091/A091n1057.xml"

  The volume is *not* derivable from the work number — it is catalogue data — so it
  must be supplied. Guessing it would produce a confidently wrong citation, which is
  the failure mode this project exists to prevent.

  **How wide the volume number is, is also catalogue data**, and this function used to
  guess it: two digits, which is right for T, X and J and wrong for A, P, L and U. That
  produced `A/A91/A91n1057.xml` and two works failed to bake with `:enoent`. The bake was
  fixed by carrying the acquired path instead of rebuilding it (rule 50) and this
  function, which is still what single-work acquisition calls, was left guessing —
  rule 41, third time.

  It now takes the width from `Pramana.Cbeta.Collections.volume_token/2` and **raises for
  a collection whose width has not been checked against a real CBETA page**. Raising is
  the point: acquiring a new collection should stop here and make someone look, rather
  than fetch a 404 from a path that looks plausible.
  """
  @spec work_path(String.t(), pos_integer(), String.t()) :: String.t()
  def work_path(canon, volume, number) when is_integer(volume) do
    case Collections.volume_token(canon, volume) do
      nil ->
        raise ArgumentError, """
        no verified volume-number width for CBETA collection #{inspect(canon)}.

        The width is a property of the edition — T09 is two digits, A091 is three — so it
        cannot be guessed. Check one file's path in the CBETA repository, or the `id`
        attribute on a line at cbdata.dila.edu.tw/stable/juans?work=..., and add the
        collection to `Pramana.Cbeta.Collections`.

        Known: #{Enum.join(Collections.volume_token_known(), ", ")}
        """

      token ->
        "#{canon}/#{token}/#{token}n#{number}.xml"
    end
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

  # THE ONE STAGE THAT TOUCHES THE NETWORK, and the only one whose failures are somebody
  # else's. `bytes` is what distinguishes a slow link from a truncated response — the cache
  # that trusted `size > 0` and served a half-downloaded 1.2 GB tarball is rule 58.
  defp default_fetcher(url) do
    Pramana.Telemetry.span(
      [:pramana, :acquire, :fetch],
      fn -> fetch(url) end,
      fn
        {:ok, body} -> {%{bytes: byte_size(body)}, %{outcome: :ok, source: @source_id}}
        {:error, reason} -> {%{bytes: 0}, %{outcome: :error, reason: reason, source: @source_id}}
      end
    )
  end

  defp fetch(url) do
    case Req.get(url, headers: [{"user-agent", "pramana-acquire"}], max_retries: 3) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> {:ok, Jason.encode!(body)}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
