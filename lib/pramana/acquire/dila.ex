defmodule Pramana.Acquire.DILA do
  @moduledoc """
  Fetches DILA's authority databases — reference data about people and places, not corpus.

  `DILA-edu/Authority-Databases`, CC BY-SA 3.0, pinned by commit. Three files are declared
  and each is fetched only if the lockfile does not already hold it at the pinned commit
  with a matching hash.

  ## This is a source acquired in PARTS, which is the whole reason for the care here

  The person file was acquired alone; place and districts came later. `Lockfile.merge_source/1`
  rather than `put_source/1` — writing the entry whole is how acquiring CBETA's X collection
  deleted the Taishō's 2,471 file records and left a corpus that could not be reproduced from
  `sources.lock.json`. Rule 43.

  **And the pin is READ, not resolved.** Fetching at whatever `master` points to today would
  put files from two different commits under one pin, which states something untrue about
  every one of them — `merge_source/1` refuses that outright. So an already-locked source is
  extended at the commit it was locked at, and moving the pin is a deliberate act:
  `--pin <sha>` re-acquires every declared file at the new commit, which is the only way the
  entry stays honest.

  ## What is here, and what is not

  `authority_time/` and `authority_catalog/` exist in the repository as README files with no
  data at this pin. They are absent from `@files` for that reason and not because nobody got
  to them — `Pramana.Sources` names this source *"(person, place, time)"*, and that name is
  a promise the upstream does not keep.

  ## Not shared with `Pramana.Acquire.CBETA`, deliberately

  The download-and-lock mechanics here are close to that module's, and extracting them was
  rejected for now: CBETA's acquirer is load-bearing and gate-verified, and refactoring it in
  the same change that adds a second source is the coupling this project's rules warn about.
  **Extract when a third source needs it, or the first time a fix lands in one and not the
  other** — that second condition is rule 41, and it is the one that will actually fire.
  """

  alias Pramana.Acquire.Lockfile
  alias Pramana.Sources

  @source_id "dila-authority"
  @raw "https://raw.githubusercontent.com"
  @api "https://api.github.com/repos"

  # Declared here rather than passed in: what this source consists of is a fact about the
  # source, and a caller free to fetch a subset is a caller free to record a partial one.
  @files [
    "authority_person/Buddhist_Studies_Person_Authority.xml",
    "authority_place/Buddhist_Studies_Place_Authority.xml",
    "authority_place/districts.xml"
  ]

  @doc "Every file this source declares, in fetch order."
  @spec files() :: [String.t()]
  def files, do: @files

  @doc """
  Fetches whatever is missing, at the commit this source is already pinned to.

  Returns `{:ok, %{pin: sha, fetched: [path], skipped: [path]}}`. Passing `pin: sha` moves
  the pin and re-fetches everything, which is the only honest way to change it.
  """
  @spec fetch(keyword()) ::
          {:ok, %{pin: String.t(), fetched: [String.t()], skipped: [String.t()]}}
          | {:error, term()}
  def fetch(opts \\ []) do
    with {:ok, source} <- Sources.fetch(@source_id),
         {:ok, pin, locked} <- pin_and_locked(opts) do
      {skip, fetch} = Enum.split_with(@files, &(&1 in locked))

      case download(source, pin, fetch, opts) do
        {:ok, []} -> {:ok, %{pin: pin, fetched: [], skipped: skip}}
        {:ok, downloaded} -> lock(source, pin, downloaded, skip, opts)
        error -> error
      end
    end
  end

  # MERGE, never replace — `Lockfile.merge_source/1` and rule 43. Writing the entry whole is
  # how acquiring CBETA's X collection deleted the Taishō's 2,471 file records.
  defp lock(source, pin, downloaded, skip, opts) do
    entry =
      Lockfile.build_entry(source,
        files: downloaded,
        pin: %{"type" => "git", "commit" => pin},
        retrieved_at: Keyword.get(opts, :retrieved_at, DateTime.utc_now())
      )

    with :ok <- Lockfile.merge_source(entry) do
      {:ok, %{pin: pin, fetched: Enum.map(downloaded, & &1.path), skipped: skip}}
    end
  end

  # An explicit `--pin` re-fetches everything; otherwise the locked pin wins and only the
  # missing files are fetched. `Lockfile.verify/1` decides what "already held" means, so a
  # file edited by hand in `raw/` is refetched rather than trusted — invariant #3.
  defp pin_and_locked(opts) do
    case {Keyword.get(opts, :pin), Lockfile.get_source(@source_id)} do
      {pin, _} when is_binary(pin) ->
        {:ok, pin, []}

      {nil, {:ok, entry}} ->
        locked =
          case Lockfile.verify(@source_id) do
            {:ok, _} -> Enum.map(entry["files"] || [], & &1["path"])
            {:error, _} -> []
          end

        {:ok, get_in(entry, ["pin", "commit"]), locked}

      {nil, {:error, :not_locked}} ->
        resolve_pin(opts)
    end
  end

  @doc "Resolves the repository's current default-branch commit."
  @spec resolve_pin(keyword()) :: {:ok, String.t(), []} | {:error, term()}
  def resolve_pin(opts \\ []) do
    {:ok, source} = Sources.fetch(@source_id)

    case fetcher(opts).("#{@api}/#{source.repo}/commits/master") do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"sha" => sha}} when is_binary(sha) -> {:ok, sha, []}
          _ -> {:error, :unexpected_api_response}
        end

      error ->
        error
    end
  end

  defp download(_source, _pin, [], _opts), do: {:ok, []}

  defp download(source, pin, paths, opts) do
    fetcher = fetcher(opts)
    base = Path.join(Lockfile.raw_dir(), @source_id)

    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case fetcher.("#{@raw}/#{source.repo}/#{pin}/#{path}") do
        {:ok, body} ->
          target = Path.join(base, path)
          File.mkdir_p!(Path.dirname(target))
          File.write!(target, body)

          {:cont,
           {:ok, [%{path: path, sha256: Lockfile.sha256(body), bytes: byte_size(body)} | acc]}}

        {:error, reason} ->
          # Names the path. A partial acquisition that reports only "failed" leaves nobody
          # able to tell which of three files is missing.
          {:halt, {:error, {:fetch_failed, path, reason}}}
      end
    end)
    |> case do
      {:ok, files} -> {:ok, Enum.reverse(files)}
      error -> error
    end
  end

  defp fetcher(opts), do: Keyword.get(opts, :fetcher, &default_fetcher/1)

  # These files are tens of megabytes; `receive_timeout` is raised well above Req's default
  # because a 31 MB body over a slow link otherwise fails as a timeout, which reads like an
  # outage rather than like a large file.
  # THE ONE STAGE THAT TOUCHES THE NETWORK, and the only one whose failures are somebody
  # else's. `bytes` is what distinguishes a slow link from a truncated response — the cache
  # that trusted `size > 0` and served a half-downloaded 1.2 GB tarball is rule 58.
  defp default_fetcher(url) do
    Pramana.Telemetry.span(
      [:pramana, :acquire, :fetch],
      fn -> http_get(url) end,
      fn
        {:ok, body} -> {%{bytes: byte_size(body)}, %{outcome: :ok, source: @source_id}}
        {:error, reason} -> {%{bytes: 0}, %{outcome: :error, reason: reason, source: @source_id}}
      end
    )
  end

  defp http_get(url) do
    case Req.get(url,
           headers: [{"user-agent", "pramana-acquire"}],
           max_retries: 3,
           receive_timeout: 300_000
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> {:ok, Jason.encode!(body)}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
