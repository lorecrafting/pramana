defmodule Pramana.Acquire.ArchiveTest do
  @moduledoc """
  A cached archive that exists is not a cached archive that is usable.

  The CBETA tarball is 1.2 GB. A stall, a Ctrl-C or a dropped connection leaves a
  plausible-looking file behind, and the cache check was `size > 0` — so every later run
  logged "archive already downloaded", skipped the fetch, and died in `:erl_tar` with
  `{:extract_failed, :eof}`. That error points at the extraction code and says nothing
  about the cache, which stays poisoned until someone deletes it by hand. It cost two
  hours here.
  """
  # ASYNC: FALSE, like every other test that touches `:project_root`. That key is global
  # application state, and the corpus tests read the real `raw/` through it in `setup_all`.
  # Running async, this pointed it at an empty temp directory for the length of the module
  # and `Pramana.Normalize.CBETACorpusTest` failed its setup with :enoent — 16 tests
  # invalidated, on some seeds and not others. `cbeta_test.exs` and `lockfile_test.exs` are
  # already `async: false` for exactly this; the reason simply is not written down anywhere
  # a new file would find it.
  use ExUnit.Case, async: false

  alias Pramana.Acquire.Archive

  setup do
    root = Path.join(System.tmp_dir!(), "pramana-archive-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:pramana, :project_root)
    Application.put_env(:pramana, :project_root, root)

    on_exit(fn ->
      File.rm_rf!(root)
      if prev, do: Application.put_env(:pramana, :project_root, prev)
    end)

    %{root: root}
  end

  # A real gzipped tar holding one file at the path GitHub's archive shape produces:
  # everything nested under "<repo>-<sha>/", which `extract/5` strips.
  defp archive_bytes(sha) do
    path = String.to_charlist("xml-p5-#{sha}/N/N13/N13n0006.xml")
    tmp = Path.join(System.tmp_dir!(), "src-#{System.unique_integer([:positive])}.tar.gz")
    :ok = :erl_tar.create(String.to_charlist(tmp), [{path, "<TEI>相應部</TEI>"}], [:compressed])
    bytes = File.read!(tmp)
    File.rm!(tmp)
    bytes
  end

  defp cache_path(sha), do: Path.join(System.tmp_dir!(), "pramana-cbeta-#{sha}.tar.gz")

  describe "a cached archive" do
    test "is used when it decompresses to the end" do
      sha = "sha#{System.unique_integer([:positive])}"
      File.write!(cache_path(sha), archive_bytes(sha))
      on_exit(fn -> File.rm(cache_path(sha)) end)

      downloads = self()

      assert {:ok, [%{path: "N/N13/N13n0006.xml"}]} =
               Archive.fetch("cbeta", sha, ["N/N13/N13n0006.xml"],
                 repo: "cbeta-org/xml-p5",
                 downloader: fn _url, _target ->
                   send(downloads, :downloaded)
                   :ok
                 end
               )

      refute_received :downloaded
    end

    # THE BUG. Half a gzip has a positive size and no trailer, so it passed the old check
    # and failed two steps later with an error about tar.
    test "is refetched when it was truncated mid-download" do
      sha = "sha#{System.unique_integer([:positive])}"
      whole = archive_bytes(sha)
      File.write!(cache_path(sha), binary_part(whole, 0, div(byte_size(whole), 2)))
      on_exit(fn -> File.rm(cache_path(sha)) end)

      test = self()

      assert {:ok, [_]} =
               Archive.fetch("cbeta", sha, ["N/N13/N13n0006.xml"],
                 repo: "cbeta-org/xml-p5",
                 downloader: fn _url, target ->
                   send(test, :downloaded)
                   File.write!(target, whole)
                   :ok
                 end
               )

      assert_received :downloaded
    end

    test "is refetched when it is empty" do
      sha = "sha#{System.unique_integer([:positive])}"
      File.write!(cache_path(sha), "")
      on_exit(fn -> File.rm(cache_path(sha)) end)

      test = self()

      assert {:ok, [_]} =
               Archive.fetch("cbeta", sha, ["N/N13/N13n0006.xml"],
                 repo: "cbeta-org/xml-p5",
                 downloader: fn _url, target ->
                   send(test, :downloaded)
                   File.write!(target, archive_bytes(sha))
                   :ok
                 end
               )

      assert_received :downloaded
    end

    # A failed download must not leave a file the next run would trust.
    test "leaves nothing behind when the download fails" do
      sha = "sha#{System.unique_integer([:positive])}"

      assert {:error, {:download_failed, :nope}} =
               Archive.fetch("cbeta", sha, ["N/N13/N13n0006.xml"],
                 repo: "cbeta-org/xml-p5",
                 downloader: fn _url, target ->
                   File.write!(target, "partial")
                   {:error, :nope}
                 end
               )

      refute File.exists?(cache_path(sha))
    end
  end
end
