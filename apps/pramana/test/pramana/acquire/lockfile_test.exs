defmodule Pramana.Acquire.LockfileTest do
  use ExUnit.Case, async: false

  alias Pramana.Acquire.Lockfile
  alias Pramana.Sources

  setup do
    root = Path.join(System.tmp_dir!(), "pramana-lock-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:pramana, :project_root)
    Application.put_env(:pramana, :project_root, root)

    on_exit(fn ->
      File.rm_rf!(root)
      if prev, do: Application.put_env(:pramana, :project_root, prev)
    end)

    {:ok, source} = Sources.fetch("cbeta")
    %{root: root, source: source}
  end

  defp write_raw!(root, source_id, path, contents) do
    target = Path.join([root, "raw", source_id, path])
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, contents)
    %{path: path, sha256: Lockfile.sha256(contents), bytes: byte_size(contents)}
  end

  # A source acquired one collection at a time is written more than once, and
  # `put_source/1` writes the entry WHOLE. Acquiring CBETA's X collection therefore
  # deleted the Taishō's 2,471 files from the lockfile while their texts stayed in the
  # corpus — nothing failed, and the corpus stopped being reproducible from
  # `sources.lock.json`, which is invariant 3.
  describe "merge_source/1" do
    test "keeps files an earlier acquisition recorded", %{source: source} do
      pin = %{"type" => "git", "commit" => "abc"}

      taisho = %{path: "T/T09/T09n0262.xml", sha256: String.duplicate("a", 64), bytes: 1}
      zoku = %{path: "X/X08/X08n0240.xml", sha256: String.duplicate("b", 64), bytes: 2}

      :ok = Lockfile.put_source(Lockfile.build_entry(source, files: [taisho], pin: pin))
      :ok = Lockfile.merge_source(Lockfile.build_entry(source, files: [zoku], pin: pin))

      {:ok, entry} = Lockfile.get_source("cbeta")

      assert Enum.map(entry["files"], & &1["path"]) == [
               "T/T09/T09n0262.xml",
               "X/X08/X08n0240.xml"
             ]

      assert entry["file_count"] == 2
    end

    test "recomputes the manifest hash over the union, so bake_id covers both",
         %{source: source} do
      pin = %{"type" => "git", "commit" => "abc"}
      a = %{path: "T/T09/T09n0262.xml", sha256: String.duplicate("a", 64), bytes: 1}
      b = %{path: "X/X08/X08n0240.xml", sha256: String.duplicate("b", 64), bytes: 2}

      :ok = Lockfile.put_source(Lockfile.build_entry(source, files: [a], pin: pin))
      :ok = Lockfile.merge_source(Lockfile.build_entry(source, files: [b], pin: pin))

      {:ok, entry} = Lockfile.get_source("cbeta")
      assert entry["files_sha256"] == Lockfile.manifest_hash([a, b])
    end

    test "a re-acquired file is replaced, not duplicated", %{source: source} do
      pin = %{"type" => "git", "commit" => "abc"}
      before = %{path: "T/T09/T09n0262.xml", sha256: String.duplicate("a", 64), bytes: 1}
      again = %{path: "T/T09/T09n0262.xml", sha256: String.duplicate("c", 64), bytes: 3}

      :ok = Lockfile.put_source(Lockfile.build_entry(source, files: [before], pin: pin))
      :ok = Lockfile.merge_source(Lockfile.build_entry(source, files: [again], pin: pin))

      {:ok, entry} = Lockfile.get_source("cbeta")

      assert [%{"sha256" => sha, "bytes" => 3}] = entry["files"]
      assert sha == String.duplicate("c", 64)
    end

    test "refuses to merge files fetched at a different pin", %{source: source} do
      a = %{path: "T/T09/T09n0262.xml", sha256: String.duplicate("a", 64), bytes: 1}
      b = %{path: "X/X08/X08n0240.xml", sha256: String.duplicate("b", 64), bytes: 2}

      :ok =
        Lockfile.put_source(
          Lockfile.build_entry(source, files: [a], pin: %{"type" => "git", "commit" => "abc"})
        )

      assert {:error, {:pin_conflict, %{"commit" => "abc"}, %{"commit" => "def"}}} =
               Lockfile.merge_source(
                 Lockfile.build_entry(source,
                   files: [b],
                   pin: %{"type" => "git", "commit" => "def"}
                 )
               )

      # And it left the lockfile alone rather than half-writing it.
      {:ok, entry} = Lockfile.get_source("cbeta")
      assert Enum.map(entry["files"], & &1["path"]) == ["T/T09/T09n0262.xml"]
    end

    # A pin that moved is not automatically a conflict. Re-acquiring the same paths at a
    # newer commit is the ordinary case and must replace the entry; it is only a conflict
    # when the new fetch leaves paths behind, because those would keep a commit label
    # they never came from.
    test "replaces the entry when the new fetch covers everything already locked",
         %{source: source} do
      a = %{path: "T/T09/T09n0262.xml", sha256: String.duplicate("a", 64), bytes: 1}
      a2 = %{path: "T/T09/T09n0262.xml", sha256: String.duplicate("z", 64), bytes: 9}

      :ok =
        Lockfile.put_source(
          Lockfile.build_entry(source, files: [a], pin: %{"type" => "git", "commit" => "abc"})
        )

      assert :ok =
               Lockfile.merge_source(
                 Lockfile.build_entry(source,
                   files: [a2],
                   pin: %{"type" => "git", "commit" => "def"}
                 )
               )

      assert {:ok, %{"pin" => %{"commit" => "def"}, "file_count" => 1}} =
               Lockfile.get_source("cbeta")
    end

    test "writes the entry outright when the source is not locked yet", %{source: source} do
      entry =
        Lockfile.build_entry(source,
          files: [%{path: "T/T09/T09n0262.xml", sha256: String.duplicate("a", 64), bytes: 1}],
          pin: %{"type" => "git", "commit" => "abc"}
        )

      assert :ok = Lockfile.merge_source(entry)
      assert {:ok, %{"file_count" => 1}} = Lockfile.get_source("cbeta")
    end
  end

  describe "manifest_hash/1" do
    test "is independent of the order files were fetched in" do
      a = %{path: "T/T09/a.xml", sha256: "aaa", bytes: 1}
      b = %{path: "T/T09/b.xml", sha256: "bbb", bytes: 2}

      assert Lockfile.manifest_hash([a, b]) == Lockfile.manifest_hash([b, a])
    end

    test "changes when any file's content hash changes" do
      a = %{path: "x.xml", sha256: "aaa", bytes: 1}
      a2 = %{path: "x.xml", sha256: "zzz", bytes: 1}

      refute Lockfile.manifest_hash([a]) == Lockfile.manifest_hash([a2])
    end

    test "changes when a file is added" do
      a = %{path: "x.xml", sha256: "aaa", bytes: 1}
      b = %{path: "y.xml", sha256: "bbb", bytes: 1}

      refute Lockfile.manifest_hash([a]) == Lockfile.manifest_hash([a, b])
    end
  end

  describe "build_entry/2" do
    test "records the pin, license, and per-file hashes", %{source: source} do
      files = [%{path: "T/T09/T09n0262.xml", sha256: "deadbeef", bytes: 42}]

      entry =
        Lockfile.build_entry(source,
          files: files,
          pin: %{"type" => "git", "commit" => "abc123"}
        )

      assert entry["id"] == "cbeta"
      assert entry["pin"] == %{"type" => "git", "commit" => "abc123"}
      assert entry["file_count"] == 1
      assert entry["files_sha256"] == Lockfile.manifest_hash(files)
      assert [%{"path" => "T/T09/T09n0262.xml", "sha256" => "deadbeef"}] = entry["files"]
    end

    test "records CBETA's non-commercial, non-redistributable license", %{source: source} do
      entry = Lockfile.build_entry(source, files: [], pin: %{"type" => "git", "commit" => "x"})

      assert entry["license"]["spdx"] == "LicenseRef-CBETA-NC"
      assert entry["license"]["class"] == "nc"
      assert entry["license"]["commercial_use"] == false
      assert entry["license"]["redistributable"] == false
    end

    test "sorts files so the entry is stable across runs", %{source: source} do
      files = [
        %{path: "z.xml", sha256: "z", bytes: 1},
        %{path: "a.xml", sha256: "a", bytes: 1}
      ]

      entry = Lockfile.build_entry(source, files: files, pin: %{"type" => "git", "commit" => "x"})
      assert Enum.map(entry["files"], & &1["path"]) == ["a.xml", "z.xml"]
    end
  end

  describe "put_source/1 and get_source/1" do
    test "round-trips an entry", %{source: source} do
      entry = Lockfile.build_entry(source, files: [], pin: %{"type" => "git", "commit" => "abc"})
      assert :ok = Lockfile.put_source(entry)
      assert {:ok, read_back} = Lockfile.get_source("cbeta")
      assert read_back["pin"]["commit"] == "abc"
    end

    test "replacing one source leaves others untouched", %{source: cbeta} do
      {:ok, sc} = Sources.fetch("sc")

      :ok = Lockfile.put_source(Lockfile.build_entry(cbeta, files: [], pin: %{"c" => 1}))
      :ok = Lockfile.put_source(Lockfile.build_entry(sc, files: [], pin: %{"c" => 2}))
      :ok = Lockfile.put_source(Lockfile.build_entry(cbeta, files: [], pin: %{"c" => 3}))

      assert {:ok, %{"pin" => %{"c" => 3}}} = Lockfile.get_source("cbeta")
      assert {:ok, %{"pin" => %{"c" => 2}}} = Lockfile.get_source("sc")
    end

    test "returns :not_locked for an unknown source" do
      assert {:error, :not_locked} = Lockfile.get_source("cbeta")
    end
  end

  describe "verify/1 — raw/ is append-only and tamper-evident" do
    test "passes when raw/ matches the lockfile", %{root: root, source: source} do
      f = write_raw!(root, "cbeta", "T/T09/T09n0262.xml", "<TEI>妙法蓮華經</TEI>")
      :ok = Lockfile.put_source(Lockfile.build_entry(source, files: [f], pin: %{"c" => 1}))

      assert {:ok, 1} = Lockfile.verify("cbeta")
    end

    test "detects an edited file", %{root: root, source: source} do
      f = write_raw!(root, "cbeta", "T/T09/T09n0262.xml", "original")
      :ok = Lockfile.put_source(Lockfile.build_entry(source, files: [f], pin: %{"c" => 1}))

      # Simulate a hand-edit of raw/, which invariant #3 forbids.
      File.write!(Path.join([root, "raw", "cbeta", "T/T09/T09n0262.xml"]), "tampered")

      assert {:error, {:mismatches, [%{reason: :hash_mismatch, path: path}]}} =
               Lockfile.verify("cbeta")

      assert path == "T/T09/T09n0262.xml"
    end

    test "detects a deleted file", %{root: root, source: source} do
      f = write_raw!(root, "cbeta", "T/T09/T09n0262.xml", "original")
      :ok = Lockfile.put_source(Lockfile.build_entry(source, files: [f], pin: %{"c" => 1}))
      File.rm!(Path.join([root, "raw", "cbeta", "T/T09/T09n0262.xml"]))

      assert {:error, {:mismatches, [%{reason: :enoent}]}} = Lockfile.verify("cbeta")
    end

    test "hashes bytes, not decoded text — CJK must round-trip exactly", %{
      root: root,
      source: source
    } do
      # A CJK-heavy payload with a rare glyph, to catch any accidental transcoding
      # in the read/write path.
      contents = "妙法蓮華經 序品第一 𡬸 \u{20B9F}"
      f = write_raw!(root, "cbeta", "cjk.xml", contents)
      :ok = Lockfile.put_source(Lockfile.build_entry(source, files: [f], pin: %{"c" => 1}))

      assert {:ok, 1} = Lockfile.verify("cbeta")
      assert File.read!(Path.join([root, "raw", "cbeta", "cjk.xml"])) == contents
    end
  end
end
