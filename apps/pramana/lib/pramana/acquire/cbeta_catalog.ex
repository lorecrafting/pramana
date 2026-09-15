defmodule Pramana.Acquire.CBETA.Catalog do
  @moduledoc """
  Enumerates every work in the CBETA repository at a pinned commit.

  One recursive git-tree call returns all 5,005 XML blobs (not truncated), and the
  path pattern `CANON/CANONvv/CANONvvnNNNN.xml` holds for **every one of them** — so
  the catalog is derivable from paths alone, with no per-file requests and no
  hand-maintained index.

  Collections present: T (Taishō, 2,471 works), X (卍續藏, 1,236), J, B, ZW, and a
  dozen smaller ones. About 2.1 GB of XML in total.

  Deriving the catalogue from the tree rather than shipping a static list matters
  because the volume is **not** derivable from a work number — it is catalogue data,
  and guessing it would produce a confidently wrong citation.
  """

  @api "https://api.github.com"
  @path_pattern ~r{^(?<canon>[A-Z]+)/\k<canon>(?<vol>\d+)/\k<canon>\k<vol>n(?<number>[A-Za-z0-9]+)\.xml$}

  @type entry :: %{
          canon: String.t(),
          volume: pos_integer(),
          number: String.t(),
          work_id: String.t(),
          path: String.t(),
          bytes: non_neg_integer()
        }

  @doc """
  Fetches and parses the catalog at `sha`.

  Options:
    * `:canon`   — restrict to one collection or several: `"T"`, or `"K,A,P,L"`. Several
      matters because the archive path downloads the WHOLE repository tarball once per
      call, so acquiring seven small collections one at a time is seven downloads of the
      same ~2 GB for 74 works.
    * `:fetcher` — injected for tests; no test touches the network
  """
  @spec fetch(String.t(), keyword()) :: {:ok, [entry()]} | {:error, term()}
  def fetch(sha, opts \\ []) do
    fetcher = Keyword.get(opts, :fetcher, &default_fetcher/1)
    repo = Keyword.get(opts, :repo, "cbeta-org/xml-p5")

    with {:ok, body} <- fetcher.("#{@api}/repos/#{repo}/git/trees/#{sha}?recursive=1"),
         {:ok, tree} <- Jason.decode(body) do
      parse_tree(tree, opts)
    end
  end

  @doc """
  Parses an already-fetched git tree.

  A truncated tree is an ERROR, not a partial success. Silently baking a partial
  corpus is exactly the kind of failure that looks fine and produces missing-citation
  bugs much later.
  """
  @spec parse_tree(map(), keyword()) :: {:ok, [entry()]} | {:error, term()}
  def parse_tree(%{"truncated" => true}, _opts), do: {:error, :tree_truncated}

  def parse_tree(%{"tree" => nodes}, opts) do
    canon_filter = canon_filter(Keyword.get(opts, :canon))

    entries =
      nodes
      |> Enum.filter(&(&1["type"] == "blob" and String.ends_with?(&1["path"], ".xml")))
      |> Enum.flat_map(&parse_path(&1, canon_filter))
      |> Enum.sort_by(&{&1.canon, &1.volume, &1.number})

    {:ok, entries}
  end

  def parse_tree(_other, _opts), do: {:error, :unexpected_tree_response}

  # `nil` means every collection; a MapSet means these. Built once per call rather than
  # split per path, over 5,005 of them.
  defp canon_filter(nil), do: nil

  defp canon_filter(spec) when is_binary(spec) do
    case String.split(spec, ",", trim: true) do
      [] -> nil
      canons -> MapSet.new(canons, &String.trim/1)
    end
  end

  defp parse_path(%{"path" => path} = node, canon_filter) do
    case Regex.named_captures(@path_pattern, path) do
      nil ->
        # Not a work file. Reported by the caller rather than dropped silently.
        []

      %{"canon" => canon, "vol" => vol, "number" => number} ->
        if canon_filter && not MapSet.member?(canon_filter, canon) do
          []
        else
          [
            %{
              canon: canon,
              volume: String.to_integer(vol),
              number: number,
              work_id: "#{canon}#{number}",
              path: path,
              bytes: node["size"] || 0
            }
          ]
        end
    end
  end

  @doc """
  Paths in the tree that look like work files but do not parse.

  Surfaced so an unrecognised naming convention is visible rather than quietly
  reducing coverage.
  """
  @spec unparsed(map()) :: [String.t()]
  def unparsed(%{"tree" => nodes}) do
    nodes
    |> Enum.filter(&(&1["type"] == "blob" and String.ends_with?(&1["path"], ".xml")))
    |> Enum.map(& &1["path"])
    |> Enum.reject(&Regex.match?(@path_pattern, &1))
  end

  def unparsed(_), do: []

  defp default_fetcher(url) do
    case Req.get(url, headers: [{"user-agent", "pramana-acquire"}], max_retries: 3) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> {:ok, Jason.encode!(body)}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
