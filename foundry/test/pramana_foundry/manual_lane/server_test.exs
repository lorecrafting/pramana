defmodule PramanaFoundry.ManualLane.ServerTest do
  @moduledoc """
  W3 (T6, THIN-LANE-DESIGN-2026-09-23.md §5): the flagged Gateway start and its Q3 seed.

  Positive-path tests give the Server its own temporary `runtime_root:`, disjoint from the
  suite's shared root, so nothing here interferes with the real application's own children.
  The flag-gating tests instead read the real, already-booted application: the suite runs
  with `PRAMANA_MANUAL_LANE` unset, so the flag-off assertions hold for free.
  """
  use ExUnit.Case, async: false

  alias PramanaFoundry.Application, as: App
  alias PramanaFoundry.DurableStore.Gateway
  alias PramanaFoundry.ManualLane.Server
  alias PramanaFoundry.RuntimeRoot

  @valid_seed %{
    "policy" => %{
      "allowed_operations" => ["launch"],
      "allowed_scopes" => ["ticket:manual-lane"],
      "independent_of_roles" => %{"reviewer" => ["developer"]}
    },
    "control" => %{"status" => "active"},
    "starts" => %{"developer" => 3, "reviewer" => 2}
  }

  @non_independent_seed put_in(@valid_seed, ["policy", "independent_of_roles"], %{
                          "reviewer" => ["pm"]
                        })

  describe "the flag" do
    test "off: no Server process and no store file under the real runtime root" do
      refute Process.whereis(Server)

      refute File.exists?(Path.join(RuntimeRoot.fetch!(), "state/manual-lane/authority.sqlite3"))
    end

    test "on: enables the child" do
      System.put_env("PRAMANA_MANUAL_LANE", "1")
      on_exit(fn -> System.delete_env("PRAMANA_MANUAL_LANE") end)
      assert App.manual_lane_enabled?()
    end

    test "red control: \"0\" starts nothing" do
      System.put_env("PRAMANA_MANUAL_LANE", "0")
      on_exit(fn -> System.delete_env("PRAMANA_MANUAL_LANE") end)
      refute App.manual_lane_enabled?()
    end
  end

  describe "flag on" do
    setup do
      root = fresh_root()
      %{root: root, seed_path: write_seed!(root, @valid_seed)}
    end

    test "a store is created at its own path, and no legacy JSONL is touched", ctx do
      start_supervised!(
        {Server, runtime_root: ctx.root, repo: ctx.root, policy_path: ctx.seed_path}
      )

      assert File.exists?(Path.join(ctx.root, "state/manual-lane/authority.sqlite3"))
      refute File.exists?(Path.join(ctx.root, "state/current/events.jsonl"))
      refute File.exists?(Path.join(ctx.root, "state/current/coordinator.jsonl"))
      refute File.exists?(Path.join(ctx.root, "state/current/telemetry.jsonl"))
    end

    test "red control: without a repo, startup refuses", ctx do
      assert {:error, {:manual_lane_repo_missing, _child_spec}} =
               start_supervised({Server, runtime_root: ctx.root, policy_path: ctx.seed_path})

      refute Process.whereis(Server)
    end

    test "the seed is applied once, and a restart is idempotent and reopens :ready", ctx do
      opts = [runtime_root: ctx.root, repo: ctx.root, policy_path: ctx.seed_path]
      start_supervised!({Server, opts})

      ctx1 = Server.context()
      assert_seeded(ctx1)

      stop_supervised!(Server)
      start_supervised!({Server, opts})
      ctx2 = Server.context()

      assert %{mode: :ready, reason: nil} = Gateway.status(ctx2.gateway)
      assert ctx2.writer_epoch != ctx1.writer_epoch
      assert_seeded(ctx2)
    end

    test "red control: a seed whose independence pairing omits \"developer\" is refused", ctx do
      bad_path = write_seed!(ctx.root, @non_independent_seed)

      assert {:error, {:manual_lane_seed_independence_missing, _child_spec}} =
               start_supervised(
                 {Server, runtime_root: ctx.root, repo: ctx.root, policy_path: bad_path}
               )

      refute Process.whereis(Server)
    end
  end

  defp assert_seeded(ctx) do
    assert {:ok, %{"value" => %{"check_set" => []} = policy}} =
             Gateway.protected_query(ctx.gateway, ctx.capability, %{
               "schema_version" => 1,
               "type" => "policy",
               "policy_id" => "manual-lane"
             })

    assert policy["independent_of_roles"] == %{"reviewer" => ["developer"]}

    assert {:ok, %{"value" => %{"status" => "active"}}} =
             Gateway.protected_query(ctx.gateway, ctx.capability, %{
               "schema_version" => 1,
               "type" => "control",
               "control_id" => "manual-lane"
             })

    assert {:ok, %{"authorized" => 3, "dimension" => "starts.developer"}} =
             Gateway.protected_query(ctx.gateway, ctx.capability, %{
               "schema_version" => 1,
               "type" => "ledger",
               "ledger_id" => "starts.developer",
               "generation" => 0
             })

    assert {:ok, %{"authorized" => 2, "dimension" => "starts.reviewer"}} =
             Gateway.protected_query(ctx.gateway, ctx.capability, %{
               "schema_version" => 1,
               "type" => "ledger",
               "ledger_id" => "starts.reviewer",
               "generation" => 0
             })
  end

  defp fresh_root do
    root =
      Path.join(
        "/private/tmp",
        "manual-lane-server-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp write_seed!(root, seed) do
    path = Path.join(root, "seed-#{System.unique_integer([:positive, :monotonic])}.json")
    {:ok, encoded} = PramanaFoundry.DurableStore.Encoding.json(seed)
    File.write!(path, encoded)
    path
  end
end
