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
