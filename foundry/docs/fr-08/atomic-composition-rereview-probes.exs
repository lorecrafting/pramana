# Independent variants against 154a9fb; disposable fixture stores only.
# MIX_ENV=test mix run --no-start docs/fr-08/atomic-composition-rereview-probes.exs
ExUnit.start(seed: 92032)
base = File.read!("test/pramana_foundry/durable_store/atomic_bundle_test.exs")
base = String.replace(base, "PramanaFoundry.DurableStore.AtomicBundleTest", "PramanaFoundry.AtomicCompositionRereview")
base = Regex.replace(~r/\nend\s*\z/, base, "\n")
extra = ~S"""
  alias PramanaFoundry.DurableStore.Encoding
  defp change_bundle(ctx, id, transform) do
    stop_supervised!(Gateway)
    {:ok, conn} = Sqlite3.open(ctx.path, mode: :readwrite)
    {:ok, [[bytes]]} = Database.query(conn, "SELECT result FROM atomic_bundles WHERE command_id = ?", [id])
    result = bytes |> :json.decode() |> rereview_normalize() |> transform.()
    {:ok, encoded} = Encoding.json(result)
    :ok = Database.execute(conn, "UPDATE atomic_bundles SET result = ? WHERE command_id = ?", [{:blob, encoded}, id])
    case result["operations"] do
      [%{"result" => operation_result, "execution_status" => status}] ->
        {:ok, encoded} = Encoding.json(%{"schema_version" => 1, "execution_status" => status, "operation_result" => operation_result})
        :ok = Database.execute(conn, "UPDATE durable_operations SET result = ? WHERE owner_kind = 'bundle_v2' AND owner_id = ? AND ordinal = 0", [{:blob, encoded}, id])
      _ -> :ok
    end
    :ok = Sqlite3.close(conn)
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"})
    %{ctx | gateway: gateway}
  end
  defp rereview_normalize(:null), do: nil
  defp rereview_normalize(m) when is_map(m), do: Map.new(m, fn {k,v} -> {k, rereview_normalize(v)} end)
  defp rereview_normalize(l) when is_list(l), do: Enum.map(l, &rereview_normalize/1)
  defp rereview_normalize(v), do: v

  test "rereview: scalar outcome enters recovery without crashing startup", ctx do
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", policy_bundle("scalar-outcome", "policy"))
    ctx = change_bundle(ctx, "scalar-outcome", &Map.put(&1, "operations", [17]))
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end

  test "rereview: settlement carrier must equal receipt-derived immutable row", ctx do
    seed_issued_launch!(ctx)
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", nonstart_bundle("forged-carrier"))
    ctx = change_bundle(ctx, "forged-carrier", fn result ->
      [op] = result["operations"]
      op = put_in(op, ["result", "facts", "infrastructure_settlement", "ordinal"], 900)
      Map.put(result, "operations", [op])
    end)
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end
end
"""
Code.compile_string(base <> extra, "atomic_composition_rereview_generated.exs")
