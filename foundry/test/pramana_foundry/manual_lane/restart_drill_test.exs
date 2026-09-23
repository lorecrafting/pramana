defmodule PramanaFoundry.ManualLane.RestartDrillTest do
  @moduledoc """
  W5 (T7, THIN-LANE-DESIGN-2026-09-23.md §6): the restart drill. The real `bin/pramana lane`
  entry point (`CLI.RPC.run/1`) drives a `ManualLane.Server` on a temporary store the Server
  seeds itself, so the seed and the backend must name the same policy and ledgers.

  At each stop point the Server and its Gateway are stopped (cleanly, or killed), restarted
  over the same path under a new `writer_epoch`, and the store must open `:ready`, replay to
  the pre-stop state and its committed projection, and carry the lane on to completion.
  No in-memory state crosses a restart: every assertion reads the store.
  """
  use ExUnit.Case, async: false

  # The pinned recovery-mode refusal logs a GenServer crash on every kill.
  @moduletag :capture_log

  import ExUnit.CaptureIO

  alias Exqlite.Sqlite3
  alias PramanaFoundry.CLI.RPC
  alias PramanaFoundry.DurableStore.{Database, Gateway}
  alias PramanaFoundry.ManualLane.{Backend, Replay, Server}
  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.Execution

  @dev "human:raymond"
  @rev "agent:fable:s1"

  @seed %{
    "policy" => %{
      "allowed_operations" => ["launch"],
      "allowed_scopes" => [],
      "allowed_roles" => ["developer", "reviewer"],
      "infrastructure_attempt_limits" => %{"developer" => 3, "reviewer" => 3},
      "independent_of_roles" => %{"reviewer" => ["developer"]}
    },
    "control" => %{"status" => "active"},
    "starts" => %{"developer" => 3, "reviewer" => 3}
  }

  setup do
    root = Path.join("/private/tmp", "lane-drill-#{System.unique_integer([:positive])}")
    repo = Path.join(root, "repo")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(root) end)

    git!(repo, ["init", "-q", "-b", "main"])
    base = commit!(repo, "a.txt", "base")
    git!(repo, ["tag", "base"])
    candidate = commit!(repo, "b.txt", "candidate")

    seed_path = Path.join(root, "seed.json")
    File.write!(seed_path, JSON.encode!(@seed))
    notes = Path.join(root, "notes.md")
    File.write!(notes, "looks right\n")

    c = %{
      root: root,
      repo: repo,
      base: base,
      candidate: candidate,
      notes: notes,
      opts: [runtime_root: root, repo: repo, policy_path: seed_path]
    }

    start!(c)
    c
  end

  # ── Stop after admit ─────────────────────────────────────────────────────────────

  test "stop after admit: queued, spec and scope intact, no attempt; the lane completes", c do
    admitted = admit!(c)
    restart!(c, :stop)

    t = ticket()
    assert t["phase"] == "queued"
    assert t["attempts"] in [nil, %{}]
    assert t["active_attempt_id"] == nil

    assert %{
             "base_revision" => base,
             "base_ref" => "base",
             "scope" => ["foundry/**", "docs/**"],
             "acceptance_criteria" => ["passes"]
           } = t["spec"]

    assert base == c.base
    assert {:ok, %{"value" => policy}} = Replay.query(ctx(), policy_query())
    assert "ticket:ML-1" in policy["allowed_scopes"]

    assert admit!(c) == admitted
    complete!(c)
  end

  # ── Stop after packet (issue) ────────────────────────────────────────────────────

  describe "stop after packet, the Server and Gateway killed" do
    setup c do
      admit!(c)
      old_epoch = ctx().writer_epoch
      packet = ok!(~w(packet ML-1 --role developer --principal #{@dev}))
      restart!(c, :kill)
      refute ctx().writer_epoch == old_epoch

      t = ticket()
      assert t["phase"] == "developing"
      [attempt] = Map.values(t["attempts"])

      assert [%Execution{role: "developer", lifecycle: "pending"}] =
               Map.values(attempt["executions"])

      effect = effect(packet["packet"]["execution_id"])
      assert effect["status"] == "issued"
      assert [%{"writer_epoch" => ^old_epoch}] = effect["claims"]

      %{"tickets" => %{"ML-1" => s}} = ok!(~w(status ML-1))

      assert [%{"awaits_operator" => true, "issuer" => @dev}] =
               hd(Map.values(s["attempts"]))["executions"]

      # No blind relaunch (FR-10 A5): the same packet, and no second effect.
      assert ok!(~w(packet ML-1 --role developer --principal #{@dev})) == packet
      assert [_one] = Map.values(hd(Map.values(ticket()["attempts"]))["executions"])

      %{old_epoch: old_epoch, effect_id: effect["effect_id"]}
    end

    test "submit settles only the old-epoch claim, and the lane completes", c do
      assert %{"phase" => "awaiting_review"} = submit!(c)
      assert effect_by_id(c.effect_id)["status"] == "succeeded"
      assert %{"phase" => "ready_to_integrate"} = review!(c, "approved")
    end

    test "settle non_started carries the old epoch as quiescence_epoch", c do
      assert %{"phase" => "queued"} =
               ok!(~w(settle ML-1 --role developer --principal #{@dev} --outcome non_started
                      --attest gone --issuer-gone --channel-quiet))

      # Core accepts an `issuer_quiescent` receipt only when its quiescence_epoch equals the
      # claim's writer_epoch (`settlement_provenance`), and that claim holds the old epoch.
      effect = effect_by_id(c.effect_id)
      refute effect["status"] == "issued"
      assert [%{"writer_epoch" => old}] = effect["claims"]
      assert old == c.old_epoch
      refute ctx().writer_epoch == c.old_epoch

      complete!(c)
    end
  end

  # ── Stop after submit, and between receipt and freeze ────────────────────────────

  test "stop after submit: awaiting_review, one consumed unit; the lane completes", c do
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    submitted = submit!(c)
    restart!(c, :stop)

    t = ticket()
    attempt = t["attempts"][t["active_attempt_id"]]
    assert t["phase"] == "awaiting_review"
    assert attempt["phase"] == "awaiting_review"
    assert attempt["candidate_id"] == c.candidate
    assert effect(developer_execution(t))["status"] == "succeeded"
    assert %{"held" => 0, "consumed" => 1} = ledger("developer")

    assert submit!(c) == submitted
    assert %{"phase" => "ready_to_integrate"} = review!(c, "approved")
  end

  test "split: a stop between the receipt and the freeze replays and the rerun completes", c do
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))

    # The CLI's first commit alone, with the receipt byte-for-byte as `submit` builds it.
    receipt = %{
      "evidence_kind" => "operator_attestation",
      "attested_by" => @dev,
      "statement" => "delivered candidate #{c.candidate}",
      "candidate_id" => c.candidate
    }

    assert {:ok, _} = Backend.deliver(ctx(), "ML-1", "developer", @dev, receipt)
    restart!(c, :kill)

    t = ticket()
    assert t["phase"] == "developing"
    assert effect(developer_execution(t))["status"] == "succeeded"

    assert %{"phase" => "awaiting_review", "candidate_id" => cand} = submit!(c)
    assert cand == c.candidate
    assert deliver_commands() == 1
    assert %{"phase" => "ready_to_integrate"} = review!(c, "approved")
  end

  # ── Stop after review ────────────────────────────────────────────────────────────

  for {verdict, phase} <- [
        {"approved", "ready_to_integrate"},
        {"correction", "queued"},
        {"rejected", "rejected"}
      ] do
    test "stop after review #{verdict}: #{phase}, reviewer closed, nothing issued", c do
      admit!(c)
      ok!(~w(packet ML-1 --role developer --principal #{@dev}))
      submit!(c)
      reviewed = review!(c, unquote(verdict))
      restart!(c, :stop)

      t = ticket()
      assert t["phase"] == unquote(phase)
      attempt = t["attempts"][t["active_attempt_id"]] || only_attempt(t)
      assert attempt["review"]["verdict"] == unquote(verdict)
      assert attempt["candidate_id"] == c.candidate

      executions = Map.values(attempt["executions"])
      assert %Execution{lifecycle: "closed"} = Enum.find(executions, &(&1.role == "reviewer"))

      effects = for {id, _} <- attempt["executions"], do: effect(id)
      assert Enum.map(effects, & &1["issuer"]) |> Enum.sort() == Enum.sort([@dev, @rev])
      refute Enum.any?(effects, &(&1["status"] == "issued"))

      # The rerun reports the committed review, though its verdict moved the active attempt.
      events = event_count()
      assert review_again(c, unquote(verdict)) == reviewed
      assert event_count() == events

      # Red control: a different verdict on the reviewed candidate is refused, not reported.
      other = Enum.find(~w(approved correction rejected), &(&1 != unquote(verdict)))

      assert {false, %{"error" => "review_already_recorded"}} = lane(review_argv(c, other))
      assert event_count() == events
    end
  end

  # The same argv after a correction and a resubmission of the same candidate is the next
  # attempt's review, not a rerun of the committed one.
  test "an open review on the next attempt is reviewed, not reported as the earlier one", c do
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    submit!(c)
    review!(c, "correction")
    restart!(c, :stop)

    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    submit!(c)
    assert %{"phase" => "queued"} = review!(c, "correction")

    verdicts = for {_, a} <- ticket()["attempts"], do: a["review"]["verdict"]
    assert verdicts == ["correction", "correction"]
  end

  # ── A2: an unknown hold survives a restart ───────────────────────────────────────

  test "settle unknown before a restart: the hold survives", c do
    admit!(c)
    %{"packet" => p} = ok!(~w(packet ML-1 --role developer --principal #{@dev}))

    ok!(~w(settle ML-1 --role developer --principal #{@dev} --outcome unknown --attest lost))

    restart!(c, :kill)
    assert effect(p["execution_id"])["status"] == "unknown"
    assert %{"held" => 1} = ledger("developer")
    %{"tickets" => %{"ML-1" => s}} = ok!(~w(status ML-1))

    assert [%{"effect_status" => "unknown", "awaits_operator" => true}] =
             hd(Map.values(s["attempts"]))["executions"]
  end

  # ── A stop between a refused launch and its retry ────────────────────────────────

  test "a launch refused under a burned id retries under the next id after a restart", c do
    admit!(c)
    ctx = ctx()
    id = "ML-1/developer/0/#{@dev}"

    # The racer from cli_test: decides, loses to a concurrent policy write, and Core
    # records its refused bundle under its id.
    {:ok, facts} = Replay.launch_facts(ctx, "manual-lane", "manual-lane", "starts.developer", nil)

    command = %{
      "schema_version" => 1,
      "command_id" => id,
      "type" => "plan_launch",
      "target_ids" => %{"ticket_id" => "ML-1"},
      "payload" => %{"role" => "developer"},
      "expected_revisions" => %{}
    }

    {:ok, decision} = WorkflowKernel.decide(Backend.state(ctx), command, facts)
    {:ok, _} = Backend.admit(ctx, "ML-2", ticket()["spec"])
    assert {:ok, %{"disposition" => refused}, _} = Replay.submit(ctx, decision, @dev)
    assert refused != "accepted"

    restart!(c, :kill)
    assert ticket()["phase"] == "queued"

    assert %{"packet" => %{"execution_id" => exec}} =
             ok!(~w(packet ML-1 --role developer --principal #{@dev}))

    assert exec == "#{id}/retry-1/execution"
    complete!(c, [:packet_done])
  end

  # ── The lane's steps ─────────────────────────────────────────────────────────────

  defp admit!(c) do
    ok!(~w(admit ML-1 --base-ref base --title t --scope foundry/**,docs/** --acceptance passes))
    |> tap(fn r -> assert r["base_revision"] == c.base end)
  end

  defp submit!(c),
    do: ok!(~w(submit ML-1 --principal #{@dev} --candidate #{c.candidate} --checkout #{c.repo}))

  defp review!(c, verdict) do
    ok!(~w(packet ML-1 --role reviewer --principal #{@rev}))
    review_again(c, verdict)
  end

  defp review_again(c, verdict), do: ok!(review_argv(c, verdict))

  defp review_argv(c, verdict),
    do: ~w(review ML-1 --principal #{@rev} --verdict #{verdict}
         --candidate #{c.candidate} --notes #{c.notes})

  # From wherever the lane stopped, on to an approved ticket.
  defp complete!(c, done \\ []) do
    if :packet_done not in done and ticket()["phase"] == "queued",
      do: ok!(~w(packet ML-1 --role developer --principal #{@dev}))

    assert %{"phase" => "awaiting_review"} = submit!(c)
    assert %{"phase" => "ready_to_integrate"} = review!(c, "approved")
  end

  # ── Restart ──────────────────────────────────────────────────────────────────────

  defp start!(c) do
    # Temporary, so a killed Server is not restarted behind the drill's back.
    start_supervised!(Supervisor.child_spec({Server, c.opts}, restart: :temporary))
  end

  # Stops the Server and its Gateway, restarts over the same store, and asserts the store
  # opens :ready and replays to exactly the pre-stop state and its committed projection.
  defp restart!(c, how) do
    before = Backend.state(ctx())
    %{gateway: gateway} = Server.context()
    server = Process.whereis(Server)
    refs = Enum.map([gateway, server], &Process.monitor/1)

    case how do
      :stop ->
        stop_supervised!(Server)

      :kill ->
        # Untrappable, Gateway first: neither runs `terminate/2`.
        Process.exit(gateway, :kill)
        Process.exit(server, :kill)
    end

    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 5_000)
    if how == :kill, do: recover_owner!(c)

    start!(c)
    assert %{mode: :ready, reason: nil} = Gateway.status(Server.context().gateway)
    assert Backend.state(ctx()) == before
    law!()
  end

  # FINDING (W5): after an unclean exit the Owner leaves `.owner.unclean`, and reopening
  # needs `recovery_evidence`. `Server.init/1` never forwards it to `Gateway.start_link`,
  # so the Server alone can never restart the lane: it stops with `:recovery_mode` (and the
  # CLI's `:gateway_recovery` is unreachable). This pins that, then recovers the owner the
  # way Core allows, with a one-off Gateway given the evidence and stopped cleanly.
  defp recover_owner!(c) do
    assert {:error, {{:recovery_mode, reason}, _}} =
             start_supervised(Supervisor.child_spec({Server, c.opts}, restart: :temporary))

    assert {:store_owner_unavailable, {:ambiguous_previous_owner, _, _}} = reason

    gateway =
      start_supervised!(
        {Gateway,
         path: Path.join(c.root, "state/manual-lane/authority.sqlite3"),
         protected_capability: make_ref(),
         writer_epoch: "drill-recovery",
         recovery_evidence: "drill: Server and Gateway killed, BEAM monitors confirm both down"},
        id: :owner_recovery
      )

    assert %{mode: :ready} = Gateway.status(gateway)
    stop_supervised!(:owner_recovery)
  end

  # The substitution law: the replayed ticket is the committed projection.
  defp law! do
    {:ok, [[bytes]]} =
      sql(
        "SELECT projection FROM projections WHERE namespace = ? AND entity_id = ?",
        ["foundry.ticket.v1", "ML-1"]
      )

    assert JSON.decode!(bytes)["value"] == ticket() |> JSON.encode!() |> JSON.decode!()
  end

  # ── Reads ────────────────────────────────────────────────────────────────────────

  defp ctx, do: Map.put(Server.context(), :path, Server.context().store_path)
  defp ticket, do: Backend.state(ctx())["tickets"]["ML-1"]
  defp only_attempt(t), do: t["attempts"] |> Map.values() |> then(fn [a] -> a end)

  defp policy_query, do: %{"type" => "policy", "policy_id" => Backend.ids().policy_id}

  defp developer_execution(t) do
    t["attempts"][t["active_attempt_id"]]["executions"]
    |> Enum.find_value(fn {id, %Execution{role: r}} -> if r == "developer", do: id end)
  end

  defp effect(execution_id),
    do: effect_by_id(String.replace_suffix(execution_id, "/execution", "/effect"))

  defp effect_by_id(id) do
    {:ok, effect} = Replay.query(ctx(), %{"type" => "effect", "effect_id" => id})
    effect
  end

  defp ledger(role) do
    {:ok, l} =
      Replay.query(ctx(), %{
        "type" => "ledger",
        "ledger_id" => Backend.ids().ledgers[role],
        "generation" => 0
      })

    Map.take(l, ~w(available held consumed))
  end

  defp deliver_commands do
    {:ok, [[n]]} =
      sql("SELECT count(*) FROM root_commands WHERE command_id LIKE 'ML-1/deliver/%'", [])

    n
  end

  defp event_count do
    {:ok, [[n]]} = sql("SELECT count(*) FROM events", [])
    n
  end

  defp sql(query, params) do
    {:ok, conn} = Sqlite3.open(ctx().path, mode: :readonly)

    try do
      Database.query(conn, query, params)
    after
      Sqlite3.close(conn)
    end
  end

  # ── The CLI entry point ──────────────────────────────────────────────────────────

  # Runs `bin/pramana lane ARGV --json` through the RPC entry point: {exit_ok?, decoded}.
  defp lane(argv) do
    payload =
      %{"version" => 1, "argv" => ["lane" | argv] ++ ["--json"]}
      |> JSON.encode!()
      |> Base.url_encode64(padding: false)

    out =
      capture_io(fn ->
        ok? =
          try do
            RPC.run(payload)
            true
          rescue
            RuntimeError -> false
          end

        send(self(), {:ok?, ok?})
      end)

    assert_received {:ok?, ok?}
    decoded = JSON.decode!(out)
    assert decoded["ok"] == ok?, "exit status and output disagree: #{out}"
    {ok?, decoded}
  end

  defp ok!(argv) do
    assert {true, result} = lane(argv)
    result
  end

  defp git!(repo, args) do
    {out, 0} =
      System.cmd("git", ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@t" | args])

    String.trim(out)
  end

  defp commit!(repo, file, text) do
    File.write!(Path.join(repo, file), text)
    git!(repo, ["add", file])
    git!(repo, ["commit", "-q", "-m", text])
    git!(repo, ["rev-parse", "HEAD"])
  end
end
