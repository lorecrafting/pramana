defmodule PramanaFoundry.ImproverProposalGateTest do
  @moduledoc """
  The Improver finds and records, but does not propose tickets, until FR-20 reconnects
  proposals. That path was closed until 2026-09-21 only because `SystemMetrics.system/0`
  raised on every cycle before it; the fix opened it. See IMPLEMENTATION-LOG for 2026-09-22.

  No Coordinator runs in this test, so a cycle that reached `propose_findings/1` would exit on
  `Coordinator.apply_pm_proposals/1` and take the Improver with it. The Improver surviving a
  cycle with new findings is therefore the observable proof the proposal step was skipped.
  Red control (rule 6): flip the `:propose` default to true and this fails.
  """
  use ExUnit.Case, async: false

  alias PramanaFoundry.Improver

  test "a cycle with new findings records them and proposes nothing by default" do
    name = :"improver_gate_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Improver, name: name, enable_loop: false}, restart: :temporary)
    ref = Process.monitor(pid)

    Improver.analyze(pid)
    findings = Improver.last_findings(pid)

    assert findings != [],
           "the precondition failed: this environment produced no findings, so the test proves nothing"

    refute_received {:DOWN, ^ref, _, _, _}
    assert Process.alive?(pid)
    assert :sys.get_state(pid).proposed_fingerprints == MapSet.new()
  end
end
