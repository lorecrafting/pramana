defmodule Pramana.BakeTest do
  @moduledoc """
  Bake identity. The project's central claim is that two people with the same
  `bake_id` hold byte-identical corpora, which is what makes a citation reproducible
  and what "decoupled from the LLM" means concretely. These tests are that claim.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Sources

  setup do
    root = Path.join(System.tmp_dir!(), "pramana-bake-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:pramana, :project_root)
    Application.put_env(:pramana, :project_root, root)

    on_exit(fn ->
      File.rm_rf!(root)

      if prev,
        do: Application.put_env(:pramana, :project_root, prev),
        else: Application.delete_env(:pramana, :project_root)
    end)

    {:ok, source} = Sources.fetch("cbeta")

    :ok =
      Lockfile.put_source(
        Lockfile.build_entry(source,
          files: [%{path: "T/T09/T09n0262.xml", sha256: "aaa", bytes: 10}],
          pin: %{"type" => "git", "commit" => "sha-one"}
        )
      )

    %{source: source}
  end

  describe "bake_id/1" do
    test "is deterministic for identical inputs" do
      assert {:ok, a, _} = Bake.bake_id(%{"work" => "T0262"})
      assert {:ok, b, _} = Bake.bake_id(%{"work" => "T0262"})
      assert a == b
    end

    test "does not depend on map key ORDER" do
      # Elixir map iteration order is not guaranteed, so a naive encode would make the
      # bake id unstable across runs — the one thing it must never be.
      assert {:ok, a, _} = Bake.bake_id(%{"work" => "T0262", "volume" => 9, "canon" => "T"})
      assert {:ok, b, _} = Bake.bake_id(%{"canon" => "T", "volume" => 9, "work" => "T0262"})
      assert a == b
    end

    test "changes when the config changes" do
      {:ok, a, _} = Bake.bake_id(%{"work" => "T0262"})
      {:ok, b, _} = Bake.bake_id(%{"work" => "T0263"})
      refute a == b
    end

    test "changes when upstream bytes change", %{source: source} do
      {:ok, a, _} = Bake.bake_id()

      # Same pin, different file hash: the corpus content differs, so the id must.
      :ok =
        Lockfile.put_source(
          Lockfile.build_entry(source,
            files: [%{path: "T/T09/T09n0262.xml", sha256: "bbb", bytes: 10}],
            pin: %{"type" => "git", "commit" => "sha-one"}
          )
        )

      {:ok, b, _} = Bake.bake_id()
      refute a == b
    end

    test "changes when the upstream pin changes", %{source: source} do
      {:ok, a, _} = Bake.bake_id()

      :ok =
        Lockfile.put_source(
          Lockfile.build_entry(source,
            files: [%{path: "T/T09/T09n0262.xml", sha256: "aaa", bytes: 10}],
            pin: %{"type" => "git", "commit" => "sha-TWO"}
          )
        )

      {:ok, b, _} = Bake.bake_id()
      refute a == b
    end

    test "also returns the lockfile digest it was derived from" do
      assert {:ok, _id, lock_digest} = Bake.bake_id()
      assert is_binary(lock_digest) and byte_size(lock_digest) == 64
    end
  end

  describe "pipeline_version" do
    test "is recorded on the bake so a corpus can name how it was built" do
      {:ok, bake} = Bake.record(%{"work" => "T0262"})
      assert bake.pipeline_version == Bake.pipeline_version()
    end
  end

  describe "record/1" do
    test "persists the bake with stats" do
      assert {:ok, bake} = Bake.record(%{"work" => "T0262"})

      assert byte_size(bake.id) == 64
      assert bake.built_at
      assert is_integer(bake.stats["segments"])
    end

    test "re-running an identical bake is idempotent" do
      {:ok, first} = Bake.record(%{"work" => "T0262"})
      {:ok, second} = Bake.record(%{"work" => "T0262"})

      assert first.id == second.id
      assert Pramana.Repo.aggregate(Pramana.Corpus.Bake, :count) == 1
    end

    test "current_id/0 reports the latest bake" do
      # Deliberately does NOT assert an empty table first. Asserting global emptiness
      # makes a test order-dependent, and a suite that is green only in one order is
      # not green. Clear explicitly when the empty case is what is under test.
      {:ok, bake} = Bake.record(%{})
      assert Bake.current_id() == bake.id
    end

    test "current_id/0 is nil when there is no bake" do
      Pramana.Repo.delete_all(Pramana.Corpus.Bake)
      assert Bake.current_id() == nil
    end
  end
end
