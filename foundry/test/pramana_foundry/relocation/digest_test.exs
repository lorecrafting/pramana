defmodule PramanaFoundry.Relocation.DigestTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Relocation.Digest

  @moduletag :digest

  setup do
    tmp = Path.join(System.tmp_dir!(), "digest-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)
    {:ok, tmp_dir: tmp}
  end

  test "hash_bytes computes lowercase sha256", _ctx do
    # sha256 of "hello" is 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
    assert Digest.hash_bytes("hello") ==
             "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
  end

  test "snapshot recursively computes digests and skips .git", %{tmp_dir: tmp} do
    f1 = Path.join(tmp, "a.txt")
    File.write!(f1, "file a content")

    sub = Path.join(tmp, "subdir")
    File.mkdir_p!(sub)
    f2 = Path.join(sub, "b.json")
    File.write!(f2, "{\"key\": \"value\"}")

    git = Path.join(tmp, ".git")
    File.mkdir_p!(git)
    File.write!(Path.join(git, "config"), "git config")

    {:ok, snap} = Digest.snapshot(tmp)

    assert snap.file_count == 2
    assert Map.has_key?(snap.digests, "a.txt")
    assert Map.has_key?(snap.digests, "subdir/b.json")
    refute Map.has_key?(snap.digests, ".git/config")
    assert snap.digests["a.txt"] == Digest.hash_bytes("file a content")
  end

  test "verify succeeds when destination matches expected digests", %{tmp_dir: tmp} do
    src = Path.join(tmp, "src")
    dst = Path.join(tmp, "dst")
    File.mkdir_p!(src)
    File.mkdir_p!(dst)

    File.write!(Path.join(src, "evidence.json"), "{\"evidence\": 1}")
    File.write!(Path.join(dst, "evidence.json"), "{\"evidence\": 1}")

    {:ok, snap} = Digest.snapshot(src)
    assert {:ok, result} = Digest.verify(snap, dst)
    assert result.matched_count == 1
  end

  test "verify detects missing and modified files", %{tmp_dir: tmp} do
    src = Path.join(tmp, "src")
    dst = Path.join(tmp, "dst")
    File.mkdir_p!(src)
    File.mkdir_p!(dst)

    File.write!(Path.join(src, "kept.txt"), "kept")
    File.write!(Path.join(src, "modified.txt"), "original")
    File.write!(Path.join(src, "missing.txt"), "missing")

    File.write!(Path.join(dst, "kept.txt"), "kept")
    File.write!(Path.join(dst, "modified.txt"), "corrupted")

    {:ok, snap} = Digest.snapshot(src)
    assert {:error, {:digest_verification_failed, details}} = Digest.verify(snap, dst)

    assert "missing.txt" in details.missing
    assert Map.has_key?(details.mismatches, "modified.txt")
    assert details.mismatches["modified.txt"].expected == Digest.hash_bytes("original")
    assert details.mismatches["modified.txt"].actual == Digest.hash_bytes("corrupted")
  end
end
