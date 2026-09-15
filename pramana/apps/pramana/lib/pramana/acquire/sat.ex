defmodule Pramana.Acquire.SAT do
  @moduledoc """
  Fetching the Taishō volumes 56–84 that CBETA does not publish.

  Volumes 56–84 are the Japanese-composed sectarian corpus, and only SAT publishes them.
  A request for a bulk copy went to the committee on 2026-08-15 and is unanswered; see
  `docs/sat-request-email.md`, which also carries the follow-up and the reasoning about
  what may and may not be fetched before a reply arrives.

  ## Two phases, and the order is forced

  **Metadata first, because the fetch list cannot be computed without it.** The reader is
  addressed as `satdb2018pre.php?...&useid={work}_{volume}_{page}` and answers with the
  whole *fascicle* containing that page — one probe returned 1,653 line ids spanning 19
  Taishō pages. Nothing in the catalogue says how many fascicles a work has, so the walk is
  adaptive: ask for page 1, read which pages came back, ask for the page after them.

  Phase 1 is also worth having on its own. Each IIIF manifest carries the work's title, its
  byline, its 部 division and its extent, so 541 manifests would let this corpus **name**
  every work it is missing rather than report a number — which is the doctrine
  `Pramana.Coverage` exists for.

  ## The catalogue was never actually blocked

  `docs/PLAN.md` recorded #41 as *"no source exists"*. SAT serves a browsable index at
  `/iiif/taisho/manifests/`, listing 5,750 manifests over 2,873 works, of which **541 fall
  in T2185–T2731 and span exactly volumes 56–84**. One request, no permission needed. It
  also corrected a figure this project had published: the "547 works" was `2731 - 2185 + 1`,
  the width of the number range, not a count.

  ## Licences differ between text and image, and the difference is load-bearing

      SAT text     CC BY-SA 4.0
      IIIF images  CC BY-NC-SA 4.0   <- non-commercial, and a different obligation

  This module fetches **text and manifest metadata only**. Nothing here requests a page
  image, and anything that later does inherits the more restrictive licence.

  ## Politeness is a parameter, not a default to be tuned away

  `robots.txt` on the host is served empty, which under the convention declares no
  restriction. That is permission in the mechanical sense and not in the one that matters:
  the letter of 2026-08-15 said this project would not crawl. `interval_ms` defaults to
  three seconds, every request identifies itself with a contact address, and the walk stops
  on the first non-200 rather than retrying into a service that may be trying to shed load.

  **A transport error is not a status code**, and the first run of this conflated them: 63
  manifests in, a pooled connection went stale and `%Req.TransportError{reason: :closed}`
  halted the run as though the server had refused. Those are retried once; a 403 or a 429
  still stops on the spot.
  """

  @host "https://21dzk.l.u-tokyo.ac.jp"
  @iiif "https://dzkimgs.l.u-tokyo.ac.jp/iiif/taisho/manifests"
  @contact "raymond.n.luong@gmail.com"
  @default_interval_ms 3_000

  @gap_first 2185
  @gap_last 2731

  @doc "The User-Agent every request carries. A crawl that cannot be contacted is anonymous."
  @spec user_agent() :: String.t()
  def user_agent do
    "pramana-research-bot/0.1 (non-commercial Buddhist studies retrieval; #{@contact})"
  end

  @doc """
  The work/volume pairs of the gap, parsed from a saved copy of SAT's manifest index.

  Reads a FILE rather than the network: the index is acquired once into `raw/` and pinned,
  so re-deriving the catalogue does not re-request anything.
  """
  @spec catalogue(Path.t()) :: {:ok, [{pos_integer(), pos_integer()}]} | {:error, term()}
  def catalogue(index_path) do
    with {:ok, html} <- File.read(index_path) do
      pairs =
        ~r/(\d+)_(\d+)_manifest\.json/
        |> Regex.scan(html)
        |> Enum.map(fn [_, w, v] -> {String.to_integer(w), String.to_integer(v)} end)
        |> Enum.filter(fn {work, _} -> work >= @gap_first and work <= @gap_last end)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, pairs}
    end
  end

  @doc "URL of one work's IIIF manifest."
  @spec manifest_url(pos_integer(), pos_integer()) :: String.t()
  def manifest_url(work, volume), do: "#{@iiif}/#{work}_#{volume}_manifest.json"

  @doc "URL of the reader page whose fascicle contains `page`."
  @spec fascicle_url(pos_integer(), pos_integer(), pos_integer()) :: String.t()
  def fascicle_url(work, volume, page) do
    useid = "#{work}_#{volume}_#{String.pad_leading(to_string(page), 4, "0")}"
    "#{@host}/SAT2018/satdb2018pre.php?mode=detail&ob=1&mode2=2&useid=#{useid}"
  end

  @doc """
  The interesting fields of a manifest, for a work this corpus cannot show.

  `label` is the title, `author` the byline as SAT prints it — `聖徳太子 撰`, which is the
  shape `Pramana.Authority` already parses — and `division` the 部 this project's own
  `Pramana.Taisho.Divisions` table names.
  """
  @spec summarize_manifest(map()) :: map()
  def summarize_manifest(manifest) do
    meta =
      manifest
      |> Map.get("metadata", [])
      |> Map.new(fn m -> {to_string(m["label"]), stringify(m["value"])} end)

    %{
      title: to_string(manifest["label"]),
      division: Map.get(meta, "分類"),
      author: meta |> Map.get("Author", "") |> String.trim(),
      translator: meta |> Map.get("Translator", "") |> String.trim(),
      pages: manifest |> get_in(["sequences", Access.at(0), "canvases"]) |> length_or_zero(),
      license: to_string(manifest["license"]),
      attribution: to_string(manifest["attribution"])
    }
  end

  defp stringify(v) when is_binary(v), do: v
  defp stringify([%{"@value" => v} | _]), do: v
  defp stringify(%{"@value" => v}), do: v
  defp stringify(v), do: to_string(inspect(v))

  defp length_or_zero(nil), do: 0
  defp length_or_zero(list), do: length(list)

  @doc """
  Fetches one URL, politely.

  Sleeps `interval_ms` BEFORE the request rather than after, so the pause cannot be skipped
  by an early return, and returns `{:error, {:status, code}}` on anything but 200 — the
  caller stops rather than retries. A transport-level failure is retried once, after the
  same interval; see `request/3`.
  """
  @spec get(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def get(url, opts \\ []) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    Process.sleep(interval)
    request(url, interval, Keyword.get(opts, :transport_retries, 1))
  end

  # A CLOSED SOCKET AND A 429 ARE NOT THE SAME EVENT, and treating them alike stopped a
  # 541-manifest run after 63 on 2026-08-30. `Req` pools connections, the server drops idle
  # ones, and at one request every three seconds the next request lands on a dead socket and
  # returns `%Req.TransportError{reason: :closed}`. That is connection lifecycle, not a
  # service asking to be left alone.
  #
  # So the two are split: a transport error is retried once, on a fresh connection. **Any
  # non-200 status still stops immediately and is never retried** — that is the case where
  # retrying would be the thing the 2026-08-15 letter promised not to do.
  defp request(url, interval, transport_retries) do
    case Req.get(url,
           headers: [{"user-agent", user_agent()}],
           max_retries: 0,
           receive_timeout: 60_000,
           pool_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:status, status}}

      {:error, %Req.TransportError{}} when transport_retries > 0 ->
        Process.sleep(interval)
        request(url, interval, transport_retries - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The Taishō number range these volumes occupy."
  @spec gap_range() :: Range.t()
  def gap_range, do: @gap_first..@gap_last
end
