defmodule Pramana.Repo.Migrations.CreateWorkRelations do
  use Ecto.Migration

  @moduledoc """
  Typed, directional relations between works — see `docs/COMMENTARY.md`.

  `text_role` already distinguishes root / treatise / commentary / subcommentary, and
  those are populated. What was missing is *which text* a commentary comments on, so
  "show me Chinese commentary" worked and "show me commentary **on the Lotus Sūtra**"
  did not — and the second is the question people actually have.

  Modelled as a graph rather than a `parent_id`, because relations chain: a
  subcommentary explains a commentary which explains a sūtra, and walking a modern
  explanation back to root scripture should show the intermediate layers rather than
  collapse them.
  """

  def change do
    create table(:work_relations) do
      add :source_work_id, references(:works, type: :string, on_delete: :delete_all), null: false

      add :target_work_id, references(:works, type: :string, on_delete: :delete_all)

      # Kept even when the target work is not in the corpus: a manifest can assert that
      # a commentary explains 夏蓮居's conflation before that conflation is ingested, and
      # dropping the assertion until then would lose real information. Exactly one of
      # target_work_id / target_work_ref must be set (CHECK below).
      add :target_work_ref, :string

      add :relation, :string, null: false
      add :scope, :string, null: false, default: "whole_work"

      # The exact passage, when known. Work-level linking is easy and mildly useful;
      # PASSAGE-level linking is what makes a commentary actually helpful, and Chinese
      # commentaries quote the root passage before explaining it, so #22/#23 can derive
      # this deterministically rather than guess.
      add :target_urn, :string

      # NOT decoration. A catalogue assertion and an LLM inference are different claims
      # and the difference has to reach the answer — CLAUDE.md invariant #5.
      add :confidence, :string, null: false, default: "asserted"
      add :method, :string, null: false
      add :evidence, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:work_relations, [:source_work_id])
    create index(:work_relations, [:target_work_id])
    create index(:work_relations, [:relation])
    create index(:work_relations, [:target_urn])

    # One assertion per (source, target, relation, method). The same relation asserted by
    # a catalogue AND by lemma matching is two pieces of evidence worth keeping
    # separately — corroboration is information.
    create unique_index(
             :work_relations,
             [:source_work_id, :target_work_id, :target_work_ref, :relation, :method],
             name: :work_relations_unique_assertion,
             nulls_distinct: false
           )

    create constraint(:work_relations, :work_relations_relation_known,
             check: """
             relation IN ('comments_on','subcommentary_of','translates','conflates',
                          'abridges','quotes','parallel_of')
             """
           )

    create constraint(:work_relations, :work_relations_scope_known,
             check: "scope IN ('whole_work','juan','passage')"
           )

    create constraint(:work_relations, :work_relations_confidence_known,
             check: "confidence IN ('certain','probable','asserted','uncertain')"
           )

    create constraint(:work_relations, :work_relations_method_known,
             check: "method IN ('catalogue','manifest','lemma_match','llm')"
           )

    # A relation must point AT something.
    create constraint(:work_relations, :work_relations_has_target,
             check: "target_work_id IS NOT NULL OR target_work_ref IS NOT NULL"
           )

    # A passage-scoped relation without a URN is a claim it cannot support.
    create constraint(:work_relations, :work_relations_passage_needs_urn,
             check: "scope <> 'passage' OR target_urn IS NOT NULL"
           )

    # Nothing comments on itself.
    create constraint(:work_relations, :work_relations_no_self_reference,
             check: "source_work_id IS DISTINCT FROM target_work_id"
           )
  end
end
