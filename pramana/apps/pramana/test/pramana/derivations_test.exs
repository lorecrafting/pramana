defmodule Pramana.DerivationsTest do
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Work
  alias Pramana.Derivations
  alias Pramana.Relations
  alias Pramana.Repo

  test "a clean exit cannot certify stale extra derived rows" do
    Repo.insert!(%Work{id: "T9001", title: "Alpha", text_role: "root"})
    Repo.insert!(%Work{id: "T9002", title: "Beta", text_role: "commentary"})

    token =
      Derivations.begin_run(
        "relations_title",
        "bake-test",
        %{"mode" => "full"},
        %{"min_title" => 3}
      )

    assert {:ok, _} =
             Relations.assert(%{
               source_work_id: "T9002",
               target_work_id: "T9001",
               relation: "comments_on",
               method: "title_match",
               confidence: "probable"
             })

    receipt =
      Derivations.finish_run!(token, %{
        "failures" => 0,
        "expected_output_count" => 0
      })

    assert receipt.status == "partial"
    assert receipt.stats["input_changed_during_run"] == false
    assert receipt.stats["expected_output_count"] == 0
    assert receipt.stats["output_count"] == 1
    assert receipt.stats["output_count_matches_expected"] == false
  end

  test "a producer must state its expected output cardinality" do
    token =
      Derivations.begin_run(
        "relations_title",
        "bake-test",
        %{"mode" => "full"},
        %{"min_title" => 3}
      )

    assert_raise ArgumentError, ~r/expected_output_count/, fn ->
      Derivations.finish_run!(token, %{"failures" => 0})
    end
  end
end
