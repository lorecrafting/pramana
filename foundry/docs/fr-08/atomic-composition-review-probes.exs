# Independent review of 9a8a4912bcc86d1f58b50a65f9cc148982ac3915.
# Run with MIX_ENV=test mix run --no-start docs/fr-08/atomic-composition-review-probes.exs
# Required-behavior assertions deliberately fail on the reviewed candidate.
ExUnit.start(seed: 92022)
base = File.read!("test/pramana_foundry/durable_store/atomic_bundle_test.exs")

base =
  String.replace(
    base,
    "PramanaFoundry.DurableStore.AtomicBundleTest",
    "PramanaFoundry.AtomicCompositionIndependentReview"
  )

base = Regex.replace(~r/\nend\s*\z/, base, "\n")

extra = ~S"""
  alias PramanaFoundry.DurableStore.Encoding

  defp decode_review(bytes), do: bytes |> :json.decode() |> normalize_review()
  defp normalize_review(:null), do: nil
  defp normalize_review(m) when is_map(m), do: Map.new(m, fn {k, v} -> {k, normalize_review(v)} end)
  defp normalize_review(l) when is_list(l), do: Enum.map(l, &normalize_review/1)
  defp normalize_review(v), do: v

  defp reopen_review(ctx) do
    stop_supervised!(Gateway)
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"})
    %{ctx | gateway: gateway}
  end

  defp corrupt_review(ctx, fun) do
    stop_supervised!(Gateway)
    {:ok, conn} = Sqlite3.open(ctx.path, mode: :readwrite)
    fun.(conn)
    :ok = Sqlite3.close(conn)
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"})
    %{ctx | gateway: gateway}
  end

  test "review: early protected rejection is durable with unexecuted suffix", ctx do
    b = policy_bundle("early-reject", "early-policy")
    [op] = b["operations"]
    bad = put_in(op, ["expected_revisions"], %{})
    b = Map.put(b, "operations", [bad, op])
    assert {:ok, %{"disposition" => "rejected"} = result, :rejected} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    assert %{mode: :ready} = Gateway.status(ctx.gateway)
    assert {:ok, ^result, :idempotent} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
  end

  test "review: cached rejected synthetic operation cannot authorize domain mutation", ctx do
    b = policy_bundle("cached-rejection", "absent-policy")
    [op] = b["operations"]
    op = put_in(op, ["expected_revisions"], %{})
    b = Map.put(b, "operations", [op])
    req = root_command("cached-rejection/protected/0", %{}, op["operation"])
    assert {:ok, %{"disposition" => "rejected"}, :committed} = Gateway.protected_command(ctx.gateway, ctx.capability, "operator", req)
    result = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    refute match?({:ok, %{"disposition" => "accepted"}, :committed}, result), inspect(result)
  end

  test "review: global identity cannot downgrade atomic bundle to domain-only retry", ctx do
    b = policy_bundle("cross-route", "policy")
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    assert {:error, :idempotency_conflict} = Gateway.transact(ctx.gateway, "operator", b["command"], b["proposal"])
  end

  test "review: restored settlement ordinal must derive from retained receipt", ctx do
    seed_issued_launch!(ctx)
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", nonstart_bundle("settlement-corruption"))
    ctx = corrupt_review(ctx, fn conn ->
      {:ok, [[bytes]]} = Database.query(conn, "SELECT state FROM root_infrastructure_settlements WHERE effect_id = 'effect-1'")
      state = :json.decode(bytes) |> Map.put("ordinal", 900) |> Map.put("role", "pm") |> Map.put("work_owner", "invented-owner") |> Map.put("infrastructure_generation", 99)
      state = Map.put(state, "predecessor_effect_id", nil)
      {:ok, altered} = Encoding.json(state)
      :ok = Database.execute(conn, "UPDATE root_infrastructure_settlements SET ordinal = 900, role = 'pm', work_owner = 'invented-owner', infrastructure_generation = 99, state = ? WHERE effect_id = 'effect-1'", [{:blob, altered}])
    end)
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end

  test "review: deleting settlement cannot silently erase infrastructure evidence", ctx do
    seed_issued_launch!(ctx)
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", nonstart_bundle("settlement-deletion"))
    ctx = corrupt_review(ctx, fn conn -> :ok = Database.execute(conn, "DELETE FROM root_infrastructure_settlements") end)
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end

  test "review: protected v1 singleton history is required and byte-bound", ctx do
    accept_current!(ctx, %{"type" => "set_policy", "policy_id" => "legacy", "value" => %{}})
    ctx = corrupt_review(ctx, fn conn ->
      :ok = Database.execute(conn, "UPDATE durable_operations SET operation_type = 'grant_ledger', request = ?, result = ? WHERE owner_kind = 'protected_v1'", [{:blob, "invented"}, {:blob, "invented"}])
    end)
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end

  test "review: missing v1 singleton history fails closed", ctx do
    accept_current!(ctx, %{"type" => "set_policy", "policy_id" => "legacy", "value" => %{}})
    ctx = corrupt_review(ctx, fn conn -> :ok = Database.execute(conn, "DELETE FROM durable_operations") end)
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end

  test "review: partial v2 migration cannot preserve forged singleton rows", ctx do
    accept_current!(ctx, %{"type" => "set_policy", "policy_id" => "legacy", "value" => %{}})
    stop_supervised!(Gateway)
    {:ok, conn} = Sqlite3.open(ctx.path, mode: :readwrite)
    :ok = Database.execute(conn, "UPDATE metadata SET value = '1' WHERE key = 'protected_schema_version'")
    :ok = Database.execute(conn, "DELETE FROM metadata WHERE key = 'migration_atomic_bundle_v2'")
    :ok = Database.execute(conn, "DROP TABLE root_infrastructure_settlements")
    :ok = Database.execute(conn, "DROP TABLE atomic_bundles")
    :ok = Database.execute(conn, "UPDATE durable_operations SET request = ?, result = ?", [{:blob, "forged"}, {:blob, "forged"}])
    :ok = Sqlite3.close(conn)
    assert {:error, _} = Gateway.migrate(ctx.path)
  end

  test "review: bundle result cannot drop protected operation outcomes", ctx do
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", policy_bundle("missing-outcomes", "policy"))
    ctx = corrupt_review(ctx, fn conn ->
      {:ok, [[bytes]]} = Database.query(conn, "SELECT result FROM atomic_bundles WHERE command_id = 'missing-outcomes'")
      result = decode_review(bytes) |> Map.put("operations", [])
      {:ok, altered} = Encoding.json(result)
      :ok = Database.execute(conn, "UPDATE atomic_bundles SET result = ? WHERE command_id = 'missing-outcomes'", [{:blob, altered}])
    end)
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end

  test "review: malformed typed row fences instead of crashing gateway startup", ctx do
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", policy_bundle("wrong-kind", "policy"))
    ctx = corrupt_review(ctx, fn conn ->
      :ok = Database.execute(conn, "UPDATE durable_operations SET operation_kind = 'domain' WHERE owner_kind = 'bundle_v2' AND ordinal = 0")
    end)
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end

  test "review: staged writes use prestate CAS and declared dependency semantics", ctx do
    b = policy_bundle("staged-cas", "same-policy")
    [first] = b["operations"]
    second = put_in(first, ["operation", "value"], %{"allowed_operations" => ["launch"]})
    # Both operations read the same absent prestate; operation order is explicit.
    b = Map.put(b, "operations", [first, second])
    assert {:ok, %{"disposition" => "accepted"}, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
  end

  test "review: same receipt new command returns existing nonstart settlement", ctx do
    seed_issued_launch!(ctx)
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", nonstart_bundle("first-receipt"))
    b = nonstart_bundle("same-receipt") |> put_in(["operations", Access.at(0), "expected_revisions"], %{
      "claim/claim-1" => 2, "effect/effect-1" => 3, "policy/policy-1" => 0,
      "control/control-1" => 0, "reservation/reservation-1" => 4, "ledger/ledger-1/0" => 2,
      "receipt/receipt-1" => 0, "settlement/effect-1" => 0,
      infrastructure_key("developer", "1") => 1
    })
    result = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    assert {:ok, %{"disposition" => "rejected", "operations" => [%{"result" => %{"facts" => %{"infrastructure_settlement" => %{"ordinal" => 1}}}}]}, :rejected} = result
  end

  test "review: stale read rejects while preserving exact retry and root state", ctx do
    first = policy_bundle("first-policy", "policy")
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", first)
    b = policy_bundle("stale-policy", "policy")
    assert {:ok, %{"disposition" => "rejected"} = r, :rejected} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    ctx = reopen_review(ctx)
    assert %{mode: :ready} = Gateway.status(ctx.gateway)
    assert {:ok, ^r, :idempotent} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    assert {:ok, %{"revision" => 0}} = fact(ctx, "policy", "policy_id", "policy")
  end

  test "review: copied bundle facts must match actual protected outcomes", ctx do
    b = policy_bundle("forged-copy", "policy")
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    ctx = corrupt_review(ctx, fn conn ->
      {:ok, [[bytes]]} = Database.query(conn, "SELECT result FROM atomic_bundles WHERE command_id = 'forged-copy'")
      result = decode_review(bytes)
      altered = put_in(result, ["operations", Access.at(0), "result", "facts", "root_policie", "revision"], 999)
      {:ok, bundle_bytes} = Encoding.json(altered)
      {:ok, op_bytes} = Encoding.json(hd(altered["operations"])["result"])
      :ok = Database.execute(conn, "UPDATE atomic_bundles SET result = ? WHERE command_id = 'forged-copy'", [{:blob, bundle_bytes}])
      :ok = Database.execute(conn, "UPDATE durable_operations SET result = ? WHERE owner_kind = 'bundle_v2' AND owner_id = 'forged-copy' AND ordinal = 0", [{:blob, op_bytes}])
    end)
    assert %{mode: :recovery} = Gateway.status(ctx.gateway)
  end

  test "review: unknown start retains holds across reopen and rejects replacement", ctx do
    seed_issued_launch!(ctx)
    b = nonstart_bundle("unknown-start")
      |> put_in(["operations", Access.at(0), "operation", "outcome"], "unknown")
      |> put_in(["operations", Access.at(0), "operation", "proof"], "outcome_unknown")
      |> update_in(["operations", Access.at(0), "expected_revisions"], fn reads ->
        Map.drop(reads, ["settlement/effect-1", infrastructure_key("developer", "1")])
      end)
    assert {:ok, %{"disposition" => "accepted"}, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    ctx = reopen_review(ctx)
    assert {:ok, %{"held" => 1, "available" => 1}} = Gateway.protected_query(ctx.gateway, ctx.capability, %{"schema_version" => 1, "type" => "ledger", "ledger_id" => "ledger-1", "generation" => 0})
    assert {:ok, %{"status" => "unknown"}} = fact(ctx, "effect", "effect_id", "effect-1")
    assert {:ok, %{"status" => "issued_unknown"}} = fact(ctx, "reservation", "reservation_id", "reservation-1")
  end

  for status <- ["cancel_requested"] do
    @review_status status
    test "review: nonstart settles original owner under #{@review_status} control", ctx do
      seed_issued_launch!(ctx)
      accept_current!(ctx, %{"type" => "set_control", "control_id" => "control-1", "value" => %{"status" => @review_status}})
      b = nonstart_bundle("controlled-#{@review_status}") |> put_in(["operations", Access.at(0), "expected_revisions", "control/control-1"], 1)
      assert {:ok, %{"disposition" => "accepted"}, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
      ctx = reopen_review(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.gateway)
      assert {:ok, %{"status" => "released"}} = fact(ctx, "reservation", "reservation_id", "reservation-1")
    end
  end

  test "review: quarantine mixed with policy mutation commits neither productive change nor domain", ctx do
    seed_issued_launch!(ctx)
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", nonstart_bundle("settled"))
    b = nonstart_bundle("mixed-quarantine")
      |> put_in(["operations", Access.at(0), "expected_revisions"], %{
        "claim/claim-1" => 2, "effect/effect-1" => 3, "policy/policy-1" => 0, "control/control-1" => 0,
        "reservation/reservation-1" => 4, "ledger/ledger-1/0" => 2, "receipt/conflict" => "absent"
      })
      |> put_in(["operations", Access.at(0), "operation", "receipt_id"], "conflict")
      |> put_in(["operations", Access.at(0), "operation", "outcome"], "failed")
      |> put_in(["operations", Access.at(0), "operation", "proof"], "delivered")
    [productive] = policy_bundle("unused", "must-not-exist")["operations"]
    b = Map.update!(b, "operations", &[productive | &1])
    assert {:ok, %{"disposition" => "rejected"}, :rejected} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
    assert {:error, :policy_not_found} = fact(ctx, "policy", "policy_id", "must-not-exist")
    assert {:ok, %{"status" => "non_started"}} = fact(ctx, "claim", "claim_id", "claim-1")
  end

  for table <- ~w(root_policy_history root_policies root_commands inputs commands events projections command_results durable_operations atomic_bundles) do
    @abort_table table
    test "review: SQLite abort at #{@abort_table} leaves no accepted partial bundle", ctx do
      ctx = corrupt_review(ctx, fn conn ->
        :ok = Database.execute(conn, "CREATE TRIGGER review_abort BEFORE INSERT ON #{@abort_table} BEGIN SELECT RAISE(ABORT, 'independent-review-abort'); END")
      end)
      assert %{mode: :ready} = Gateway.status(ctx.gateway)
      b = policy_bundle("write-abort", "must-rollback")
      assert {:error, {:storage_unavailable, _}} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", b)
      ctx = corrupt_review(ctx, fn conn -> :ok = Database.execute(conn, "DROP TRIGGER review_abort") end)
      assert %{mode: :ready} = Gateway.status(ctx.gateway)
      assert {:error, :policy_not_found} = fact(ctx, "policy", "policy_id", "must-rollback")
      assert {:error, :not_found} = Gateway.command(ctx.gateway, "write-abort")
    end
  end
end
"""

Code.eval_string(base <> extra, [], file: __ENV__.file)
