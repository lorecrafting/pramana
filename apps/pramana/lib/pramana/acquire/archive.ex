defmodule Pramana.Acquire.Archive do
  @moduledoc """
  Bulk acquisition: one tarball at a pinned commit, rather than thousands of requests.

  CBETA has 5,005 work files. Fetching them individually is thousands of round trips
  and invites rate limiting; GitHub serves the whole repository at an exact commit as a
  single archive, which is one request and far faster.

  The lockfile guarantee is unchanged: every extracted file is hashed on the way in, so
  `mix pramana.verify` still detects any later edit. The archive is a transport
  optimisation, not a weakening of provenance.
  """

  alias Pramana.Acquire.Lockfile

  require Logger

  @codeload "https://codeload.github.com"

  @doc """
  Downloads and extracts the repository archive at `sha` into `raw/<source_id>/`.

  Only paths in `keep` are extracted, so restricting to one canon does not cost disk.
  Returns the per-file results the lockfile needs.
  """
  @spec fetch(String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def fetch(source_id, sha, keep, opts \\ []) do
    repo = Keyword.fetch!(opts, :repo)
    url = "#{@codeload}/#{repo}/tar.gz/#{sha}"
    tmp = Path.join(System.tmp_dir!(), "pramana-#{source_id}-#{sha}.tar.gz")

    with :ok <- download(url, tmp, opts) do
      result = extract(source_id, sha, tmp, keep, repo)
      File.rm(tmp)
      result
    end
  end

  defp download(url, target, opts) do
    if File.exists?(target) and File.stat!(target).size > 0 do
      Logger.info("archive already downloaded: #{target}")
      :ok
    else
      Logger.info("downloading #{url}")

      case Keyword.get(opts, :downloader, &default_download/2).(url, target) do
        :ok -> :ok
        {:error, reason} -> {:error, {:download_failed, reason}}
      end
    end
  end

  defp default_download(url, target) do
    case Req.get(url, into: File.stream!(target), max_retries: 3, receive_timeout: 600_000) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # GitHub archives nest everything under "<repo>-<sha>/", which is stripped so that
  # raw/ layout matches the repository layout and lockfile paths stay stable across
  # pins. Otherwise every re-pin would rewrite every path.
  defp extract(source_id, sha, archive, keep, repo) do
    base = Path.join(Lockfile.raw_dir(), source_id)
    File.mkdir_p!(base)
    prefix = "#{repo |> String.split("/") |> List.last()}-#{sha}/"
    wanted = MapSet.new(keep)

    Logger.info("extracting #{MapSet.size(wanted)} file(s)")

    case :erl_tar.extract(archive, [:compressed, :memory]) do
      {:ok, files} ->
        results =
          files
          |> Enum.flat_map(&write_wanted(&1, prefix, wanted, base))
          |> Enum.sort_by(& &1.path)

        report_missing(wanted, results)
        {:ok, results}

      {:error, reason} ->
        {:error, {:extract_failed, reason}}
    end
  end

  defp write_wanted({name, contents}, prefix, wanted, base) do
    path = name |> List.to_string() |> String.replace_prefix(prefix, "")

    if MapSet.member?(wanted, path) do
      target = Path.join(base, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, contents)

      [%{path: path, sha256: Lockfile.sha256(contents), bytes: byte_size(contents)}]
    else
      []
    end
  end

  # A requested file absent from the archive means the catalog and the archive
  # disagree. Loud, because a quietly smaller corpus is the failure that shows up
  # later as an unexplainable missing citation.
  defp report_missing(wanted, results) do
    got = MapSet.new(results, & &1.path)
    missing = MapSet.difference(wanted, got)

    if MapSet.size(missing) > 0 do
      Logger.error(
        "#{MapSet.size(missing)} catalogued file(s) absent from the archive: " <>
          inspect(Enum.take(missing, 5))
      )
    end
  end
end
