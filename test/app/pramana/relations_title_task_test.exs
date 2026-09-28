defmodule Pramana.RelationsTitleTaskTest do
  use Pramana.DataCase

  alias Mix.Tasks.Pramana.Relations.Derive
  alias Pramana.Corpus.DerivationRun
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Repo

  test "the default title derivation writes relations and a completion receipt" do
    Repo.insert!(%Work{id: "T9001", title: "大方廣經", text_role: "root"})
    Repo.insert!(%Work{id: "T9002", title: "大方廣經疏", text_role: "commentary"})

    Derive.run([])

    assert Repo.get_by!(WorkRelation, source_work_id: "T9002", target_work_id: "T9001").method ==
             "title_match"

    assert Repo.get_by!(DerivationRun, derivation: "relations_title").status == "complete"
  end
end
