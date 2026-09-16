defmodule Pramana.ReleaseTest do
  @moduledoc """
  Recorded source identity and derived-state facts.

  These tests exercise stamps and drift using isolated database fixtures. They do not
  establish byte-complete content identity or historical retrieval reproducibility.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Bake, as: BakeSchema
  alias Pramana.Release
  alias Pramana.Translations

  defp rendering!(id) do
    {:ok, _} =
      Translations.store([
        %{
          anchor_urn: "pramana:sc.ms:mn1@#{id}",
          work_id: "mn1",
          lang: "en",
          translator_id: "sujato",
          tier: "t0",
          method: "human",
          text: "So I have heard, rendering number #{id}.",
          redistributable: true,
          license_class: "cc0"
        }
      ])
  end

  defp bake!(digit, built_at) do
    Pramana.Repo.insert!(%BakeSchema{
      id: String.duplicate(digit, 64),
      pipeline_version: Pramana.Bake.pipeline_version(),
      sources_lock_sha256: String.duplicate("c", 64),
      built_at: built_at
    })
  end

  describe "stamp/0" do
    test "is idempotent while nothing changes" do
      {:ok, first} = Release.stamp()
      {:ok, second} = Release.stamp()

      # A release list where most rows are identical is a list nobody reads.
      assert first.id == second.id
      assert first.release_id == second.release_id
    end

    test "the id MOVES when the English layer does — the whole point" do
      {:ok, before} = Release.stamp()
      rendering!("1.1")
      {:ok, after_import} = Release.stamp()

      refute before.release_id == after_import.release_id,
             """
             A rendering was imported and `release_id` did not move, which is exactly the
             `bake_id` defect this module exists to fix: two holders of one id answering
             the same query differently.
             """

      refute before.translation_set_id == after_import.translation_set_id
    end

    test "the SOURCE id does not move when only the English layer does" do
      # Derived-data changes must not alter the source-input identity.
      {:ok, before} = Release.stamp()
      rendering!("2.1")
      {:ok, after_import} = Release.stamp()

      assert before.source_bake_id == after_import.source_bake_id
      assert before.vector_set_id == after_import.vector_set_id
    end
  end

  describe "drift/0" do
    test "reports `:unstamped` before anything is recorded" do
      assert Release.drift() == :unstamped
    end

    test "reports `:current` immediately after a stamp" do
      {:ok, _} = Release.stamp()
      assert Release.drift() == :current
    end

    test "names what moved, so a stale stamp cannot be silent" do
      # A RECORDED id can go stale where a computed one cannot, which would reproduce the
      # original defect in a new place. Drift is the check that keeps it visible.
      {:ok, _} = Release.stamp()
      rendering!("3.1")

      drift = Release.drift()

      assert is_map(drift)
      assert %{translations_count: %{stamped: stamped, live: live}} = drift
      assert live == stamped + 1
    end

    test "reports a source-only change without refreshing the recorded release" do
      before = bake!("a", ~U[2026-01-01 00:00:00.000000Z])
      {:ok, stamped} = Release.stamp()
      after_bake = bake!("b", ~U[2026-01-02 00:00:00.000000Z])

      assert Release.drift() == %{
               source_bake_id: %{stamped: before.id, live: after_bake.id}
             }

      assert Release.current() == stamped
      assert Pramana.Repo.aggregate(Pramana.Corpus.Release, :count) == 1

      {:ok, refreshed} = Release.stamp()
      refute refreshed.release_id == stamped.release_id
      assert refreshed.source_bake_id == after_bake.id
      assert refreshed.translation_set_id == stamped.translation_set_id
      assert refreshed.vector_set_id == stamped.vector_set_id
      assert Release.drift() == :current
    end

    test "reports a source identity appearing after a source-less stamp" do
      {:ok, stamped} = Release.stamp()
      assert stamped.source_bake_id == nil
      bake = bake!("a", ~U[2026-01-01 00:00:00.000000Z])

      assert Release.drift() == %{source_bake_id: %{stamped: nil, live: bake.id}}
    end

    test "reports a source identity disappearing rather than treating nil as unchanged" do
      bake = bake!("a", ~U[2026-01-01 00:00:00.000000Z])
      {:ok, _} = Release.stamp()
      Pramana.Repo.delete!(bake)

      assert Release.drift() == %{source_bake_id: %{stamped: bake.id, live: nil}}
    end

    test "a newer build timestamp for the same source identity is not drift" do
      bake = bake!("a", ~U[2026-01-01 00:00:00.000000Z])
      {:ok, _} = Release.stamp()

      bake
      |> Ecto.Changeset.change(built_at: ~U[2026-01-02 00:00:00.000000Z])
      |> Pramana.Repo.update!()

      assert Release.drift() == :current
    end

    test "reports source and derived changes together" do
      before = bake!("a", ~U[2026-01-01 00:00:00.000000Z])
      {:ok, stamped} = Release.stamp()
      after_bake = bake!("b", ~U[2026-01-02 00:00:00.000000Z])
      rendering!("4.1")

      assert Release.drift() == %{
               source_bake_id: %{stamped: before.id, live: after_bake.id},
               translations_count: %{stamped: stamped.translations_count, live: 1},
               translators: %{stamped: stamped.translators, live: ["sujato"]}
             }
    end
  end

  describe "ids/0" do
    test "computes what the current corpus would stamp" do
      {:ok, stamped} = Release.stamp()
      ids = Release.ids()

      # One definition of what the ids are made of. It was briefly two — a private digest
      # for stamping and `ids/0` for reporting — and that is how a stamped id stops
      # matching the id a check computes. Rule 41.
      assert ids.release_id == stamped.release_id
      assert ids.translation_set_id == stamped.translation_set_id
      assert ids.vector_set_id == stamped.vector_set_id
    end
  end
end
