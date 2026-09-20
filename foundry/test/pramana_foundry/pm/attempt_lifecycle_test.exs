defmodule PramanaFoundry.PM.AttemptLifecycleTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.PM
  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"

  test "planning attempt caps and human-only reset control" do
    pm_state = %{"accepted_revision" => @base_rev}

    # Consecutive rejections with different run IDs but same reason increment loop counter
    r1 = "proposal /artifacts/planning/aaaa1111bbbb2222.json rejected: schema error"
    r2 = "proposal /artifacts/planning/cccc3333dddd4444.json rejected: schema error"
    r3 = "proposal /artifacts/planning/eeee5555ffff6666.json rejected: schema error"

    pm_state =
      pm_state
      |> PM.record_disposition("rejected", r1)
      |> PM.record_disposition("rejected", r2)
      |> PM.record_disposition("rejected", r3)

    assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 3
    halt = PM.halt_reason(pm_state, @base_rev, max_attempts_per_revision: 3)
    assert halt["counter"] == "consecutive_rejections"
    assert halt["clears_with"] == "reset-pm-attempts"

    # Reset with human authority clears halt
    reset_payload = %{
      "authority" => "human",
      "issued_by" => "test_operator",
      "issued_at" => "2026-09-10T00:00:00Z",
      "revision" => @base_rev
    }

    assert {:ok, record, updated_pm} = PM.reset_attempts(pm_state, reset_payload, @base_rev)
    assert record["previous_consecutive_rejections"] == 3
    refute Map.has_key?(updated_pm["consecutive_rejections_by_revision"], @base_rev)
    assert PM.halt_reason(updated_pm, @base_rev) == nil
  end
end
