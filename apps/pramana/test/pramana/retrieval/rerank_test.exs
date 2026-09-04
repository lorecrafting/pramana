defmodule Pramana.Retrieval.RerankTest do
  @moduledoc """
  Reordering fused candidates by query-to-rendering containment.

  Worth +46 retrieval cases and +5 topical over the whole gold set, with
  `answered from any tradition` 72.7% -> 81.8%. The tests that matter most here are the
  ones pinning what it must NOT do: it must not invent an ordering where it has no
  evidence, and it must not favour one tradition because only that tradition's renderings
  happen to be joinable — which is exactly the defect the first version shipped with.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Retrieval.Rerank
  alias Pramana.Translations

  defp result(urn), do: %{urn: urn, rrf_score: 0.1, span: nil}

  @chunk_urn "pramana:sc.ms:mn1@1.1"

  # One chunk, one segment, and two translators who rendered it differently. Enough to ask
  # whether a stage can be told to ignore one of them.
  defp two_translators! do
    Repo.insert!(%Source{
      id: "sc",
      name: "SuttaCentral",
      license_spdx: "CC0-1.0",
      license_class: "cc0",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Witness{id: "ms", name: "Mahāsaṅgīti"})
    Repo.insert!(%Work{id: "mn1", title: "Mūlapariyāya"})

    text =
      Repo.insert!(%Text{
        work_id: "mn1",
        source_id: "sc",
        witness_id: "ms",
        urn_prefix: "pramana:sc.ms:mn1",
        body: "Evaṁ me sutaṁ",
        body_sha256: "x",
        meta: %{}
      })

    Repo.insert!(%Segment{
      text_id: text.id,
      urn: @chunk_urn,
      ordinal: 0,
      content: "Evaṁ me sutaṁ",
      content_sha256: "y",
      char_start: 0,
      char_end: 13,
      byte_start: 0,
      byte_end: 13,
      meta: %{}
    })

    Repo.insert!(%Chunk{
      text_id: text.id,
      urn: @chunk_urn,
      first_ordinal: 0,
      last_ordinal: 0,
      segment_count: 1,
      content: "Evaṁ me sutaṁ",
      content_sha256: "z",
      char_start: 0,
      char_end: 13,
      byte_start: 0,
      byte_end: 13
    })

    {:ok, _} =
      Translations.store([
        %{
          anchor_urn: @chunk_urn,
          work_id: "mn1",
          lang: "en",
          translator_id: "sujato",
          tier: "t0",
          method: "human",
          text: "So I have heard",
          redistributable: true,
          license_class: "cc0"
        },
        %{
          anchor_urn: @chunk_urn,
          work_id: "mn1",
          lang: "en",
          translator_id: "model:mitra",
          tier: "t1",
          method: "llm",
          # `generated_translation_names_its_model` requires it, which is invariant #8
          # holding at the schema: a generated rendering that cannot say what produced it
          # is not attributable.
          model_id: "buddhist-nlp/gemma-2-mitra-it",
          text: "Thus was it spoken",
          redistributable: false,
          license_class: "unknown"
        }
      ])

    :ok
  end

  # A candidate the reranker CAN read sorts above one it cannot. `moved?` asks whether the
  # rendering was visible to this stage at all, which is the whole question.
  defp moved?(query, opts) do
    results = [result("pramana:sc.ms:mn1@9.9"), result(@chunk_urn)]

    Rerank.by_rendering(query, results, opts) != results
  end

  describe "by_rendering/3" do
    test "returns [] for no candidates" do
      assert Rerank.by_rendering("anything", []) == []
    end

    test "leaves the order alone when the query has no tokens" do
      results = [result("a"), result("b"), result("c")]

      assert Rerank.by_rendering("   ", results) == results
    end

    test "leaves the order alone when nothing carries a rendering" do
      # THE CRITICAL PROPERTY. Every candidate scores 0, and a stable sort must return
      # them untouched. If this ever regresses, the reranker starts shuffling the Chinese
      # canon — which has no English renderings at all — on no evidence whatever.
      results = Enum.map(["u1", "u2", "u3", "u4"], &result/1)

      assert Rerank.by_rendering("four noble truths", results) == results
    end

    # THE DEFECT THIS SUITE EXISTED WITHOUT UNTIL 2026-09-03.
    #
    # `--translators` restricted candidate generation and not ordering, so every arm of the
    # model ladder was reranked against the whole English layer — including the renderings
    # that defined the arm by their absence. A scope only one stage obeys is not a scope.
    test "an excluded translator cannot reorder anything" do
      two_translators!()

      # The two renderings share no tokens, so a query names exactly one of them. Without
      # that the test passes for the wrong reason: "Thus have I heard" also matches
      # Sujato's "So I have heard" on have/I/heard, and the excluded translator looks
      # visible when it is only the vocabulary overlapping.
      assert moved?("Thus was it spoken", translators: ["model:mitra"]),
             "the arm's own translator must still be visible"

      refute moved?("Thus was it spoken", translators: ["sujato"]),
             "a rendering outside the arm must not influence the ordering"
    end

    test "`--translators none` means no English anywhere in the path, not just in the index" do
      two_translators!()

      refute moved?("So I have heard", translators: [])
      refute moved?("Thus was it spoken", translators: [])
    end

    # Ablation must hide the same chunks from both stages, or candidates drawn from one
    # 25% and reranked against a different 25% is not 25% coverage of anything. Both hash
    # the chunk id, so 0% hides everything here and 100% hides nothing.
    test "a coverage ablation reaches this stage too" do
      two_translators!()

      assert moved?("So I have heard", translation_coverage: 1.0)
      refute moved?("So I have heard", translation_coverage: 0.0)
    end

    test "with no scope given, every rendering is visible — production behaviour is unchanged" do
      two_translators!()

      assert moved?("So I have heard", [])
      assert moved?("Thus was it spoken", [])
    end

    test "a tie keeps the incoming fused order" do
      # Ties are broken by original index, never arbitrarily. The fused order is real
      # evidence — two retrievers agreed on it — and must not be discarded by a signal
      # that cannot separate the candidates.
      results = Enum.map(1..10, &result("urn-#{&1}"))

      assert Rerank.by_rendering("a query with no matching renderings", results) == results
    end
  end
end
