defmodule Pramana.DerivationsTest do
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.CommentaryAlignment
  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Segment
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

  test "citation segment geometry is part of quotation and alignment input identity" do
    Repo.insert!(%Source{id: "cbeta", name: "CBETA"})
    Repo.insert!(%Witness{id: "T", name: "Taishō"})
    Repo.insert!(%Work{id: "T9001", title: "Root", text_role: "root"})
    Repo.insert!(%Work{id: "T9002", title: "Commentary", text_role: "commentary"})

    root =
      Repo.insert!(%Text{
        work_id: "T9001",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T9001",
        body: "root text",
        body_sha256: Derivations.digest("root text"),
        char_count: 9
      })

    commentary =
      Repo.insert!(%Text{
        work_id: "T9002",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T9002",
        body: "commentary text",
        body_sha256: Derivations.digest("commentary text"),
        char_count: 15
      })

    segment =
      Repo.insert!(%Segment{
        text_id: root.id,
        urn: "pramana:cbeta.T:T9001_001@p0001a01",
        ordinal: 0,
        content: "root text",
        content_sha256: Derivations.digest("root text"),
        char_start: 0,
        char_end: 9,
        byte_start: 0,
        byte_end: 9
      })

    assert {:ok, _} =
             Relations.assert(%{
               source_work_id: commentary.work_id,
               target_work_id: root.work_id,
               relation: "comments_on",
               method: "catalogue",
               confidence: "certain"
             })

    quotation_token =
      Derivations.begin_run(
        "quotations_scan",
        "bake-test",
        %{"source" => "cbeta", "witness" => "T", "division" => nil, "work" => nil},
        %{"min_length" => 20}
      )

    alignment_token =
      Derivations.begin_run(
        "commentary_align",
        "bake-test",
        %{"work" => nil},
        %{}
      )

    segment
    |> Ecto.Changeset.change(char_end: 8)
    |> Repo.update!()

    refute quotation_token.input_digest == Derivations.current_input_digest(quotation_token)
    refute alignment_token.input_digest == Derivations.current_input_digest(alignment_token)
  end

  test "output digests cover the served quotation and alignment text" do
    Repo.insert!(%Source{id: "cbeta", name: "CBETA"})
    Repo.insert!(%Witness{id: "T", name: "Taishō"})
    Repo.insert!(%Work{id: "T9001", title: "Root", text_role: "root"})
    Repo.insert!(%Work{id: "T9002", title: "Commentary", text_role: "commentary"})

    root =
      Repo.insert!(%Text{
        work_id: "T9001",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T9001",
        body: "root body",
        body_sha256: Derivations.digest("root body"),
        char_count: 9
      })

    commentary =
      Repo.insert!(%Text{
        work_id: "T9002",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T9002",
        body: "commentary body",
        body_sha256: Derivations.digest("commentary body"),
        char_count: 15
      })

    quotation =
      Repo.insert!(%Quotation{
        text: String.duplicate("a", 20),
        text_sha256: String.duplicate("1", 64),
        length: 20,
        a_text_id: root.id,
        a_work_id: root.work_id,
        a_urn: "pramana:cbeta.T:T9001_001@p0001a01",
        a_char_start: 0,
        a_char_end: 20,
        b_text_id: commentary.id,
        b_work_id: commentary.work_id,
        b_urn: "pramana:cbeta.T:T9002_001@p0001a01",
        b_char_start: 0,
        b_char_end: 20,
        bake_id: "bake-test"
      })

    quotation_token =
      Derivations.begin_run(
        "quotations_scan",
        "bake-test",
        %{"source" => "cbeta", "witness" => "T", "division" => nil, "work" => nil},
        %{"min_length" => 20}
      )

    {quotation_before, 1} = Derivations.current_output_snapshot(quotation_token)

    quotation
    |> Ecto.Changeset.change(text: String.duplicate("b", 20))
    |> Repo.update!()

    {quotation_after, 1} = Derivations.current_output_snapshot(quotation_token)
    refute quotation_before == quotation_after

    alignment =
      Repo.insert!(%CommentaryAlignment{
        lemma: "abcdefgh",
        lemma_sha256: String.duplicate("2", 64),
        length: 8,
        commentary_text_id: commentary.id,
        commentary_work_id: commentary.work_id,
        commentary_urn: "pramana:cbeta.T:T9002_001@p0001a01",
        commentary_char_start: 0,
        commentary_char_end: 8,
        root_text_id: root.id,
        root_work_id: root.work_id,
        root_urn: "pramana:cbeta.T:T9001_001@p0001a01",
        root_char_start: 0,
        root_char_end: 8,
        method: "lemma_match",
        confidence: "probable",
        bake_id: "bake-test"
      })

    alignment_token =
      Derivations.begin_run(
        "commentary_align",
        "bake-test",
        %{"work" => nil},
        %{}
      )

    {alignment_before, 1} = Derivations.current_output_snapshot(alignment_token)

    alignment
    |> Ecto.Changeset.change(lemma: "ijklmnop")
    |> Repo.update!()

    {alignment_after, 1} = Derivations.current_output_snapshot(alignment_token)
    refute alignment_before == alignment_after
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
