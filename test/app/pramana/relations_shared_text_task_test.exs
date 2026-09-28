defmodule Pramana.RelationsSharedTextTaskTest do
  use Pramana.DataCase

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pramana.Relations.SharedText
  alias Pramana.Corpus.DerivationRun
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Relations
  alias Pramana.Repo

  test "the default shared-text command reports without writing a receipt" do
    output = capture_io(fn -> SharedText.run([]) end)

    assert output =~ "DRY RUN — nothing written; add --write"
    assert Repo.get_by(DerivationRun, derivation: "relations_shared_text") == nil
  end

  test "a flagged retained assertion is counted explicitly, while an unflagged stale row keeps the receipt partial" do
    for id <- ~w(T9001 T9002 T9003) do
      Repo.insert!(%Work{
        id: id,
        title: id,
        text_role: if(id == "T9001", do: "root", else: "commentary")
      })
    end

    for source <- ~w(T9002 T9003) do
      assert {:ok, _} =
               Relations.assert(%{
                 source_work_id: source,
                 target_work_id: "T9001",
                 relation: "comments_on",
                 method: "shared_text",
                 confidence: "uncertain"
               })
    end

    Repo.get_by!(WorkRelation, source_work_id: "T9002")
    |> Ecto.Changeset.change(review_status: "needs_review", review_reason: "Edition uncertain")
    |> Repo.update!()

    capture_io(fn -> SharedText.run(["--write"]) end)
    first = Repo.one!(from r in DerivationRun, order_by: [desc: r.id], limit: 1)
    assert first.status == "partial"
    assert first.stats["retained_carryovers"] == 1
    assert first.stats["expected_output_count"] == 1
    assert first.stats["output_count"] == 2

    Repo.get_by!(WorkRelation, source_work_id: "T9003")
    |> Ecto.Changeset.change(review_status: "needs_review", review_reason: "Edition uncertain")
    |> Repo.update!()

    capture_io(fn -> SharedText.run(["--write"]) end)
    second = Repo.one!(from r in DerivationRun, order_by: [desc: r.id], limit: 1)
    assert second.status == "complete"
    assert second.stats["retained_carryovers"] == 2
    assert second.stats["expected_output_count"] == 2
    assert second.stats["output_count"] == 2
  end
end
