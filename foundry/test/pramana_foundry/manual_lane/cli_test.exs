defmodule PramanaFoundry.ManualLane.CLITest do
  @moduledoc """
  W4 (T5, THIN-LANE-DESIGN-2026-09-23.md §4): `bin/pramana lane …` through the RPC entry
  point, against a `ManualLane.Server` started on a temporary store and a temporary Git repo.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias PramanaFoundry.CLI.RPC
  alias PramanaFoundry.DurableStore.Gateway
  alias PramanaFoundry.ManualLane.{Backend, Replay, Server}
  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel

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
    root = Path.join("/private/tmp", "lane-cli-#{System.unique_integer([:positive])}")
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

    opts = [runtime_root: root, repo: repo, policy_path: seed_path]
    %{root: root, repo: repo, base: base, candidate: candidate, notes: notes, opts: opts}
  end

  defp start!(c), do: start_supervised!({Server, c.opts})

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

  defp refused!(argv, reason) do
    assert {false, %{"error" => ^reason} = result} = lane(argv)
    result
  end

  defp admit!(c) do
    ok!(~w(admit ML-1 --base-ref base --title t --scope foundry/**,docs/** --acceptance passes))
    |> tap(fn r -> assert r["base_revision"] == c.base end)
  end

  defp submit!(c),
    do: ok!(~w(submit ML-1 --principal #{@dev} --candidate #{c.candidate} --checkout #{c.repo}))

  defp ctx, do: Map.put(Server.context(), :path, Server.context().store_path)

  defp assert_ready! do
    assert %{mode: :ready} = Gateway.status(Server.context().gateway)
  end

  # ── The full path ────────────────────────────────────────────────────────────────

  test "admit → packet → submit → review → status, and every state reopens :ready", c do
    start!(c)
    assert %{"ticket_id" => "ML-1", "spec_revision_id" => _} = admit!(c)

    %{"packet" => dev} = ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    assert %{"role" => "developer", "issuer" => @dev, "base_revision" => base} = dev
    assert base == c.base
    assert dev["scope"] == ["foundry/**", "docs/**"]

    assert %{"phase" => "awaiting_review", "candidate_id" => cand} = submit!(c)
    assert cand == c.candidate

    out = Path.join(c.root, "reviewer.json")

    %{"packet" => rev, "out" => ^out} =
      ok!(~w(packet ML-1 --role reviewer --principal #{@rev} --out #{out}))

    assert rev["candidate"]["candidate_id"] == c.candidate
    assert rev["independence"]["excluded_principals"] == [@dev]
    assert File.read!(out) == PramanaFoundry.WorkPacket.encode(rev)

    assert %{"phase" => "ready_to_integrate", "verdict" => "approved"} =
             ok!(~w(review ML-1 --principal #{@rev} --verdict approved
                    --candidate #{c.candidate} --notes #{c.notes}))

    %{"mode" => "ready", "tickets" => %{"ML-1" => t}} = ok!(~w(status ML-1))
    assert t["phase"] == "ready_to_integrate"
    [attempt] = Map.values(t["attempts"])
    assert attempt["verdict"] == "approved"

    assert Enum.map(attempt["executions"], &Map.take(&1, ~w(role effect_status issuer))) ==
             [
               %{"role" => "developer", "effect_status" => "succeeded", "issuer" => @dev},
               %{"role" => "reviewer", "effect_status" => "succeeded", "issuer" => @rev}
             ]

    refute Enum.any?(attempt["executions"], & &1["awaits_operator"])

    # A restart reopens :ready and status reads the same from the store alone.
    stop_supervised!(Server)
    start!(c)
    assert_ready!()
    assert %{"tickets" => %{"ML-1" => ^t}} = ok!(~w(status))
  end

  test "human-readable output is the default", c do
    start!(c)
    admit!(c)

    payload =
      %{"version" => 1, "argv" => ~w(lane status ML-1)}
      |> JSON.encode!()
      |> Base.url_encode64(padding: false)

    out = capture_io(fn -> RPC.run(payload) end)
    assert out =~ "mode: ready\n"
    refute out =~ ~s("ok")
  end

  # ── Refusals, each before any write where the CLI owns the guard ────────────────

  test "red control: lane packet without --principal is refused before any Gateway call" do
    # No Server runs: reaching the Gateway would say lane_disabled instead.
    refute Process.whereis(Server)
    refused!(~w(packet ML-1 --role developer), "principal_required")
    refused!(~w(status), "lane_disabled")
  end

  test "admit refuses an unresolvable ref and a non-lane id", c do
    start!(c)

    refused!(
      ~w(admit ML-1 --base-ref nope --title t --scope a --acceptance x),
      "git_ref_unresolved"
    )

    refused!(
      ~w(admit T-1-ab --base-ref base --title t --scope a --acceptance x),
      "ticket_id_not_lane"
    )

    refused!(~w(admit ML-1 --base-ref base --title t --scope a), "option_required")
    assert %{"tickets" => tickets} = ok!(~w(status))
    assert tickets == %{}
  end

  test "packet refuses a reviewer under the developer's principal", c do
    start!(c)
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    submit!(c)
    refused!(~w(packet ML-1 --role reviewer --principal #{@dev}), "principal_not_independent")
    refused!(~w(packet ML-1 --role pm --principal #{@dev}), "unsupported_role")
  end

  test "a second packet returns the same packet and issues no second effect", c do
    start!(c)
    admit!(c)
    first = ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    assert ok!(~w(packet ML-1 --role developer --principal #{@dev})) == first
    %{"tickets" => %{"ML-1" => t}} = ok!(~w(status ML-1))
    assert [%{"executions" => [_one]}] = Map.values(t["attempts"])
  end

  test "submit refuses Git evidence that does not hold and a foreign principal", c do
    start!(c)
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    File.write!(Path.join(c.repo, "dirty.txt"), "x")

    refused!(
      ~w(submit ML-1 --principal #{@dev} --candidate #{c.candidate} --checkout #{c.repo}),
      "git_evidence"
    )

    File.rm!(Path.join(c.repo, "dirty.txt"))

    refused!(
      ~w(submit ML-1 --principal #{@rev} --candidate #{c.candidate} --checkout #{c.repo}),
      "receipt_provenance_mismatch"
    )

    assert %{"phase" => "awaiting_review"} = submit!(c)
    # A rerun is idempotent.
    assert %{"phase" => "awaiting_review"} = submit!(c)
  end

  test "submit --blocked blocks the ticket without review", c do
    start!(c)
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))

    assert %{"phase" => "blocked"} =
             ok!(~w(submit ML-1 --principal #{@dev} --candidate #{c.candidate}
                    --checkout #{c.repo} --blocked needs_decision))
  end

  test "review refuses a candidate other than the frozen one, before any write", c do
    start!(c)
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    submit!(c)
    ok!(~w(packet ML-1 --role reviewer --principal #{@rev}))

    refused!(
      ~w(review ML-1 --principal #{@rev} --verdict approved --candidate #{c.base} --notes #{c.notes}),
      "candidate_mismatch"
    )

    refused!(
      ~w(review ML-1 --principal #{@rev} --verdict maybe --candidate #{c.candidate} --notes #{c.notes}),
      "invalid_verdict"
    )

    # Neither refusal settled the reviewer's claim: it still awaits a receipt.
    %{"tickets" => %{"ML-1" => t}} = ok!(~w(status ML-1))
    assert t["phase"] == "reviewing"
    [attempt] = Map.values(t["attempts"])

    assert %{"effect_status" => "issued"} =
             Enum.find(attempt["executions"], &(&1["role"] == "reviewer"))

    assert %{"phase" => "queued"} =
             ok!(~w(review ML-1 --principal #{@rev} --verdict correction
                    --candidate #{c.candidate} --notes #{c.notes}))
  end

  test "settle: non_started needs both quiescence flags; unknown holds", c do
    start!(c)
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    base = ~w(settle ML-1 --role developer --principal #{@dev} --attest gone)

    refused!(base ++ ~w(--outcome non_started --issuer-gone), "quiescence_not_attested")
    refused!(base ++ ~w(--outcome sideways), "invalid_outcome")

    assert %{"phase" => "queued", "selected_discriminator" => "below_infrastructure_limit"} =
             ok!(base ++ ~w(--outcome non_started --issuer-gone --channel-quiet))

    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    assert %{"outcome" => "unknown"} = ok!(base ++ ~w(--outcome unknown))
    %{"tickets" => %{"ML-1" => t}} = ok!(~w(status ML-1))
    executions = Enum.flat_map(Map.values(t["attempts"]), & &1["executions"])
    assert Enum.any?(executions, &(&1["effect_status"] == "unknown" and &1["awaits_operator"]))
  end

  # ── Note 1: a launch that loses a CAS race burns its id; the retry must not ─────

  test "a launch whose id a refused bundle burned retries under the next id", c do
    start!(c)
    admit!(c)
    ctx = ctx()
    id = "ML-1/developer/0/#{@dev}"

    # The racer: decides at one state, loses to a concurrent policy write, and Core
    # records its refused bundle under its id.
    {:ok, facts} =
      Replay.launch_facts(ctx, "manual-lane", "manual-lane", "starts.developer", nil)

    command = %{
      "schema_version" => 1,
      "command_id" => id,
      "type" => "plan_launch",
      "target_ids" => %{"ticket_id" => "ML-1"},
      "payload" => %{"role" => "developer"},
      "expected_revisions" => %{}
    }

    {:ok, decision} = WorkflowKernel.decide(Backend.state(ctx), command, facts)
    {:ok, _} = Backend.admit(ctx, "ML-2", Backend.state(ctx)["tickets"]["ML-1"]["spec"])
    assert {:ok, %{"disposition" => refused}, _} = Replay.submit(ctx, decision, @dev)
    assert refused != "accepted"

    # The same id is now an idempotency conflict; the CLI's launch takes the next.
    assert %{"packet" => %{"execution_id" => exec, "issuer" => @dev}} =
             ok!(~w(packet ML-1 --role developer --principal #{@dev}))

    assert exec == "#{id}/retry-1/execution"
    assert %{"phase" => "awaiting_review"} = submit!(c)
    stop_supervised!(Server)
    start!(c)
    assert_ready!()
  end

  # ── Observation: lane log, the operator log, Logger ─────────────────────────────

  defp operator_log(c),
    do: Path.join(c.root, "state/manual-lane/operator.log.jsonl")

  defp operator_lines(c),
    do:
      operator_log(c)
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

  test "lane log shows the full trail, a refused same-principal review included", c do
    start!(c)
    admit!(c)
    ok!(~w(packet ML-1 --role developer --principal #{@dev}))
    submit!(c)
    refused!(~w(packet ML-1 --role reviewer --principal #{@dev}), "principal_not_independent")
    ok!(~w(packet ML-1 --role reviewer --principal #{@rev}))

    ok!(~w(review ML-1 --principal #{@rev} --verdict approved
           --candidate #{c.candidate} --notes #{c.notes}))

    %{"mode" => "ready", "trail" => %{"ML-1" => t} = all} = ok!(~w(log ML-1))
    assert Map.keys(all) == ["ML-1"]

    # The whole durable trail, in commit order.
    assert Enum.map(t["events"], &{&1["seq"], &1["type"]}) == [
             {1, "ticket_admitted"},
             {2, "launch_planned"},
             {3, "artifact_frozen"},
             {4, "stream_sealed"},
             {5, "developer_closed"},
             {6, "checks_started"},
             {7, "review_planned"},
             {8, "stream_sealed"},
             {9, "review_recorded"},
             {10, "reviewer_closed"}
           ]

    assert %{"verdict" => "approved", "candidate_id" => cand} = Enum.at(t["events"], 8)
    assert cand == c.candidate

    assert t["refusals"] == [
             %{
               "command_id" => "ML-1/reviewer/0/#{@dev}",
               "actor" => @dev,
               "reason_code" => "principal_not_independent"
             }
           ]

    assert [dev, rev] = t["effects"]
    assert dev["principals"] == %{"issuer" => @dev, "inbox" => nil}
    assert rev["principals"] == %{"issuer" => @rev, "inbox" => nil}

    for page <- [dev, rev] do
      assert %{"status" => "succeeded", "receipt_history" => "complete"} = page["settlement"]

      assert ~w(claim receipt reservation) == Enum.map(page["relations"], & &1["kind"])
    end

    # Every lane ticket without an id; an unknown id is refused; text is the default.
    assert %{"trail" => %{"ML-1" => ^t}} = ok!(~w(log))
    refused!(~w(log ML-9), "ticket_not_found")

    text = capture_io(fn -> RPC.run(encode(~w(lane log ML-1))) end)
    assert text =~ "principal_not_independent ML-1/reviewer/"
    assert text =~ "issuer=#{@rev}"
    # One operator line per command, refusals included; no line is read back.
    lines = operator_lines(c)
    assert length(lines) == 10

    assert %{"result" => "principal_not_independent", "principal" => @dev, "ticket_id" => "ML-1"} =
             Enum.at(lines, 3)

    assert %{"result" => "ok", "phase" => "ready_to_integrate", "principal" => @rev} =
             Enum.at(lines, 5)

    assert Enum.all?(lines, &(is_integer(&1["duration_ms"]) and &1["ts"] =~ ~r/Z$/))
    assert Enum.at(lines, 0)["argv"] |> hd() == "admit"
  end

  test "an operator log write failure warns and leaves the outcome unchanged", c do
    start!(c)
    File.mkdir_p!(operator_log(c))

    stderr =
      capture_io(:stderr, fn ->
        admit!(c)
        refused!(~w(packet ML-1 --role developer), "principal_required")
      end)

    assert stderr =~ "warning: operator log not written"
    assert %{"tickets" => %{"ML-1" => %{"phase" => "queued"}}} = ok!(~w(status ML-1))
  end

  test "lane log reads the store in recovery; status still refuses", c do
    start_supervised!(Supervisor.child_spec({Server, c.opts}, restart: :temporary))
    admit!(c)
    %{gateway: gateway} = Server.context()
    refs = Enum.map([gateway, Process.whereis(Server)], &Process.monitor/1)
    Process.exit(gateway, :kill)
    Process.exit(Process.whereis(Server), :kill)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 5_000)
    start_supervised!(Supervisor.child_spec({Server, c.opts}, restart: :temporary))

    refused!(~w(status), "gateway_recovery")
    assert %{"mode" => "recovery", "trail" => %{"ML-1" => t}} = ok!(~w(log ML-1))
    assert [%{"type" => "ticket_admitted"}] = t["events"]

    # Unreadable data prints gateway_recovery, as every other command does.
    File.rm!(Server.context().store_path)
    File.write!(Server.context().store_path, "not sqlite")
    assert %{"detail" => %{"next" => _}} = refused!(~w(log ML-1), "gateway_recovery")
  end

  test "no Logger in Core or the workflow kernel" do
    offenders =
      for dir <- ~w(durable_store workflow),
          file <- Path.wildcard("lib/pramana_foundry/#{dir}/**/*.ex"),
          File.read!(file) =~ ~r/\bLogger\b/,
          do: file

    assert offenders == []
  end

  # ── RPC shapes ───────────────────────────────────────────────────────────────────

  test "RPC.decode accepts each lane shape and refuses unknown ones" do
    accepted = [
      ~w(lane admit ML-1 --base-ref main --title t --scope a,b --acceptance x --acceptance y),
      ~w(lane packet ML-1 --role developer --principal p --out /tmp/p.json),
      ~w(lane submit ML-1 --principal p --candidate abc --checkout /tmp --blocked why),
      ~w(lane review ML-1 --principal p --verdict approved --candidate abc --notes /tmp/n),
      ~w(lane settle ML-1 --role developer --principal p --outcome non_started --attest s
         --issuer-gone --channel-quiet),
      ~w(lane status),
      ~w(lane status ML-1 --json),
      ~w(lane log),
      ~w(lane log ML-1 --json),
      ~w(lane packet ML-1)
    ]

    refused = [
      ~w(lane),
      ~w(lane launch ML-1),
      ~w(lane status ML-1 ML-2),
      ~w(lane log ML-1 --principal p),
      ~w(lane packet),
      ~w(lane packet ML-1 --role developer --role reviewer),
      ~w(lane packet ML-1 --verdict approved),
      ~w(lane admit ML-1 --title),
      ~w(lane settle ML-1 --issuer-gone yes)
    ]

    for argv <- accepted, do: assert({:ok, ^argv} = RPC.decode(encode(argv)))
    for argv <- refused, do: assert({:error, :unknown_command_shape} = RPC.decode(encode(argv)))
  end

  defp encode(argv),
    do: %{"version" => 1, "argv" => argv} |> JSON.encode!() |> Base.url_encode64(padding: false)
end
