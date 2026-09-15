defmodule Pramana.Acquire.DILATest do
  @moduledoc """
  A source acquired in PARTS, which is the only interesting thing about it.

  The person file was fetched alone and the place files came later. Every test here is about
  that: the pin is read rather than resolved, already-held files are not refetched, and the
  merge must not drop what an earlier run recorded. That last one is rule 43, and it is not
  hypothetical — acquiring CBETA's X collection replaced the `cbeta` entry and deleted the
  Taishō's 2,471 file records, leaving a corpus of 3,701 texts with a lockfile that could
  reproduce 1,230.
  """
  use ExUnit.Case, async: false

  alias Pramana.Acquire.DILA
  alias Pramana.Acquire.Lockfile

  setup do
    root = Path.join(System.tmp_dir!(), "pramana-dila-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:pramana, :project_root)
    Application.put_env(:pramana, :project_root, root)

    on_exit(fn ->
      File.rm_rf!(root)

      if prev,
        do: Application.put_env(:pramana, :project_root, prev),
        else: Application.delete_env(:pramana, :project_root)
    end)

    %{root: root}
  end

  # No test in this project touches the network.
  defp stub(bodies), do: fn url -> respond(bodies, url) end

  defp respond(bodies, url) do
    bodies
    |> Enum.find(fn {pattern, _} -> String.contains?(url, pattern) end)
    |> case do
      {_, {:error, reason}} -> {:error, reason}
      {_, body} -> {:ok, body}
      # An unstubbed URL is a failure with the URL in it, not a silent nil — a stub that
      # answers everything cannot prove that nothing was refetched.
      nil -> {:error, {:unexpected_url, url}}
    end
  end

  defp all_files, do: Enum.map(DILA.files(), &{Path.basename(&1), "<TEI>#{&1}</TEI>"})

  defp exploding, do: fn url -> {:error, {:should_not_have_fetched, url}} end

  describe "files/0" do
    test "declares person and place, and NOT time or catalog" do
      files = DILA.files()

      assert Enum.any?(files, &String.contains?(&1, "authority_person/"))
      assert Enum.any?(files, &String.contains?(&1, "authority_place/"))

      # `authority_time/` and `authority_catalog/` are README files with no data at this
      # pin. Declaring them would fail every acquisition over a promise upstream does not
      # keep.
      refute Enum.any?(files, &String.contains?(&1, "authority_time/"))
      refute Enum.any?(files, &String.contains?(&1, "authority_catalog/"))
    end
  end

  describe "fetch/1" do
    test "writes raw/ and records every declared file", %{root: root} do
      assert {:ok, %{pin: "sha1", fetched: fetched, skipped: []}} =
               DILA.fetch(pin: "sha1", fetcher: stub(all_files()))

      assert length(fetched) == length(DILA.files())

      for path <- DILA.files() do
        assert File.exists?(Path.join([root, "raw", "dila-authority", path]))
      end

      assert {:ok, entry} = Lockfile.get_source("dila-authority")
      assert entry["pin"] == %{"type" => "git", "commit" => "sha1"}
      assert entry["file_count"] == length(DILA.files())
    end

    test "a second run refetches nothing" do
      assert {:ok, %{fetched: [_ | _]}} = DILA.fetch(pin: "sha1", fetcher: stub(all_files()))

      # A fetcher that fails if called at all is the proof.
      assert {:ok, %{fetched: [], skipped: skipped}} = DILA.fetch(fetcher: exploding())
      assert length(skipped) == length(DILA.files())
    end

    test "reads the locked pin rather than resolving a new one" do
      assert {:ok, _} = DILA.fetch(pin: "sha1", fetcher: stub(all_files()))

      # No `commits/master` entry in the stub: resolving would raise `:unexpected_url`.
      # Fetching at whatever master points to today would put two commits under one pin.
      assert {:ok, %{pin: "sha1"}} = DILA.fetch(fetcher: exploding())
    end

    test "RULE 43: adding a file keeps what an earlier run recorded", %{root: root} do
      [person | rest] = DILA.files()
      body = "<TEI>#{person}</TEI>"

      # First run: the person file alone, exactly how this source was actually acquired.
      # Written to raw/ as well as recorded — a lockfile entry whose bytes are absent is a
      # tampered source, and `fetch/1` correctly refetches rather than trusting the record,
      # which is invariant #3 and is why an earlier version of this test failed.
      target = Path.join([root, "raw", "dila-authority", person])
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, body)

      {:ok, source} = Pramana.Sources.fetch("dila-authority")

      :ok =
        Lockfile.put_source(
          Lockfile.build_entry(source,
            files: [%{path: person, sha256: Lockfile.sha256(body), bytes: byte_size(body)}],
            pin: %{"type" => "git", "commit" => "sha1"}
          )
        )

      # Second run at the same pin adds the place files.
      assert {:ok, %{fetched: fetched}} = DILA.fetch(fetcher: stub(all_files()))

      assert {:ok, entry} = Lockfile.get_source("dila-authority")
      locked = Enum.map(entry["files"], & &1["path"])

      # The person file's record survived, and so did the two new ones.
      assert person in locked
      for path <- rest, do: assert(path in locked)
      assert entry["file_count"] == length(DILA.files())
      # It was not refetched — its hash was already recorded and verified.
      refute person in fetched
    end

    test "refetches a file that was edited in raw/, rather than trusting the lockfile", %{
      root: root
    } do
      assert {:ok, _} = DILA.fetch(pin: "sha1", fetcher: stub(all_files()))

      [person | _] = DILA.files()
      File.write!(Path.join([root, "raw", "dila-authority", person]), "tampered")

      # `raw/` is append-only and never edited (invariant #3). A mismatch means the bytes on
      # disk are not the bytes the lockfile names, and the fix is to restore them.
      assert {:ok, %{fetched: fetched}} = DILA.fetch(fetcher: stub(all_files()))
      assert person in fetched
      assert File.read!(Path.join([root, "raw", "dila-authority", person])) =~ "TEI"
    end

    test "names the path that failed rather than reporting a bare failure" do
      [_person, place | _] = DILA.files()

      fetcher =
        stub(
          Enum.map(all_files(), fn {name, body} ->
            if name == Path.basename(place), do: {name, {:error, :enoent}}, else: {name, body}
          end)
        )

      assert {:error, {:fetch_failed, ^place, :enoent}} =
               DILA.fetch(pin: "sha1", fetcher: fetcher)
    end

    test "an explicit pin re-fetches EVERY declared file, which is why it cannot conflict" do
      assert {:ok, _} = DILA.fetch(pin: "sha1", fetcher: stub(all_files()))

      moved = Enum.map(DILA.files(), &{Path.basename(&1), "<TEI>moved</TEI>"})

      assert {:ok, %{pin: "sha2", fetched: fetched, skipped: []}} =
               DILA.fetch(pin: "sha2", fetcher: stub(moved))

      # One entry listing files fetched at two commits states something untrue about every
      # one of them. Moving the pin is therefore all-or-nothing BY CONSTRUCTION rather than
      # by a check: an explicit pin ignores what is locked and refetches everything, so the
      # incoming set always covers the locked one and `Lockfile.merge_source/1` replaces the
      # entry outright. The `:pin_conflict` branch it can return is reachable only if the
      # lockfile holds a path this module no longer declares.
      assert length(fetched) == length(DILA.files())

      assert {:ok, entry} = Lockfile.get_source("dila-authority")
      assert entry["pin"] == %{"type" => "git", "commit" => "sha2"}
      assert entry["file_count"] == length(DILA.files())
    end
  end

  describe "resolve_pin/1" do
    test "extracts the commit sha" do
      assert {:ok, "abc123", []} =
               DILA.resolve_pin(fetcher: stub([{"commits/master", ~s({"sha":"abc123"})}]))
    end

    test "surfaces an unexpected API response rather than guessing" do
      assert {:error, :unexpected_api_response} =
               DILA.resolve_pin(fetcher: stub([{"commits/master", ~s({"message":"Not Found"})}]))
    end
  end
end
