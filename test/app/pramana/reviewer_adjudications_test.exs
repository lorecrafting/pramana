defmodule Pramana.ReviewerAdjudicationsTest do
  use Pramana.DataCase, async: false
  import ExUnit.CaptureIO

  alias Mix.Tasks.Pramana.Reviews, as: ReviewsTask
  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Derivations
  alias Pramana.Pilot.Scope
  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Relations
  alias Pramana.Release.Selection
  alias Pramana.Reviewer.Adjudications
  alias Pramana.Reviewer.Disposition
  alias Pramana.Reviewer.Reviews
  alias Pramana.ReviewerAccess
  alias Pramana.ReviewerScopeFixture

  setup do
    {:ok, artifact} = Scope.build(ReviewerScopeFixture.scope_input())

    path =
      Path.join(System.tmp_dir!(), "pramana-decision-#{System.unique_integer([:positive])}.json")

    File.write!(path, ScopeArtifact.encode(artifact))
    previous = System.get_env("PRAMANA_REVIEW_SCOPE_PATH")
    System.put_env("PRAMANA_REVIEW_SCOPE_PATH", path)

    on_exit(fn ->
      File.rm(path)

      if previous,
        do: System.put_env("PRAMANA_REVIEW_SCOPE_PATH", previous),
        else: System.delete_env("PRAMANA_REVIEW_SCOPE_PATH")
    end)

    release =
      Repo.insert!(%ReleaseSchema{
        release_id: "review-release",
        source_bake_id: "review-bake",
        translation_set_id: "v2:review-translation",
        vector_set_id: "v2:review-vector",
        translations_count: 0,
        vectors_count: 0,
        stamped_at: DateTime.utc_now()
      })

    Repo.insert!(%Selection{id: 1, release_id: release.id, selected_at: DateTime.utc_now()})

    Repo.insert!(%Work{id: "T1800", title: "first commentary", text_role: "commentary"})
    Repo.insert!(%Work{id: "T0400", title: "alternative root", text_role: "root"})

    assertion = hd(artifact["review_cases"])["assertion"]

    relation =
      %WorkRelation{}
      |> WorkRelation.changeset(%{
        source_work_id: "T1800",
        target_work_id: "T0400",
        relation: "comments_on",
        method: assertion["method"],
        confidence: assertion["confidence"],
        evidence: assertion["evidence"]
      })
      |> Ecto.Changeset.change(
        review_status: "needs_review",
        review_reason: assertion["review_reason"]
      )
      |> Repo.insert!()

    {:ok, account, _credential} =
      ReviewerAccess.provision(
        "reviewer.decision",
        "silent principal",
        artifact["scope_content_sha256"],
        "operator-1"
      )

    {:ok, review_case} =
      Reviews.get_case(artifact, [artifact["scope_content_sha256"]], account.id, relation.id)

    {:ok, judgment} =
      Reviews.submit(account, artifact, relation.id, %{
        "scope_sha256" => review_case.scope_sha256,
        "release_id" => review_case.release_id,
        "assertion_fingerprint" => review_case.fingerprint,
        "judgment" => "disputed",
        "rationale" => "The passage does not name this edition.",
        "source_references" => "T1800_001@p0001a01; T0400_001@p0002a01"
      })

    %{
      artifact: artifact,
      relation: relation,
      fingerprint: review_case.fingerprint,
      judgment: judgment,
      path: path,
      release: release
    }
  end

  test "operator can inspect attributed and stale judgments", context do
    {:ok, current} = Adjudications.inspect_case(context.artifact, context.relation.id)
    assert current.in_scope
    assert current.fingerprint == context.fingerprint
    assert [%{judgment: judgment, display_name: "silent principal"}] = current.judgments
    assert judgment.id == context.judgment.id

    context.relation
    |> Ecto.Changeset.change(evidence: %{"changed" => true})
    |> Repo.update!()

    {:ok, stale} = Adjudications.inspect_case(context.artifact, context.relation.id)
    refute stale.in_scope
    refute stale.fingerprint == context.fingerprint
    assert hd(stale.judgments).judgment.assertion_fingerprint == context.fingerprint

    output =
      capture_io(fn ->
        ReviewsTask.run([
          "show",
          "--scope",
          context.path,
          "--assertion-id",
          "#{context.relation.id}"
        ])
      end)

    assert output =~ "Matches selected scope: false"
    assert output =~ "(STALE) by silent principal"
  end

  test "supported disposition preserves evidence and invalidates old scope and receipt",
       context do
    token =
      Derivations.begin_run("relations_shared_text", "review-bake", %{}, %{"min_passages" => 1})

    receipt = Derivations.finish_run!(token, %{"failures" => 0, "expected_output_count" => 1})
    assert receipt.status == "complete"
    assert Derivations.current?(receipt)

    assert {:ok, decision} =
             Adjudications.decide(
               context.artifact,
               context.relation.id,
               context.fingerprint,
               decision_attrs("supported")
             )

    assert decision.assertion_fingerprint == context.fingerprint
    assert decision.assertion_snapshot["assertion"]["review_status"] == "needs_review"
    assert decision.operator_id == "operator-1"
    assert Repo.get!(WorkRelation, context.relation.id).review_status == "unflagged"
    refute Derivations.current?(receipt)
    assert Reviews.configured_scope() == {:error, :invalidated_scope}

    assert {:error, :stale_or_unreviewed} =
             Adjudications.decide(
               context.artifact,
               context.relation.id,
               context.fingerprint,
               decision_attrs("supported")
             )

    assert Repo.aggregate(Disposition, :count) == 1

    assert Derivations.shared_text_carryover_count([]) == 1

    renewed =
      "relations_shared_text"
      |> Derivations.begin_run("review-bake", %{}, %{"min_passages" => 1})
      |> Derivations.finish_run!(%{"failures" => 0, "expected_output_count" => 1})

    assert renewed.status == "complete"
    assert Derivations.current?(renewed)

    {:ok, history} = Adjudications.inspect_case(context.artifact, context.relation.id)
    refute history.in_scope
    assert Enum.map(history.dispositions, & &1.id) == [decision.id]
    assert Enum.map(history.judgments, & &1.judgment.id) == [context.judgment.id]
  end

  test "a changed supported assertion reopens review; unchanged reassertion does not", context do
    assert {:ok, _} =
             Adjudications.decide(
               context.artifact,
               context.relation.id,
               context.fingerprint,
               decision_attrs("supported")
             )

    attrs = %{
      source_work_id: "T1800",
      target_work_id: "T0400",
      relation: "comments_on",
      method: "shared_text",
      confidence: "uncertain",
      evidence: %{"fixture" => true}
    }

    assert {:ok, _} = Relations.assert(attrs)
    assert Repo.get!(WorkRelation, context.relation.id).review_status == "unflagged"

    assert {:ok, _} = Relations.assert(%{attrs | evidence: %{"fixture" => false}})
    reopened = Repo.get!(WorkRelation, context.relation.id)
    assert reopened.review_status == "needs_review"
    assert reopened.review_reason == "Assertion changed after operator support"
    assert Repo.aggregate(Disposition, :count) == 1
  end

  test "an old scope cannot accept another case after a supported decision", context do
    input = ReviewerScopeFixture.scope_input()
    second = input.relation_rows |> hd() |> Map.put(:target_work_id, "T0201")
    {:ok, artifact} = Scope.build(%{input | relation_rows: input.relation_rows ++ [second]})
    scope_sha = artifact["scope_content_sha256"]

    Repo.insert!(%Work{id: "T0201", title: "second root", text_role: "root"})

    other =
      %WorkRelation{}
      |> WorkRelation.changeset(%{
        source_work_id: "T1800",
        target_work_id: "T0201",
        relation: "comments_on",
        method: second.method,
        confidence: second.confidence,
        evidence: second.evidence
      })
      |> Ecto.Changeset.change(
        review_status: "needs_review",
        review_reason: second.review_reason
      )
      |> Repo.insert!()

    assert {:ok, _grant} =
             ReviewerAccess.grant_scope("reviewer.decision", scope_sha, "operator-1")

    account = Repo.get_by!(Pramana.Reviewer.Account, login_id: "reviewer.decision")
    assert {:ok, first} = Reviews.get_case(artifact, [scope_sha], account.id, context.relation.id)
    assert {:ok, next_case} = Reviews.get_case(artifact, [scope_sha], account.id, other.id)

    assert {:ok, _} =
             Reviews.submit(
               account,
               artifact,
               context.relation.id,
               submission_attrs(first)
             )

    assert {:ok, _} =
             Adjudications.decide(
               artifact,
               context.relation.id,
               first.fingerprint,
               decision_attrs("supported")
             )

    assert {:error, :unavailable_scope} = Reviews.list_cases(artifact, [scope_sha])

    assert {:error, :unavailable_case} =
             Reviews.get_case(artifact, [scope_sha], account.id, other.id)

    assert {:error, :stale_or_unauthorized} =
             Reviews.submit(account, artifact, other.id, submission_attrs(next_case))
  end

  test "disputed and unresolved decisions retain review cases without accepted links", context do
    output =
      capture_io(fn ->
        ReviewsTask.run([
          "decide",
          "--scope",
          context.path,
          "--assertion-id",
          "#{context.relation.id}",
          "--fingerprint",
          context.fingerprint,
          "--disposition",
          "disputed",
          "--rationale",
          "Reviewed the cited edition and passage.",
          "--source-references",
          "T1800_001@p0001a01; T0400_001@p0002a01",
          "--operator",
          "operator-1"
        ])
      end)

    assert output =~ "Recorded disputed disposition"

    assert {:ok, %Disposition{disposition: "unresolved"}} =
             Adjudications.decide(
               context.artifact,
               context.relation.id,
               context.fingerprint,
               decision_attrs("unresolved")
             )

    assert Repo.get!(WorkRelation, context.relation.id).review_status == "needs_review"
    assert {:ok, _} = Reviews.configured_scope()

    assert {:ok, [%{id: id}]} =
             Reviews.list_cases(context.artifact, [context.artifact["scope_content_sha256"]])

    assert id == context.relation.id
    assert Repo.aggregate(Disposition, :count) == 2
  end

  test "stale evidence or release refuses a decision", context do
    context.relation
    |> Ecto.Changeset.change(evidence: %{"changed" => true})
    |> Repo.update!()

    assert {:error, :stale_or_unreviewed} =
             Adjudications.decide(
               context.artifact,
               context.relation.id,
               context.fingerprint,
               decision_attrs("supported")
             )

    context.relation
    |> Ecto.Changeset.change(evidence: %{"fixture" => true})
    |> Repo.update!()

    newer =
      Repo.insert!(%ReleaseSchema{
        release_id: "other-release",
        source_bake_id: "review-bake",
        translation_set_id: "v2:review-translation",
        vector_set_id: "v2:review-vector",
        translations_count: 0,
        vectors_count: 0,
        stamped_at: DateTime.utc_now()
      })

    Repo.get!(Selection, 1)
    |> Ecto.Changeset.change(release_id: newer.id)
    |> Repo.update!()

    assert {:error, :stale_or_unreviewed} =
             Adjudications.decide(
               context.artifact,
               context.relation.id,
               context.fingerprint,
               decision_attrs("supported")
             )

    assert Repo.aggregate(Disposition, :count) == 0
    assert Repo.get!(WorkRelation, context.relation.id).review_status == "needs_review"
  end

  test "a supported decision requires an attributed review of the current assertion", context do
    Repo.delete!(context.judgment)

    assert {:error, :stale_or_unreviewed} =
             Adjudications.decide(
               context.artifact,
               context.relation.id,
               context.fingerprint,
               decision_attrs("supported")
             )

    assert Repo.aggregate(Disposition, :count) == 0
    assert Repo.get!(WorkRelation, context.relation.id).review_status == "needs_review"
  end

  defp decision_attrs(outcome) do
    %{
      disposition: outcome,
      rationale: "Reviewed the cited edition and passage.",
      source_references: "T1800_001@p0001a01; T0400_001@p0002a01",
      operator_id: "operator-1"
    }
  end

  defp submission_attrs(review_case) do
    %{
      "scope_sha256" => review_case.scope_sha256,
      "release_id" => review_case.release_id,
      "assertion_fingerprint" => review_case.fingerprint,
      "judgment" => "disputed",
      "rationale" => "The edition is unclear.",
      "source_references" => "T1800_001@p0001a01"
    }
  end
end
