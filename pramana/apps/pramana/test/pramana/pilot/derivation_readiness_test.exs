defmodule Pramana.Pilot.DerivationReadinessTest do
  use Pramana.DataCase, async: true

  alias Pramana.Commentary
  alias Pramana.Corpus.Bake, as: BakeSchema
  alias Pramana.Corpus.Work
  alias Pramana.Derivations
  alias Pramana.Pilot.DerivationReadiness
  alias Pramana.Relations
  alias Pramana.Repo

  @bake_id "bake-pilot-derivations"

  setup do
    Repo.insert!(%BakeSchema{
      id: @bake_id,
      pipeline_version: "test",
      sources_lock_sha256: "test",
      built_at: DateTime.utc_now()
    })

    Repo.insert!(%Work{id: "T9001", title: "Alpha", text_role: "root"})
    Repo.insert!(%Work{id: "T9002", title: "Beta", text_role: "commentary"})

    :ok
  end

  test "accepts all four current full/default receipts and detects later output drift" do
    record_clean!(
      "quotations_scan",
      %{"source" => "cbeta", "witness" => "T", "division" => nil, "work" => nil},
      %{"min_length" => 20}
    )

    record_clean!("relations_title", %{"mode" => "full"}, %{"min_title" => 3})
    record_clean!("relations_shared_text", %{"mode" => "full"}, %{"min_passages" => 1})

    record_clean!(
      "commentary_align",
      %{"work" => nil},
      %{
        "min_density_override" => nil,
        "grapheme_window" => Commentary.window(),
        "root_min_density" => Commentary.min_density(),
        "subcommentary_min_density" => Commentary.min_density("subcommentary"),
        "syllable_window" => Commentary.syllable_window(),
        "syllable_min_density" => Commentary.syllable_min_density(),
        "syllable_min_forward" => Commentary.syllable_min_forward()
      }
    )

    ready = DerivationReadiness.check(@bake_id)
    assert ready.ready
    assert Enum.all?(ready.derivations, fn {_kind, status} -> status.state == "ready" end)

    assert {:ok, _} =
             Relations.assert(%{
               source_work_id: "T9002",
               target_work_id: "T9001",
               relation: "comments_on",
               method: "title_match",
               confidence: "probable"
             })

    stale = DerivationReadiness.check(@bake_id)
    refute stale.ready
    assert stale.derivations["relations_title"].state == "stale_output"
  end

  test "diagnoses a qualifying receipt whose output cardinality is incomplete" do
    token =
      Derivations.begin_run(
        "relations_title",
        @bake_id,
        %{"mode" => "full"},
        %{"min_title" => 3}
      )

    receipt =
      Derivations.finish_run!(token, %{
        "failures" => 0,
        "expected_output_count" => 1
      })

    assert receipt.status == "partial"

    result = DerivationReadiness.check(@bake_id)
    assert result.derivations["relations_title"].state == "partial_receipt"
    assert result.derivations["relations_title"].output_count_matches_expected == false
  end

  test "a later relevant input mutation makes a clean receipt stale" do
    record_clean!("relations_title", %{"mode" => "full"}, %{"min_title" => 3})

    Repo.insert!(%Work{id: "T9003", title: "Gamma", text_role: "root"})

    result = DerivationReadiness.check(@bake_id)
    assert result.derivations["relations_title"].state == "stale_input"
  end

  test "rejects a commentary receipt with stale Tibetan defaults" do
    receipt =
      record_clean!(
        "commentary_align",
        %{"work" => nil},
        %{
          "min_density_override" => nil,
          "grapheme_window" => Commentary.window(),
          "root_min_density" => Commentary.min_density(),
          "subcommentary_min_density" => Commentary.min_density("subcommentary"),
          "syllable_window" => Commentary.syllable_window(),
          "syllable_min_density" => Commentary.syllable_min_density(),
          "syllable_min_forward" => Commentary.syllable_min_forward() - 1.0
        }
      )

    refute DerivationReadiness.commentary_scope?(receipt)
  end

  test "rejects a corpus-wide quotation receipt for the CBETA/T pilot" do
    receipt =
      record_clean!(
        "quotations_scan",
        %{"source" => nil, "witness" => nil, "division" => nil, "work" => nil},
        %{"min_length" => 20}
      )

    refute DerivationReadiness.quotation_scope?(receipt)
  end

  defp record_clean!(kind, scope, parameters) do
    token = Derivations.begin_run(kind, @bake_id, scope, parameters)
    {_digest, output_count} = Derivations.current_output_snapshot(token)

    receipt =
      Derivations.finish_run!(token, %{
        "failures" => 0,
        "expected_output_count" => output_count
      })

    assert receipt.status == "complete"
    receipt
  end
end
