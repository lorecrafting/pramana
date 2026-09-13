defmodule PramanaFoundry.PolicyTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.{Parity, Preparation}

  test "retired Python parity fails closed instead of reporting vacuous equality" do
    assert {:error, :retired_python_migration_parity} = Parity.shadow(%{"task" => "T1"})

    assert %{status: :retired, reason: :retired_python_migration_parity} =
             Parity.compare_fixture(:snapshot, "unused")
  end

  test "workflow-only preparation omits umbrella and database commands" do
    commands = Preparation.commands(%{"shared_resources" => %{"database" => []}})
    argv = Enum.flat_map(commands, & &1.argv)

    refute "ecto.create" in argv
    refute Enum.any?(commands, &(&1.cwd == "apps/pramana" or "apps/pramana" in &1.argv))
    assert Enum.any?(commands, &(&1.cwd == "workflow"))
  end

  test "database-declaring control retains database prerequisites" do
    commands = Preparation.commands(%{"shared_resources" => %{"database" => ["test"]}})
    assert Enum.any?(commands, &("ecto.create" in &1.argv))
  end
end
