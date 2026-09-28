defmodule Pramana.Repo.Migrations.AddWorkRelationReviewState do
  use Ecto.Migration

  def up do
    alter table(:work_relations) do
      add :review_status, :string, null: false, default: "unflagged"
      add :review_reason, :text
    end

    create constraint(:work_relations, :work_relations_review_state,
             check: """
             (review_status = 'unflagged' AND review_reason IS NULL) OR
             (review_status = 'needs_review' AND review_reason IS NOT NULL AND
              length(trim(review_reason)) > 0)
             """
           )

    execute("""
    UPDATE work_relations
       SET review_status = 'needs_review',
           review_reason = 'Historical shared-text assertion not reproduced by the current rule; source and edition need review'
     WHERE method = 'shared_text'
       AND (source_work_id, target_work_id) IN (
         ('T1699','T0374'), ('T1708','T0220b'), ('T1712','T0250'),
         ('T1722','T0277'), ('T1723','T0220c'), ('T1736','T0279'),
         ('T1738','T0279'), ('T1744','T1485'), ('T1748','T0681'),
         ('T1769','T0375'), ('T1770','T0220c'), ('T1804','T1433'),
         ('T1805','T0279'), ('T1806','T1429'), ('T1815','T0468')
       )
    """)

    execute("""
    UPDATE work_relations
       SET review_status = 'needs_review',
           review_reason = 'Shared-text margin is narrow and the proposed target conflicts with title evidence; source and edition need review'
     WHERE method = 'shared_text' AND source_work_id = 'T1736' AND target_work_id = 'T0374'
    """)
  end

  def down do
    drop constraint(:work_relations, :work_relations_review_state)

    alter table(:work_relations) do
      remove :review_status
      remove :review_reason
    end
  end
end
