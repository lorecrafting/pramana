defmodule PramanaFoundry.Effects.SilenceWatchdogTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Effects.SilenceWatchdog

  @full_evidence %{
    source: :durable_provider_event,
    event_at: 1_000.0,
    agent: "dev-1",
    pane_id: "pane-1",
    terminal_id: "term-1",
    session: "sess-1",
    role: "developer",
    task_id: "T1",
    run_id: "R1",
    pid: 4242
  }

  test "evidence is sufficient only when it is durable and every identity field is present" do
    assert SilenceWatchdog.evidence_sufficient?(@full_evidence)
    refute SilenceWatchdog.evidence_sufficient?(Map.delete(@full_evidence, :pid))
    refute SilenceWatchdog.evidence_sufficient?(%{@full_evidence | pid: nil})
  end

  test "a transcript spinner string or bare wall-clock silence is never sufficient evidence" do
    refute SilenceWatchdog.evidence_sufficient?("spinner: working...")
    refute SilenceWatchdog.evidence_sufficient?(%{source: :wall_clock, event_at: 1.0})

    refute SilenceWatchdog.evidence_sufficient?(%{
             @full_evidence
             | source: :mutable_checkout_timestamp
           })
  end

  test "a verified long-running check or tool with its own deadline is exempt" do
    assert SilenceWatchdog.exempt?(%{own_deadline_epoch: 9_999.0})
    refute SilenceWatchdog.exempt?(%{})
    refute SilenceWatchdog.exempt?(%{own_deadline_epoch: nil})
  end

  test "expired?/3 is false just before the bound and true just after it, given sufficient evidence" do
    refute SilenceWatchdog.expired?(@full_evidence, 300, 1_000.0 + 299)
    assert SilenceWatchdog.expired?(@full_evidence, 300, 1_000.0 + 301)
  end

  test "expired?/3 never fires on insufficient evidence, no matter how much time passed" do
    refute SilenceWatchdog.expired?(%{source: :wall_clock}, 300, 1_000_000.0)
  end

  test "classify/1 reads capacity, rate-limit, subscription-quota, and cooldown from durable evidence without polling a provider" do
    assert SilenceWatchdog.classify(%{signal: :capacity}) == :capacity
    assert SilenceWatchdog.classify(%{signal: :rate_limit}) == :rate_limit
    assert SilenceWatchdog.classify(%{signal: :subscription_quota}) == :subscription_quota
    assert SilenceWatchdog.classify(%{signal: :cooldown}) == :cooldown
    assert SilenceWatchdog.classify(%{signal: :unrelated_provider}) == :unrelated_provider
  end

  test "classify/1 defaults to silent_no_progress for an unrecognized or absent signal" do
    assert SilenceWatchdog.classify(%{}) == :silent_no_progress
    assert SilenceWatchdog.classify(%{signal: :something_else}) == :silent_no_progress
  end
end
