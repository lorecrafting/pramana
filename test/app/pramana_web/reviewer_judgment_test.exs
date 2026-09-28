defmodule PramanaWeb.ReviewerJudgmentTest do
  use Pramana.DataCase, async: false

  alias Plug.Conn.Query
  alias Plug.Test, as: PlugTest
  alias Pramana.Accounts
  alias Pramana.AccountsFixtures
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
  alias Pramana.Reviewer.RightsJudgment
  alias Pramana.Reviewer.RightsReviews
  alias Pramana.Reviewer.WorkJudgment
  alias Pramana.Reviewer.WorkReviews
  alias Pramana.ReviewerAccess
  alias Pramana.ReviewerScopeFixture
  alias PramanaWeb.Endpoint
  alias PramanaWeb.ReviewerEndpoint

  setup do
    start_supervised!(ReviewerEndpoint)
    {:ok, artifact} = Scope.build(ReviewerScopeFixture.scope_input())

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

    for work <- artifact["works"], work["work_id"] not in ~w(T1800 T0400) do
      Repo.insert!(%Work{
        id: work["work_id"],
        title: work["title"],
        text_role: work["text_role"],
        division: work["division"]
      })
    end

    account = AccountsFixtures.user_fixture()

    {:ok, _} =
      ReviewerAccess.grant_scope(account.email, artifact["scope_content_sha256"], "operator-1")

    %{artifact: artifact, account: account, relation: relation}
  end

  test "a granted reviewer sees source context and appends an attributed judgment", context do
    login = login(context.account)
    relation = context.relation
    home = get("/", login)
    assert home.status == 200
    assert get("/reviews", login).status == 200
    assert home.resp_body =~ "/reviews/#{relation.id}"

    page = get("/reviews/#{relation.id}", login)
    assert page.status == 200
    assert page.resp_body =~ "first commentary"
    assert page.resp_body =~ "alternative root"
    assert page.resp_body =~ "Edition identity is disputed"
    assert page.resp_body =~ "pramana:cbeta.T:T1800_001@p0001a01"
    assert page.resp_body =~ "Shared wording alone does not establish the direction"
    assert page.resp_body =~ "T1800_001@p0001a01 · characters [2, 23)"
    assert page.resp_body =~ "T0400_001@p0002a01 · characters [7, 28)"

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

  test "a local reader session reaches review only while its exact grant is active", context do
    unless Process.whereis(Endpoint), do: start_supervised!(Endpoint)
    assert Endpoint.call(PlugTest.conn(:get, "/?q=佛"), []).status == 200
    assert Endpoint.call(PlugTest.conn(:get, "/reviews"), []).status == 302

    ungranted = AccountsFixtures.user_fixture()
    ungranted_token = Accounts.generate_user_session_token(ungranted)

    assert PlugTest.conn(:get, "/reviews")
           |> PlugTest.init_test_session(%{user_token: ungranted_token})
           |> Endpoint.call([])
           |> Map.get(:status) == 403

    ungranted_reader =
      PlugTest.conn(:get, "/")
      |> PlugTest.init_test_session(%{user_token: ungranted_token})
      |> Endpoint.call([])

    refute ungranted_reader.resp_body =~ ~s(href="/reviews")

    token = Accounts.generate_user_session_token(context.account)

    session =
      PlugTest.conn(:get, "/reviews")
      |> PlugTest.init_test_session(%{user_token: token})
      |> Endpoint.call([])

    assert session.status == 200
    assert session.resp_body =~ "/reviews/#{context.relation.id}"

    reader =
      PlugTest.conn(:get, "/")
      |> PlugTest.recycle_cookies(session)
      |> Endpoint.call([])

    assert reader.status == 200
    assert reader.resp_body =~ ~s(href="/reviews")

    page =
      PlugTest.conn(:get, "/reviews/#{context.relation.id}")
      |> PlugTest.recycle_cookies(session)
      |> Endpoint.call([])

    assert page.status == 200
    assert page.resp_body =~ ~s(href="/reviews")

    attrs = submission(page)

    posted =
      PlugTest.conn(
        :post,
        "/reviews/#{context.relation.id}",
        Query.encode(%{
          "review" => attrs,
          "_csrf_token" => field(page.resp_body, "_csrf_token")
        })
      )
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> PlugTest.recycle_cookies(page)
      |> Endpoint.call([])

    assert posted.status == 302

    assert Repo.get_by!(Judgment, account_id: context.account.id).assertion_id ==
             context.relation.id

    assert :ok =
             ReviewerAccess.revoke_scope(
               context.account.email,
               context.artifact["scope_content_sha256"],
               "operator-1"
             )

    denied =
      PlugTest.conn(:get, "/reviews")
      |> PlugTest.recycle_cookies(session)
      |> Endpoint.call([])

    assert denied.status == 403
  end

  test "public-data mode keeps local review routes and grants out of the reader", context do
    previous = System.get_env("PRAMANA_PUBLIC")
    System.put_env("PRAMANA_PUBLIC", "1")

    on_exit(fn ->
      if previous,
        do: System.put_env("PRAMANA_PUBLIC", previous),
        else: System.delete_env("PRAMANA_PUBLIC")
    end)

    token = Accounts.generate_user_session_token(context.account)

    reader =
      PlugTest.conn(:get, "/")
      |> PlugTest.init_test_session(%{user_token: token})
      |> Endpoint.call([])

    assert reader.status == 200
    refute reader.resp_body =~ ~s(href="/reviews")

    route =
      PlugTest.conn(:get, "/reviews")
      |> PlugTest.init_test_session(%{user_token: token})
      |> Endpoint.call([])

    assert route.status == 404
  end

  test "the restricted reviewer database role can submit without corpus write grants", context do
    login = login(context.account)
    page = get("/reviews/#{context.relation.id}", login)
    work_page = get("/reviews/works/T1800", login)

    {:ok, _} =
      ReviewerAccess.grant_scope(
        context.account.email,
        context.artifact["scope_content_sha256"],
        "operator-1",
        "rights_signoff"
      )

    rights_page = get("/reviews/rights/cbeta-local", login)
    role = "pramana_review_test_#{System.unique_integer([:positive])}"

    Repo.query!("CREATE ROLE #{role} NOLOGIN")
    Repo.query!("GRANT USAGE ON SCHEMA public TO #{role}")

    Repo.query!("""
    GRANT SELECT ON users, users_tokens, reviewer_grants, reviewer_judgments,
      reviewer_dispositions, reviewer_work_judgments, reviewer_rights_judgments,
      work_relations, works, release_selection, releases TO #{role}
    """)

    Repo.query!("""
    GRANT INSERT ON reviewer_judgments, reviewer_work_judgments,
      reviewer_rights_judgments TO #{role}
    """)

    try do
      Repo.query!("SET LOCAL ROLE #{role}")
      assert post(context.relation.id, login, page, submission(page)).status == 302

      assert post_form("/reviews/works/T1800", login, work_page, "work_review", %{
               "scope_sha256" => field(work_page.resp_body, "scope_sha256", "work_review"),
               "release_id" => field(work_page.resp_body, "release_id", "work_review"),
               "work_fingerprint" =>
                 field(work_page.resp_body, "work_fingerprint", "work_review"),
               "judgment" => "needs_review",
               "rationale" => "Identity remains uncertain.",
               "source_references" => "CBETA T1800 catalogue"
             }).status == 302

      assert post_form("/reviews/rights/cbeta-local", login, rights_page, "rights_review", %{
               "scope_sha256" => field(rights_page.resp_body, "scope_sha256", "rights_review"),
               "release_id" => field(rights_page.resp_body, "release_id", "rights_review"),
               "item_fingerprint" =>
                 field(rights_page.resp_body, "item_fingerprint", "rights_review"),
               "decision" => "unresolved",
               "rationale" => "Terms need confirmation.",
               "evidence_references" => "CBETA terms"
             }).status == 302
    after
      Repo.query!("RESET ROLE")
    end

    assert Repo.get_by!(Judgment, account_id: context.account.id).judgment == "disputed"
    assert Repo.get_by!(WorkJudgment, account_id: context.account.id).judgment == "needs_review"
    assert Repo.get_by!(RightsJudgment, account_id: context.account.id).decision == "unresolved"
  end

  test "an old form refuses changed assertion evidence or release", context do
    login = login(context.account)
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
    first_login = login(context.account)
    first_page = get("/reviews/#{context.relation.id}", first_login)

    assert post(context.relation.id, first_login, first_page, submission(first_page)).status ==
             302

    second_account = AccountsFixtures.user_fixture()

    {:ok, _} =
      ReviewerAccess.grant_scope(
        second_account.email,
        context.artifact["scope_content_sha256"],
        "operator-1"
      )

    second_login = login(second_account)
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

  test "full-length Chinese fields reach the form", context do
    login = login(context.account)
    page = get("/reviews/#{context.relation.id}", login)

    attrs =
      submission(page)
      |> Map.put("rationale", String.duplicate("漢", 2_000))
      |> Map.put("source_references", String.duplicate("藏", 2_000))

    assert post(context.relation.id, login, page, attrs).status == 302
    judgment = Repo.get_by!(Judgment, account_id: context.account.id)
    assert judgment.rationale == attrs["rationale"]
    assert judgment.source_references == attrs["source_references"]
  end

  test "an invalid configured artifact exposes no cases or submission path", context do
    File.write!(System.fetch_env!("PRAMANA_REVIEW_SCOPE_PATH"), "{}")
    login = login(context.account)
    assert get("/reviews/#{context.relation.id}", login).status == 503
    assert get("/", login).status == 503
    assert Repo.aggregate(Judgment, :count) == 0
  end

  test "anonymous, ungranted, forged and revoked submissions leave no judgment", context do
    relation = context.relation
    assert get("/reviews/#{relation.id}", nil).status == 302

    other = AccountsFixtures.user_fixture()

    {:ok, _} =
      ReviewerAccess.grant_scope(other.email, String.duplicate("f", 64), "operator-1")

    other_login = login(other)
    assert get("/reviews/#{relation.id}", other_login).status == 404
    other_page = get("/users/settings", other_login)

    valid_login = login(context.account)
    page = get("/reviews/#{relation.id}", valid_login)
    attrs = submission(page)
    assert post(relation.id, other_page, other_page, attrs).status == 409

    assert post(relation.id, valid_login, page, Map.put(attrs, "account_id", "forged")).status ==
             400

    assert :ok =
             ReviewerAccess.revoke_scope(
               context.account.email,
               context.artifact["scope_content_sha256"],
               "operator-1"
             )

    assert post(relation.id, valid_login, page, attrs).status == 403
    assert Repo.aggregate(Judgment, :count) == 0
  end

  test "source recommendations are attributed, scoped and stopped by revocation", context do
    login = login(context.account)
    page = get("/reviews/works/T1800", login)
    assert page.status == 200
    assert page.resp_body =~ "first commentary"

    attrs = %{
      "scope_sha256" => field(page.resp_body, "scope_sha256", "work_review"),
      "release_id" => field(page.resp_body, "release_id", "work_review"),
      "work_fingerprint" => field(page.resp_body, "work_fingerprint", "work_review"),
      "judgment" => "needs_review",
      "rationale" => "The catalogue attribution requires a second witness.",
      "source_references" => "CBETA T1800 catalogue entry"
    }

    assert post_form("/reviews/works/T1800", login, page, "work_review", attrs).status == 302

    [judgment] = Repo.all(WorkJudgment)
    assert judgment.account_id == context.account.id
    assert judgment.work_id == "T1800"
    assert judgment.judgment == "needs_review"

    assert judgment.work_snapshot["work_metadata"]["attributed_author"] ==
             "Synthetic reviewer fixture"

    assert get("/reviews/works/T1800", login).resp_body =~ judgment.rationale

    assert :ok =
             ReviewerAccess.revoke_scope(
               context.account.email,
               context.artifact["scope_content_sha256"],
               "operator-1",
               "relation_review"
             )

    assert post_form("/reviews/works/T1800", login, page, "work_review", attrs).status == 403

    assert {:error, :stale_or_unauthorized} =
             WorkReviews.submit(context.account, context.artifact, "T1800", attrs)

    assert Repo.aggregate(WorkJudgment, :count) == 1
  end

  test "an edited source-work division invalidates an old form", context do
    login = login(context.account)
    page = get("/reviews/works/T1800", login)

    attrs = %{
      "scope_sha256" => field(page.resp_body, "scope_sha256", "work_review"),
      "release_id" => field(page.resp_body, "release_id", "work_review"),
      "work_fingerprint" => field(page.resp_body, "work_fingerprint", "work_review"),
      "judgment" => "needs_review",
      "rationale" => "The changed catalogue classification needs rechecking.",
      "source_references" => "CBETA T1800 catalogue entry"
    }

    Repo.get!(Work, "T1800")
    |> Ecto.Changeset.change(division: "新分類")
    |> Repo.update!()

    assert post_form("/reviews/works/T1800", login, page, "work_review", attrs).status == 409
    assert Repo.aggregate(WorkJudgment, :count) == 0
  end

  test "a rights-only signer lands on the rights workspace", context do
    signer = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    {:ok, _} =
      ReviewerAccess.grant_scope(
        signer.email,
        context.artifact["scope_content_sha256"],
        "operator-1",
        "rights_signoff"
      )

    login_page = get("/users/log-in", nil)

    session =
      post_form("/users/log-in", login_page, login_page, "user", %{
        "email" => signer.email,
        "password" => AccountsFixtures.valid_user_password()
      })

    assert session.status == 302
    assert {"location", "/reviews/rights"} in session.resp_headers
    assert get("/", session).status == 403

    index = get("/reviews/rights", session)
    assert index.status == 200
    assert index.resp_body =~ ~s(href="/reviews/rights")
    refute index.resp_body =~ ~s(href="/reviews")

    {:ok, _} =
      ReviewerAccess.grant_scope(
        signer.email,
        String.duplicate("f", 64),
        "operator-1"
      )

    next_login =
      post_form("/users/log-in", login_page, login_page, "user", %{
        "email" => signer.email,
        "password" => AccountsFixtures.valid_user_password()
      })

    assert {"location", "/reviews/rights"} in next_login.resp_headers

    unless Process.whereis(Endpoint), do: start_supervised!(Endpoint)

    local_page =
      PlugTest.conn(:get, "/")
      |> PlugTest.init_test_session(%{
        user_token: Accounts.generate_user_session_token(signer)
      })
      |> Endpoint.call([])

    assert local_page.resp_body =~ ~s(href="/reviews/rights")
    refute local_page.resp_body =~ ~s(href="/reviews")
  end

  test "rights decisions require their own grant and preserve exact use evidence", context do
    login = login(context.account)
    assert get("/reviews/rights", login).status == 403

    {:ok, _} =
      ReviewerAccess.grant_scope(
        context.account.email,
        context.artifact["scope_content_sha256"],
        "operator-1",
        "rights_signoff"
      )

    index = get("/reviews/rights", login)
    assert index.status == 200
    assert length(Regex.scan(~r/id="right-/, index.resp_body)) == 20
    assert index.resp_body =~ "Karashima / Kumārajīva"

    path = "/reviews/rights/dila-karashima-kumarajiva-local"
    page = get(path, login)
    assert page.status == 200
    assert page.resp_body =~ "T0262"

    attrs = %{
      "scope_sha256" => field(page.resp_body, "scope_sha256", "rights_review"),
      "release_id" => field(page.resp_body, "release_id", "rights_review"),
      "item_fingerprint" => field(page.resp_body, "item_fingerprint", "rights_review"),
      "decision" => "unresolved",
      "rationale" => "The digital-edition terms need confirmation for local lookup.",
      "evidence_references" => "DILA Karashima T0262 terms, checked 2026-09-28"
    }

    assert post_form(path, login, page, "rights_review", attrs).status == 302

    [judgment] = Repo.all(RightsJudgment)
    assert judgment.account_id == context.account.id
    assert judgment.item_id == "dila-karashima-kumarajiva-local"
    assert judgment.policy_snapshot["boundary"] =~ "T0262"
    assert judgment.decision == "unresolved"
    assert get(path, login).resp_body =~ judgment.rationale

    assert :ok =
             ReviewerAccess.revoke_scope(
               context.account.email,
               context.artifact["scope_content_sha256"],
               "operator-1",
               "rights_signoff"
             )

    assert post_form(path, login, page, "rights_review", attrs).status == 403

    assert {:error, :stale_or_unauthorized} =
             RightsReviews.submit(
               context.account,
               context.artifact,
               "dila-karashima-kumarajiva-local",
               attrs
             )

    assert Repo.aggregate(RightsJudgment, :count) == 1
  end

  defp login(account) do
    token = Accounts.generate_user_session_token(account)

    PlugTest.conn(:get, "/")
    |> PlugTest.init_test_session(%{user_token: token})
    |> ReviewerEndpoint.call([])
  end

  defp get(path, cookies) do
    conn = PlugTest.conn(:get, path)
    conn = if cookies, do: PlugTest.recycle_cookies(conn, cookies), else: conn
    ReviewerEndpoint.call(conn, [])
  end

  defp post(id, cookies, page, attrs) do
    params = %{
      "review" => attrs,
      "_csrf_token" => field(page.resp_body, "_csrf_token")
    }

    PlugTest.conn(:post, "/reviews/#{id}", Query.encode(params))
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> PlugTest.recycle_cookies(cookies)
    |> ReviewerEndpoint.call([])
  end

  defp post_form(path, cookies, page, as, attrs) do
    PlugTest.conn(
      :post,
      path,
      Query.encode(%{
        as => attrs,
        "_csrf_token" => field(page.resp_body, "_csrf_token")
      })
    )
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> PlugTest.recycle_cookies(cookies)
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

  defp field(body, name, as \\ "review") do
    name = if name == "_csrf_token", do: name, else: "#{as}[#{name}]"
    [tag] = Regex.run(~r/<input(?=[^>]*name="#{Regex.escape(name)}")[^>]*>/, body)
    [_, value] = Regex.run(~r/value="([^"]+)"/, tag)
    value
  end

  defp seed_case!(artifact) do
    Repo.insert!(%Source{id: "cbeta", name: "CBETA", license_class: "nc"})
    Repo.insert!(%Witness{id: "T", name: "Taishō"})

    Repo.insert!(%Work{
      id: "T1800",
      title: "first commentary",
      text_role: "commentary",
      division: "經疏部",
      composition_origin: "chinese",
      attributed_author: "Synthetic reviewer fixture"
    })

    Repo.insert!(%Work{
      id: "T0400",
      title: "alternative root",
      text_role: "root",
      division: "經集部",
      composition_origin: "chinese"
    })

    quote_text = "如是我聞此處只是相同的文字不能證明版本關係"
    quote_sha256 = hash(quote_text)
    source_body = "甲乙" <> quote_text
    target_body = String.duplicate("乙", 7) <> quote_text

    source_text =
      Repo.insert!(%Text{
        source_id: "cbeta",
        witness_id: "T",
        work_id: "T1800",
        urn_prefix: "pramana:cbeta.T:T1800",
        body: source_body,
        body_sha256: hash(source_body)
      })

    target_text =
      Repo.insert!(%Text{
        source_id: "cbeta",
        witness_id: "T",
        work_id: "T0400",
        urn_prefix: "pramana:cbeta.T:T0400",
        body: target_body,
        body_sha256: hash(target_body)
      })

    Repo.insert!(%Quotation{
      text: quote_text,
      text_sha256: quote_sha256,
      length: String.length(quote_text),
      a_text_id: target_text.id,
      a_work_id: "T0400",
      a_urn: "pramana:cbeta.T:T0400_001@p0002a01",
      a_char_start: 7,
      a_char_end: 7 + String.length(quote_text),
      b_text_id: source_text.id,
      b_work_id: "T1800",
      b_urn: "pramana:cbeta.T:T1800_001@p0001a01",
      b_char_start: 2,
      b_char_end: 2 + String.length(quote_text),
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

  defp hash(value), do: value |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end
