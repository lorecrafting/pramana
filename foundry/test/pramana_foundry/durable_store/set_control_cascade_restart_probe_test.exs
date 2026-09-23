defmodule PramanaFoundry.DurableStore.SetControlCascadeRestartProbeTest do
  # Found by Fable 5.1 reviewing d67eeac2: set_control cancel_requested cascades through cancel_effect,
  # which releases holds; set_control's facts now carry the released ledgers, so the store reopens.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway

  setup do
    root =
      Path.join(
        "/private/tmp",
        "setctl-restart-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()

    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation-fr08a",
               repository_id: "repository-fr08a"
             )

    gateway =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-fr08a"}
      )

    on_exit(fn -> File.rm_rf!(root) end)
    gw = {gateway, capability}

    for {id, op} <- [
          {"SEED-POLICY",
           %{
             "type" => "set_policy",
             "policy_id" => "policy-1",
             "value" => %{"allowed_operations" => ["launch"], "allowed_scopes" => ["ticket:T-S"]}
           }},
          {"SEED-CONTROL",
           %{
             "type" => "set_control",
             "control_id" => "control-1",
             "value" => %{"status" => "active"}
           }},
          {"SEED-LEDGER",
           %{
             "type" => "grant_ledger",
             "ledger_id" => "root",
             "generation" => 0,
             "dimension" => "starts.developer",
             "units" => 2
           }}
        ] do
      assert %{"disposition" => "accepted"} = run(gw, id, op), id
    end

    %{gw: gw, path: path, capability: capability}
  end

  for status <- ["pending", "claimed"] do
    test "cancel_requested over a #{status} effect with a hold, then reopen", ctx do
      at!(ctx.gw, unquote(status))

      assert %{"disposition" => "accepted"} =
               run(ctx.gw, "CANCEL-CTL", %{
                 "type" => "set_control",
                 "control_id" => "control-1",
                 "value" => %{"status" => "cancel_requested"}
               })

      assert %{effect: "cancelled", reservation: "released"} = state(ctx.gw)
      reopen!(ctx)
    end
  end

  defp reopen!(ctx) do
    stop_supervised!(Gateway)

    assert {:ok, gateway} =
             start_supervised(
               {Gateway,
                path: ctx.path,
                protected_capability: ctx.capability,
                writer_epoch: "writer-epoch-fr08a"},
               id: :reopened
             )

    assert %{mode: :ready, reason: nil} = Gateway.status(gateway)
    %{ctx | gw: {gateway, ctx.capability}}
  end

  defp at!(gw, status) do
    steps = [
      {"RESERVE-1",
       %{
         "type" => "reserve",
         "reservation_id" => "reservation-1",
         "ledger_id" => "root",
         "generation" => 0,
         "owner_kind" => "effect",
         "owner_id" => "effect-1",
         "units" => 1
       }},
      {"EFFECT-1",
       %{
         "type" => "create_effect",
         "effect_id" => "effect-1",
         "request" => %{"request_id" => "request-1", "role" => "developer", "profile" => "sol"},
         "operation" => "launch",
         "scope" => "ticket:T-S",
         "ticket_id" => "T-S",
         "attempt_id" => "attempt-1",
         "execution_id" => "execution-1",
         "policy_id" => "policy-1",
         "policy_revision" => 0,
         "control_id" => "control-1",
         "control_revision" => 0,
         "reservation_ids" => ["reservation-1"],
         "leases" => [%{"lease_id" => "lease-1", "resource_id" => "slot-1"}]
       }},
      {"CLAIM-1",
       %{
         "type" => "claim_effect",
         "effect_id" => "effect-1",
         "claim_id" => "claim-1",
         "writer_epoch" => "writer-epoch-fr08a"
       }}
    ]

    count = %{"pending" => 2, "claimed" => 3}[status]

    for {id, op} <- Enum.take(steps, count) do
      assert %{"disposition" => "accepted"} = run(gw, id, op), id
    end
  end

  defp state({gateway, capability}) do
    fact = fn query ->
      assert {:ok, fact} = Gateway.protected_query(gateway, capability, query)
      fact
    end

    %{
      effect: fact.(q("effect", "effect_id", "effect-1"))["status"],
      reservation: fact.(q("reservation", "reservation_id", "reservation-1"))["status"]
    }
  end

  defp q(type, key, value), do: %{"schema_version" => 1, "type" => type, key => value}

  defp run({gateway, capability}, id, operation) do
    assert {:ok, first, :committed} =
             protected(gateway, capability, id <> "-PROBE", %{}, operation)

    if first["reason_code"] == "incomplete_read_set" do
      assert {:ok, result, :committed} =
               protected(gateway, capability, id, first["facts"]["required_revisions"], operation)

      result
    else
      first
    end
  end

  defp protected(gateway, capability, id, reads, operation) do
    Gateway.protected_command(gateway, capability, "operator", %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => operation
    })
  end
end
