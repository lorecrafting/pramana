defmodule Pramana.ReleaseContentIdentityV2Test do
  @moduledoc """
  Adversarial coverage for release identity v2.

  The cases keep counts and model/translator names unchanged while changing the actual
  answer-producing content. That is the hole the previous coarse release stamp could not
  see.
  """

  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Chunk.Vectors
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Embed
  alias Pramana.Embed.Transfer
  alias Pramana.Release
  alias Pramana.Release.Selection
  alias Pramana.Repo
  alias Pramana.Translations

  test "same-count translation replacement moves the content identity" do
    rendering!("First rendering")
    {:ok, before} = Release.stamp()

    rendering!("Second rendering")

    assert Repo.aggregate(Pramana.Corpus.Translation, :count) == 1
    assert before.translators == ["fixture"]

    assert %{
             translation_set_id: %{stamped: stamped, live: live}
           } = Release.drift()

    assert stamped == before.translation_set_id
    assert String.starts_with?(live, "v2:")
    refute live == stamped

    {:ok, after_edit} = Release.stamp()
    refute after_edit.release_id == before.release_id
    refute after_edit.translation_set_id == before.translation_set_id
    assert after_edit.vector_set_id == before.vector_set_id
    assert Release.drift() == :current
  end

  test "actual rendering text participates even when its adjacent hash is stale" do
    rendering!("Original rendering")
    {:ok, before} = Release.stamp()
    changed_at = DateTime.add(DateTime.utc_now(), 1, :second)

    Repo.update_all(Pramana.Corpus.Translation,
      set: [text: "Tampered rendering", updated_at: changed_at]
    )

    # Deliberately leave text_sha256 untouched. The v1-style trust in the adjacent hash
    # would miss this; v2 fingerprints the actual stored text as well.
    assert %{translation_set_id: %{stamped: stamped, live: live}} = Release.drift()
    assert stamped == before.translation_set_id
    refute live == stamped
  end

  test "a no-op translation rewrite does not manufacture content drift" do
    rendering!("Same rendering")
    {:ok, before} = Release.stamp()

    rendering!("Same rendering")

    assert Release.drift() == :current
    {:ok, after_rewrite} = Release.stamp()
    assert after_rewrite == before
  end

  test "same-count vector replacement hashes the stored embedding bytes" do
    vector_row = vector_fixture!()
    first = unit_vector(0)
    second = unit_vector(1)
    old = DateTime.add(DateTime.utc_now(), -60, :second)

    Repo.update_all(
      from(v in ChunkVector, where: v.id == ^vector_row.id),
      set: [
        embedding: Pgvector.new(first),
        embedding_model: "fixture-model",
        embedding_max_length: 320,
        embedded_at: old,
        updated_at: old
      ]
    )

    {:ok, before} = Release.stamp()
    count = Repo.aggregate(ChunkVector, :count)

    path =
      Path.join(
        System.tmp_dir!(),
        "pramana-release-v2-#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      Jason.encode!(%{
        id: vector_row.id,
        sha256: vector_row.content_sha256,
        embedding: second,
        max_length: 320
      }) <> "\n"
    )

    assert {:ok, %{written: 1}} = Transfer.import(path, model: "fixture-model")
    assert Repo.aggregate(ChunkVector, :count) == count
    assert before.embedding_models == ["fixture-model"]

    assert %{vector_set_id: %{stamped: stamped, live: live}} = Release.drift()
    assert stamped == before.vector_set_id
    assert String.starts_with?(live, "v2:")
    refute live == stamped

    {:ok, after_import} = Release.stamp()
    refute after_import.release_id == before.release_id
    refute after_import.vector_set_id == before.vector_set_id
    assert after_import.translation_set_id == before.translation_set_id
  end

  test "legacy coarse component ids are visible drift, not silently reinterpreted" do
    now = DateTime.utc_now()

    legacy =
      Repo.insert!(%ReleaseSchema{
        release_id: String.duplicate("c", 64),
        source_bake_id: nil,
        translation_set_id: String.duplicate("a", 64),
        vector_set_id: String.duplicate("b", 64),
        translations_count: 0,
        vectors_count: 0,
        embedding_models: [],
        translators: [],
        stamped_at: now
      })

    Repo.insert!(%Selection{id: 1, release_id: legacy.id, selected_at: now})

    assert Release.drift() == %{
             identity_version: %{stamped: "v1/coarse", live: "v2"}
           }
  end

  test "ids exposes versioned content-set identities without selecting them" do
    ids = Release.ids()

    assert String.starts_with?(ids.translation_set_id, "v2:")
    assert String.starts_with?(ids.vector_set_id, "v2:")
    assert byte_size(ids.release_id) == 64
    assert Release.current() == nil
  end

  defp rendering!(text) do
    {:ok, 1} =
      Translations.store([
        %{
          anchor_urn: "pramana:sc.ms:mn1@1.1",
          work_id: "mn1",
          lang: "en",
          translator_id: "fixture",
          translator_name: "Fixture Translator",
          tier: "t0",
          method: "human",
          text: text,
          redistributable: true,
          license_class: "cc0"
        }
      ])
  end

  defp vector_fixture! do
    Repo.insert!(%Source{
      id: "release-v2-source",
      name: "Release v2 source",
      license_spdx: "CC0-1.0",
      license_class: "cc0",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Witness{id: "release-v2-witness", name: "Release v2 witness"})
    Repo.insert!(%Work{id: "release-v2-work", title: "Release v2 work"})

    %{text: text} =
      Pramana.CorpusFixtures.text!(
        %{
          work_id: "release-v2-work",
          source_id: "release-v2-source",
          witness_id: "release-v2-witness",
          urn_prefix: "pramana:fixture.release-v2:work"
        },
        [{"pramana:fixture.release-v2:work@1.1", "identity fixture"}]
      )

    {:ok, 1} = Builder.build_for_text(text.id, max_chars: 100)
    {:ok, 1} = Vectors.build_source(text.id)
    Repo.one!(ChunkVector)
  end

  defp unit_vector(axis) do
    List.duplicate(0.0, Embed.dims()) |> List.replace_at(axis, 1.0)
  end
end
