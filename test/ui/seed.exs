# Synthetic browser fixture. bin/ui-loop runs this only against its disposable database.
Code.require_file("test/app/support/reviewer_scope_fixture.ex")

alias Pramana.Accounts
alias Pramana.Accounts.User
alias Pramana.Accounts.UserToken
alias Pramana.Corpus.Quotation
alias Pramana.Corpus.Release
alias Pramana.Corpus.Source
alias Pramana.Corpus.Text
alias Pramana.Corpus.Witness
alias Pramana.Corpus.Work
alias Pramana.Corpus.WorkRelation
alias Pramana.Pilot.Scope
alias Pramana.Pilot.ScopeArtifact
alias Pramana.Release.Selection
alias Pramana.Repo
alias Pramana.ReviewerAccess

hash = fn value ->
  value |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end

input = Pramana.ReviewerScopeFixture.scope_input()
{:ok, artifact} = Scope.build(input)
File.write!(System.fetch_env!("PRAMANA_REVIEW_SCOPE_PATH"), ScopeArtifact.encode(artifact))

release =
  Repo.insert!(%Release{
    release_id: "review-release",
    source_bake_id: "review-bake",
    translation_set_id: "v2:review-translation",
    vector_set_id: "v2:review-vector",
    translations_count: 0,
    vectors_count: 0,
    stamped_at: DateTime.utc_now()
  })

Repo.insert!(%Selection{id: 1, release_id: release.id, selected_at: DateTime.utc_now()})
Repo.insert!(%Source{id: "cbeta", name: "Synthetic CBETA fixture", license_class: "nc"})
Repo.insert!(%Witness{id: "T", name: "Taishō"})

for work <- input.works do
  Repo.insert!(%Work{
    id: work.work_id,
    title: work.title,
    text_role: work.text_role,
    division: work.division,
    composition_origin: "chinese"
  })
end

quote = "如是我聞此處只是相同的文字不能證明版本關係"
source_body = "甲乙" <> quote
target_body = String.duplicate("乙", 7) <> quote

source_text =
  Repo.insert!(%Text{
    source_id: "cbeta",
    witness_id: "T",
    work_id: "T1800",
    urn_prefix: "pramana:cbeta.T:T1800",
    body: source_body,
    body_sha256: hash.(source_body),
    char_count: String.length(source_body)
  })

target_text =
  Repo.insert!(%Text{
    source_id: "cbeta",
    witness_id: "T",
    work_id: "T0400",
    urn_prefix: "pramana:cbeta.T:T0400",
    body: target_body,
    body_sha256: hash.(target_body),
    char_count: String.length(target_body)
  })

Repo.insert!(%Quotation{
  text: quote,
  text_sha256: hash.(quote),
  length: String.length(quote),
  a_text_id: target_text.id,
  a_work_id: "T0400",
  a_urn: "pramana:cbeta.T:T0400_001@p0002a01",
  a_char_start: 7,
  a_char_end: 7 + String.length(quote),
  b_text_id: source_text.id,
  b_work_id: "T1800",
  b_urn: "pramana:cbeta.T:T1800_001@p0001a01",
  b_char_start: 2,
  b_char_end: 2 + String.length(quote),
  bake_id: "review-bake"
})

assertion = hd(artifact["review_cases"])["assertion"]

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

{:ok, user} = Accounts.register_user(%{email: "ui-reviewer@example.test"})
user = user |> User.confirm_changeset() |> Repo.update!()
scope = artifact["scope_content_sha256"]
{:ok, _} = ReviewerAccess.grant_scope(user.email, scope, "ui-fixture")
{:ok, _} = ReviewerAccess.grant_scope(user.email, scope, "ui-fixture", "rights_signoff")
{token, token_row} = UserToken.build_email_token(user, "login")
Repo.insert!(token_row)

File.write!(
  Path.join(System.fetch_env!("UI_SEED_DIR"), "magic-link"),
  System.fetch_env!("UI_BASE_URL") <> "/users/log-in/" <> token
)
