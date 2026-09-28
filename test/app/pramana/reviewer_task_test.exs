defmodule Pramana.ReviewerTaskTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Pramana.Reviewer

  test "serving processes cannot run account management" do
    previous = System.get_env("PRAMANA_REVIEWER")
    System.put_env("PRAMANA_REVIEWER", "1")

    on_exit(fn ->
      if previous,
        do: System.put_env("PRAMANA_REVIEWER", previous),
        else: System.delete_env("PRAMANA_REVIEWER")
    end)

    assert_raise Mix.Error, ~r/separate operator process/, fn ->
      Reviewer.run(["rotate", "--login-id", "reviewer.one"])
    end
  end
end
