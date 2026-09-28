defmodule PramanaWeb.ReviewerJudgmentTest do
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Pilot.Scope
  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Release.Selection
  alias Pramana.Reviewer.Grant
  alias Pramana.Reviewer.Judgment
  alias Pramana.ReviewerAccess
  alias PramanaWeb.ReviewerEndpoint

  setup do
    start_supervised!(ReviewerEndpoint)
    {:ok, artifact} = Scope.build(scope_input())

    path =
      Path.join(System.tmp_dir!(), "pramana-review-#{System.unique_integer([:positive])}.json")

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
    relation = seed_case!(artifact)

    {:ok, account, credential} =
      ReviewerAccess.provision(
        "reviewer.case",
        "silent principal",
        artifact["scope_content_sha256"],
        "operator-1"
      )

    %{artifact: artifact, account: account, credential: credential, relation: relation}
  end

  test "a granted reviewer sees source context and appends an attributed judgment", context do
    login = login("reviewer.case", context.credential)
    relation = context.relation
    home = get("/", login)
    assert home.status == 200
    assert home.resp_body =~ "/reviews/#{relation.id}"

    page = get("/reviews/#{relation.id}", login)
    assert page.status == 200
    assert page.resp_body =~ "first commentary"
    assert page.resp_body =~ "alternative root"
    assert page.resp_body =~ "Edition identity is disputed"
    assert page.resp_body =~ "pramana:cbeta.T:T1800_001@p0001a01"
    assert page.resp_body =~ "Shared text alone does not prove direction"

    posted = post(relation.id, login, page, submission(page))
    assert posted.status == 302

    [judgment] = Repo.all(Judgment)
    assert judgment.account_id == context.account.id
    assert Repo.get!(Grant, judgment.grant_id).account_id == context.account.id
    assert judgment.assertion_id == relation.id
    assert judgment.assertion_fingerprint == field(page.resp_body, "assertion_fingerprint")
    assert judgment.scope_sha256 == context.artifact["scope_content_sha256"]
    assert judgment.release_id == "review-release"
    assert judgment.judgment == "disputed"
    assert judgment.rationale == "The quoted passage does not establish this edition."
    assert judgment.source_references == "T1800_001@p0001a01; T0400_001@p0002a01"
    assert Repo.get!(WorkRelation, relation.id).review_status == "needs_review"

    after_submit = get("/reviews/#{relation.id}", posted)
    assert after_submit.status == 200
    assert after_submit.resp_body =~ "Your previous judgments"
    assert after_submit.resp_body =~ judgment.rationale
  end

  test "an old form refuses changed assertion evidence or release", context do
    login = login("reviewer.case", context.credential)
    page = get("/reviews/#{context.relation.id}", login)
    attrs = submission(page)

    context.relation
    |> Ecto.Changeset.change(evidence: %{"new" => "evidence"})
    |> Repo.update!()

    assert post(context.relation.id, login, page, attrs).status == 409
    assert Repo.aggregate(Judgment, :count) == 0

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

    assert post(context.relation.id, login, page, attrs).status == 409
    assert Repo.aggregate(Judgment, :count) == 0
  end

  test "disagreeing reviewers keep separate append-only histories", context do
    first_login = login("reviewer.case", context.credential)
    first_page = get("/reviews/#{context.relation.id}", first_login)

    assert post(context.relation.id, first_login, first_page, submission(first_page)).status ==
             302

    {:ok, second_account, second_credential} =
      ReviewerAccess.provision(
        "reviewer.second",
        "Second reviewer",
        context.artifact["scope_content_sha256"],
        "operator-1"
      )

    second_login = login("reviewer.second", second_credential)
    second_page = get("/reviews/#{context.relation.id}", second_login)
    refute second_page.resp_body =~ "The quoted passage does not establish this edition."

    second_attrs =
      submission(second_page)
      |> Map.put("judgment", "supported")
      |> Map.put("rationale", "The cited colophon names this exact witness.")

    assert post(context.relation.id, second_login, second_page, second_attrs).status == 302
    assert Repo.aggregate(Judgment, :count) == 2

    assert Repo.get_by!(Judgment, account_id: context.account.id).judgment == "disputed"
    assert Repo.get_by!(Judgment, account_id: second_account.id).judgment == "supported"

    first_history = get("/reviews/#{context.relation.id}", first_login).resp_body
    assert first_history =~ "The quoted passage does not establish this edition."
    refute first_history =~ "The cited colophon names this exact witness."
    assert Repo.get!(WorkRelation, context.relation.id).review_status == "needs_review"
  end

  test "an invalid configured artifact exposes no cases or submission path", context do
    File.write!(System.fetch_env!("PRAMANA_REVIEW_SCOPE_PATH"), "{}")
    login = login("reviewer.case", context.credential)
    assert get("/reviews/#{context.relation.id}", login).status == 503
    assert get("/", login).resp_body =~ "No current review cases are available"
    assert Repo.aggregate(Judgment, :count) == 0
  end

  test "anonymous, ungranted, forged and revoked submissions leave no judgment", context do
    relation = context.relation
    assert get("/reviews/#{relation.id}", nil).status == 302

    {:ok, _other, other_credential} =
      ReviewerAccess.provision("reviewer.other", "Other", String.duplicate("f", 64), "operator-1")

    other_login = login("reviewer.other", other_credential)
    assert get("/reviews/#{relation.id}", other_login).status == 404
    other_home = get("/", other_login)

    valid_login = login("reviewer.case", context.credential)
    page = get("/reviews/#{relation.id}", valid_login)
    attrs = submission(page)
    assert post(relation.id, other_login, other_home, attrs).status == 409

    assert post(relation.id, valid_login, page, Map.put(attrs, "account_id", "forged")).status ==
             400

    assert :ok =
             ReviewerAccess.revoke_scope(
               "reviewer.case",
               context.artifact["scope_content_sha256"],
               "operator-1"
             )

    assert post(relation.id, valid_login, page, attrs).status == 302
    assert Repo.aggregate(Judgment, :count) == 0
  end

  defp login(login_id, credential) do
    page = ReviewerEndpoint.call(Plug.Test.conn(:get, "/login"), [])
    csrf = field(page.resp_body, "_csrf_token")

    Plug.Test.conn(
      :post,
      "/login",
      URI.encode_query(%{
        "_csrf_token" => csrf,
        "login_id" => login_id,
        "credential" => credential
      })
    )
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> Plug.Test.recycle_cookies(page)
    |> ReviewerEndpoint.call([])
  end

  defp get(path, cookies) do
    conn = Plug.Test.conn(:get, path)
    conn = if cookies, do: Plug.Test.recycle_cookies(conn, cookies), else: conn
    ReviewerEndpoint.call(conn, [])
  end

  defp post(id, cookies, page, attrs) do
    attrs = Map.put(attrs, "_csrf_token", field(page.resp_body, "_csrf_token"))

    Plug.Test.conn(:post, "/reviews/#{id}", URI.encode_query(attrs))
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> Plug.Test.recycle_cookies(cookies)
    |> ReviewerEndpoint.call([])
  end

  defp submission(page) do
    %{
      "scope_sha256" => field(page.resp_body, "scope_sha256"),
      "release_id" => field(page.resp_body, "release_id"),
      "assertion_fingerprint" => field(page.resp_body, "assertion_fingerprint"),
      "judgment" => "disputed",
      "rationale" => "The quoted passage does not establish this edition.",
      "source_references" => "T1800_001@p0001a01; T0400_001@p0002a01"
    }
  end

  defp field(body, name) do
    [_, value] = Regex.run(~r/name="#{name}" value="([^"]+)"/, body)
    value
  end

  defp seed_case!(artifact) do
    Repo.insert!(%Source{id: "cbeta", name: "CBETA", license_class: "nc"})
    Repo.insert!(%Witness{id: "T", name: "Taishō"})

    Repo.insert!(%Work{
      id: "T1800",
      title: "first commentary",
      text_role: "commentary",
      composition_origin: "chinese",
      attributed_author: "Synthetic reviewer fixture"
    })

    Repo.insert!(%Work{
      id: "T0400",
      title: "alternative root",
      text_role: "root",
      composition_origin: "chinese"
    })

    quote_text = "如是我聞此處只是相同的文字不能證明版本關係"
    quote_sha256 = hash(quote_text)

    source_text =
      Repo.insert!(%Text{
        source_id: "cbeta",
        witness_id: "T",
        work_id: "T1800",
        urn_prefix: "pramana:cbeta.T:T1800",
        body: quote_text,
        body_sha256: quote_sha256
      })

    target_text =
      Repo.insert!(%Text{
        source_id: "cbeta",
        witness_id: "T",
        work_id: "T0400",
        urn_prefix: "pramana:cbeta.T:T0400",
        body: quote_text,
        body_sha256: quote_sha256
      })

    Repo.insert!(%Quotation{
      text: quote_text,
      text_sha256: quote_sha256,
      length: String.length(quote_text),
      a_text_id: source_text.id,
      a_work_id: "T1800",
      a_urn: "pramana:cbeta.T:T1800_001@p0001a01",
      a_char_start: 0,
      a_char_end: String.length(quote_text),
      b_text_id: target_text.id,
      b_work_id: "T0400",
      b_urn: "pramana:cbeta.T:T0400_001@p0002a01",
      b_char_start: 0,
      b_char_end: String.length(quote_text),
      bake_id: "review-bake"
    })

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

    relation
  end

  defp scope_input do
    demand_roots =
      for n <- 0..9 do
        work("T02" <> String.pad_leading(Integer.to_string(n), 2, "0"), "root", 100 + n)
      end

    citers =
      for n <- 0..9 do
        work("T17" <> String.pad_leading(Integer.to_string(n), 2, "0"), "commentary", 500 + n)
      end

    agamas = for id <- ~w(T0001 T0026 T0099 T0125), do: work(id, "root", 100)

    quotation_rows =
      Enum.zip(citers, demand_roots)
      |> Enum.map(fn {citer, root} ->
        %{
          a_work_id: citer.work_id,
          b_work_id: root.work_id,
          text_sha256: hash(citer.work_id <> root.work_id),
          length: 20
        }
      end)

    base_relation = %{
      source_work_id: "T1800",
      target_work_id: "T0400",
      target_work_ref: nil,
      relation: "comments_on",
      scope: "whole_work",
      target_urn: nil,
      confidence: "uncertain",
      method: "shared_text",
      evidence: %{"fixture" => true},
      review_status: "needs_review",
      review_reason: "Edition identity is disputed"
    }

    %{
      release: %{
        release_id: "review-release",
        source_bake_id: "review-bake",
        translation_set_id: "v2:review-translation",
        vector_set_id: "v2:review-vector",
        stamped_at: "2026-09-28T00:00:00Z"
      },
      works:
        agamas ++
          demand_roots ++
          citers ++
          [work("T1800", "commentary", 600), work("T0400", "root", 100)],
      quotation_rows: quotation_rows,
      relation_rows: [
        base_relation,
        %{
          base_relation
          | target_work_id: "T0200",
            method: "title_match",
            confidence: "certain",
            review_status: "unflagged",
            review_reason: nil
        }
      ],
      alignment_rows: []
    }
  end

  defp work(id, role, date_start) do
    title =
      Map.get(
        %{
          "T0001" => "長阿含經",
          "T0026" => "中阿含經",
          "T0099" => "雜阿含經",
          "T0125" => "增壹阿含經",
          "T1800" => "first commentary",
          "T0400" => "alternative root"
        },
        id,
        id
      )

    %{
      work_id: id,
      title: title,
      text_role: role,
      division:
        cond do
          id in ~w(T0001 T0026 T0099 T0125) -> "阿含部"
          role == "root" -> "經集部"
          true -> "經疏部"
        end,
      date_start: date_start,
      date_end: date_start + 50
    }
  end

  defp hash(value), do: value |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end
