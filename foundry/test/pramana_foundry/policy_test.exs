defmodule PramanaFoundry.PolicyTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.{Parity, Preparation}

  test "shadow mode has no Herdr or live-state capability" do
    assert {:ok, %{herdr_calls: 0, live_state_writes: 0}} = Parity.shadow(%{"task" => "T1"})
    assert {:error, :effects_forbidden_in_shadow_mode} = Parity.shadow(%{}, herdr: fn -> :bad end)
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
