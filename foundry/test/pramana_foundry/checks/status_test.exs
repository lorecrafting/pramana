defmodule PramanaFoundry.Checks.StatusTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Checks.Status

  @identity %{
    pid: 4242,
    parent_pid: 1,
    process_group_id: 4242,
    started_at: "a",
    command: "sleep 5"
  }

  defp base(overrides) do
    Map.merge(
      %{
        recorded_identity: @identity,
        live_identity: @identity,
        completion: nil,
        deadline_epoch: nil,
        cancellation_requested?: false,
        stop_intent_checkpointed?: false
      },
      overrides
    )
  end

  test "a live process matching the recorded identity exactly is :running" do
    assert Status.classify(base(%{})) == :running
  end

  test "no completion and no live match at all (process gone) is :uncertain, never assumed success" do
    assert Status.classify(base(%{live_identity: nil})) == :uncertain
  end

  test "no completion and a live pid that no longer matches (reused by another process) is :uncertain" do
    other = %{@identity | started_at: "different-start-time"}
    assert Status.classify(base(%{live_identity: other})) == :uncertain
  end

  # The drift defect, pinned deterministically. The probe at docs/fr-04 witnesses it against
  # real processes but only lands ~half the time, so it guards nothing in a gate; this does.
  test "a process that exec'd is still :running -- command may change, incarnation may not" do
    exec_ed = %{@identity | command: "/…/Python.app/Contents/MacOS/Python -c ..."}

    assert Status.classify(base(%{live_identity: exec_ed})) == :running

    # And it is not reported cancelled while it is still alive, which is what made a live
    # check read `:cancelled` in 5 of 12 measured launches.
    assert Status.classify(base(%{live_identity: exec_ed, cancellation_requested?: true})) ==
             :running
  end

  # The other half of the pair: dropping `command` must not weaken what :uncertain catches.
  # A reused pid gets a new start time, which is what actually distinguishes an incarnation.
  test "a different incarnation on the same pid is still :uncertain, command notwithstanding" do
    for field <- [:started_at, :process_group_id] do
      impostor = Map.put(@identity, field, "definitely different")
      assert Status.classify(base(%{live_identity: impostor})) == :uncertain, "#{field}"
    end
  end

  test "a matching cancellation request with no live process is :cancelled" do
    assert Status.classify(base(%{live_identity: nil, cancellation_requested?: true})) ==
             :cancelled
  end

  test "a completed run inside its deadline is {:completed, code, true} when nothing stopped it" do
    completion = %{"returncode" => 0, "completed_at" => 100.0}

    assert Status.classify(base(%{completion: completion, deadline_epoch: 200.0})) ==
             {:completed, 0, true}
  end

  test "deadline expiry beats a late zero exit: it is :timeout even though returncode is 0" do
    completion = %{"returncode" => 0, "completed_at" => 250.0}
    assert Status.classify(base(%{completion: completion, deadline_epoch: 200.0})) == :timeout
  end

  test "a nonzero exit past the deadline is still classified :timeout, not the exit code" do
    completion = %{"returncode" => 1, "completed_at" => 250.0}
    assert Status.classify(base(%{completion: completion, deadline_epoch: 200.0})) == :timeout
  end

  test "no deadline configured never times out, however late completion arrives" do
    completion = %{"returncode" => 0, "completed_at" => 1_000_000.0}

    assert Status.classify(base(%{completion: completion, deadline_epoch: nil})) ==
             {:completed, 0, true}
  end

  test "completion after a checkpointed stop intent is preserved as diagnostics but is not promotable" do
    completion = %{"returncode" => 0, "completed_at" => 100.0}

    assert Status.classify(base(%{completion: completion, stop_intent_checkpointed?: true})) ==
             {:completed, 0, false}
  end
end
