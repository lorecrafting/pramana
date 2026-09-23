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
      ~w(lane packet ML-1)
    ]

    refused = [
      ~w(lane),
      ~w(lane launch ML-1),
      ~w(lane status ML-1 ML-2),
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
