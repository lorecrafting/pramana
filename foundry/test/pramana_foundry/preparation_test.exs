defmodule PramanaFoundry.PreparationTest do
  use ExUnit.Case, async: true

  test "preparation is selected from admitted ticket's declared resource needs" do
    workflow_only_ticket = %{
      "shared_resources" => %{
        "corpus" => [],
        "database" => [],
        "gpu" => [],
        "other" => ["workflow-engine"]
      }
    }

    database_ticket = %{
      "shared_resources" => %{
        "corpus" => [],
        "database" => ["main"],
        "gpu" => [],
        "other" => []
      }
    }

    wf_cmds = PramanaFoundry.Preparation.commands(workflow_only_ticket)
    assert length(wf_cmds) == 2
    refute Enum.any?(wf_cmds, &(&1.argv == ["mise", "exec", "--", "mix", "ecto.create"]))

    db_cmds = PramanaFoundry.Preparation.commands(database_ticket)
    assert length(db_cmds) == 4
    assert Enum.any?(db_cmds, &(&1.argv == ["mise", "exec", "--", "mix", "ecto.create"]))
  end
end
