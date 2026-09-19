defmodule Pramana.DerivationsTest do
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
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

  test "commentary receipts become stale when the source role changes" do
    Repo.insert!(%Source{id: "cbeta", name: "CBETA"})
    Repo.insert!(%Witness{id: "T", name: "Taishō"})
    Repo.insert!(%Work{id: "T9001", title: "Root", text_role: "root"})
    Repo.insert!(%Work{id: "T9002", title: "Commentary", text_role: "commentary"})

    for {work_id, body} <- [{"T9001", "root text"}, {"T9002", "commentary text"}] do
      Repo.insert!(%Text{
        work_id: work_id,
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:#{work_id}",
        body: body,
        body_sha256: Derivations.digest(body),
        char_count: String.length(body)
      })
    end

    assert {:ok, _} =
             Relations.assert(%{
               source_work_id: "T9002",
               target_work_id: "T9001",
               relation: "comments_on",
               method: "catalogue",
               confidence: "certain"
             })

    token =
      Derivations.begin_run(
        "commentary_align",
        "bake-test",
        %{"work" => nil},
        %{}
      )

    "T9002"
    |> then(&Repo.get!(Work, &1))
    |> Ecto.Changeset.change(text_role: "subcommentary")
    |> Repo.update!()

    refute token.input_digest == Derivations.current_input_digest(token)
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
