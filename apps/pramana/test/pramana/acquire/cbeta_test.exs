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
