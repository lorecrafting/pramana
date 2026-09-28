defmodule Pramana.Repo.Migrations.ReflagChangedSupportedRelations do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE FUNCTION reflag_changed_supported_relation() RETURNS trigger AS $$
      BEGIN
        IF OLD.review_status = 'unflagged'
           AND NEW.review_status = 'unflagged'
           AND ROW(OLD.source_work_id, OLD.target_work_id, OLD.target_work_ref,
                   OLD.relation, OLD.method, OLD.confidence, OLD.scope,
                   OLD.target_urn, OLD.evidence)
               IS DISTINCT FROM
               ROW(NEW.source_work_id, NEW.target_work_id, NEW.target_work_ref,
                   NEW.relation, NEW.method, NEW.confidence, NEW.scope,
                   NEW.target_urn, NEW.evidence)
           AND EXISTS (
             SELECT 1 FROM reviewer_dispositions
             WHERE assertion_id = OLD.id AND disposition = 'supported'
           ) THEN
          NEW.review_status := 'needs_review';
          NEW.review_reason := 'Assertion changed after operator support';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION reflag_changed_supported_relation()"
    )

    execute(
      """
      CREATE TRIGGER reflag_changed_supported_relation
      BEFORE UPDATE ON work_relations
      FOR EACH ROW EXECUTE FUNCTION reflag_changed_supported_relation()
      """,
      "DROP TRIGGER reflag_changed_supported_relation ON work_relations"
    )
  end
end
