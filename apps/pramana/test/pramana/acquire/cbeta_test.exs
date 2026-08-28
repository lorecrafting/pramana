defmodule Pramana.Acquire.CBETATest do
  use ExUnit.Case, async: false

  alias Pramana.Acquire.CBETA
  alias Pramana.Acquire.Lockfile

  setup do
    root = Path.join(System.tmp_dir!(), "pramana-cbeta-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:pramana, :project_root)
    Application.put_env(:pramana, :project_root, root)

    on_exit(fn ->
      File.rm_rf!(root)
      if prev, do: Application.put_env(:pramana, :project_root, prev)
    end)

    %{root: root}
  end

  # A stub fetcher: no test in this project touches the network.
  defp stub(responses), do: fn url -> respond(responses, url) end

  defp respond(responses, url) do
    responses
    |> Enum.find(fn {pattern, _} -> String.contains?(url, pattern) end)
    |> case do
      {_, {:error, reason}} -> {:error, reason}
      {_, body} -> {:ok, body}
      nil -> {:error, {:unexpected_url, url}}
    end
  end

  describe "work_path/3" do
    test "builds the CBETA repository path for a Taishō work" do
      assert CBETA.work_path("T", 9, "0262") == "T/T09/T09n0262.xml"
      assert CBETA.work_path("T", 84, "2688") == "T/T84/T84n2688.xml"
    end

    test "zero-pads the volume to two digits" do
      assert CBETA.work_path("T", 1, "0001") == "T/T01/T01n0001.xml"
    end

    # Two digits is the Taishō's width, not CBETA's. A/P/L/U use three, so this built
    # `A/A91/A91n1057.xml` and the fetch 404s on a path that looks entirely plausible.
    # Every expectation here is a path that exists in `sources.lock.json`.
    test "uses the width the COLLECTION uses, not the Taishō's" do
      assert CBETA.work_path("A", 91, "1057") == "A/A091/A091n1057.xml"
      assert CBETA.work_path("P", 154, "1519") == "P/P154/P154n1519.xml"
      assert CBETA.work_path("L", 130, "1557") == "L/L130/L130n1557.xml"
      assert CBETA.work_path("U", 205, "1368") == "U/U205/U205n1368.xml"
      assert CBETA.work_path("M", 59, "1540") == "M/M59/M59n1540.xml"
      assert CBETA.work_path("J", 31, "B271") == "J/J31/J31nB271.xml"
    end

    # Stopping is the correct behaviour for a collection nobody has checked. A guessed
    # path either 404s — confusing — or, worse, finds a file and cites it wrongly.
    test "raises for a collection whose width has never been checked" do
      assert_raise ArgumentError, ~r/no verified volume-number width/, fn ->
        CBETA.work_path("N", 1, "0001")
      end
    end
  end

  describe "resolve_pin/1" do
    test "extracts the commit sha" do
      fetcher = stub([{"commits/master", ~s({"sha":"abc123def"})}])
      assert {:ok, "abc123def"} = CBETA.resolve_pin(fetcher: fetcher)
    end

    test "surfaces an unexpected API response rather than guessing" do
      fetcher = stub([{"commits/master", ~s({"message":"Not Found"})}])
      assert {:error, :unexpected_api_response} = CBETA.resolve_pin(fetcher: fetcher)
    end

    test "propagates transport errors" do
      fetcher = stub([{"commits/master", {:error, :timeout}}])
      assert {:error, :timeout} = CBETA.resolve_pin(fetcher: fetcher)
    end
  end

  describe "fetch_paths/3" do
    @xml "<TEI xml:id=\"T09n0262\">妙法蓮華經</TEI>"

    test "writes raw/ and records the pin and hashes", %{root: root} do
      fetcher = stub([{"T09n0262.xml", @xml}])

      assert {:ok, %{pin: "sha1", refetched: true, files: [file]}} =
               CBETA.fetch_paths("sha1", ["T/T09/T09n0262.xml"], fetcher: fetcher)

      assert file.path == "T/T09/T09n0262.xml"
      assert file.sha256 == Lockfile.sha256(@xml)
      assert File.read!(Path.join([root, "raw", "cbeta", "T/T09/T09n0262.xml"])) == @xml

      assert {:ok, entry} = Lockfile.get_source("cbeta")
      assert entry["pin"] == %{"type" => "git", "commit" => "sha1"}
      assert entry["file_count"] == 1
    end

    test "is idempotent — a second run verifies instead of refetching", %{root: _root} do
      fetcher = stub([{"T09n0262.xml", @xml}])
      paths = ["T/T09/T09n0262.xml"]

      assert {:ok, %{refetched: true}} = CBETA.fetch_paths("sha1", paths, fetcher: fetcher)

      # A fetcher that would fail if called proves nothing was refetched.
      exploding = fn url -> {:error, {:should_not_have_fetched, url}} end
      assert {:ok, %{refetched: false}} = CBETA.fetch_paths("sha1", paths, fetcher: exploding)
    end

    test "refetches when the pin changes" do
      paths = ["T/T09/T09n0262.xml"]

      assert {:ok, %{refetched: true}} =
               CBETA.fetch_paths("sha1", paths, fetcher: stub([{"T09", @xml}]))

      assert {:ok, %{refetched: true, pin: "sha2"}} =
               CBETA.fetch_paths("sha2", paths, fetcher: stub([{"T09", @xml}]))
    end

    test "refetches when raw/ was tampered with", %{root: root} do
      paths = ["T/T09/T09n0262.xml"]

      assert {:ok, %{refetched: true}} =
               CBETA.fetch_paths("sha1", paths, fetcher: stub([{"T09", @xml}]))

      File.write!(Path.join([root, "raw", "cbeta", "T/T09/T09n0262.xml"]), "tampered")

      assert {:ok, %{refetched: true}} =
               CBETA.fetch_paths("sha1", paths, fetcher: stub([{"T09", @xml}]))

      assert File.read!(Path.join([root, "raw", "cbeta", "T/T09/T09n0262.xml"])) == @xml
    end

    test "reports which path failed rather than partially succeeding silently" do
      fetcher = stub([{"T09n0262.xml", @xml}, {"T09n0263.xml", {:error, :enoent}}])

      assert {:error, {:fetch_failed, "T/T09/T09n0263.xml", :enoent}} =
               CBETA.fetch_paths("sha1", ["T/T09/T09n0262.xml", "T/T09/T09n0263.xml"],
                 fetcher: fetcher
               )
    end
  end
end
