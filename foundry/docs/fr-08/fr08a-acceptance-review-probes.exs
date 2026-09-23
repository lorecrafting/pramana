# Fresh acceptance variations. Reuse the maintained public fixture helpers and
# required-behavior tests without editing that historical reviewer artifact.
base = File.read!("docs/fr-08/fr08a-final-review-probes.exs")
base = Regex.replace(~r/\nend\s*\z/, base, "\n")
extra = ~S"""
  defp chain(ctx, depth) do
    accept(ctx, policy() |> Map.put("policy_id", "chain") |> put_in(["value", "infrastructure_attempt_limits"], %{"developer" => depth + 2}))
    for i <- 0..depth do
      id = "chain-#{i}"
      prepare(ctx, id, fn op ->
        op = Map.put(op, "policy_id", "chain") |> put_in(["request", "operation_ordinal"], i)
        if i == 0, do: op, else: put_in(op, ["request", "predecessor_effect_id"], "chain-#{i - 1}")
      end)
      if i < depth do
        issue(ctx, id)
        accept(ctx, receipt(id, "ns-#{i}", "non_started", "issuer_quiescent"))
      end
    end
    "chain-#{depth}"
  end

  defp required(ctx, op) do
    {:ok, %{"reason_code" => "incomplete_read_set", "facts" => %{"required_revisions" => reads}}, :committed} =
      Gateway.protected_command(ctx.g, ctx.cap, "operator", req(op, %{}))
    reads
  end

  for stage <- [:claim, :issue] do
    @stage stage
    test "acceptance: five-deep ancestry CAS and quarantine at #{@stage}", ctx do
      id = chain(ctx, 5)
      claim = %{"type" => "claim_effect", "effect_id" => id, "claim_id" => "cl-" <> id, "writer_epoch" => "epoch-A"}
      op = if @stage == :claim do
        claim
      else
        accept(ctx, claim)
        %{"type" => "issue_claim", "claim_id" => "cl-" <> id, "writer_epoch" => "epoch-A"}
      end
      reads = required(ctx, op)
      for i <- 0..4, do: assert(Map.has_key?(reads, "effect/chain-#{i}"))
      {:ok, %{"reason_code" => "incomplete_read_set"}, :committed} =
        Gateway.protected_command(ctx.g, ctx.cap, "operator", req(op, Map.delete(reads, "effect/chain-0")))
      rejected(submit(ctx, receipt("chain-1", "late-deep", "succeeded", "delivered")))
      {:ok, %{"reason_code" => "stale_read_set"}, :committed} =
        Gateway.protected_command(ctx.g, ctx.cap, "operator", req(op, reads))
      rejected(submit(ctx, op))
      ctx = reopen(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.g)
      rejected(submit(ctx, op))
      assert {:ok, %{"held" => 1, "available" => 19}} = ledger(ctx)
    end
  end

  test "acceptance: five-deep terminal ancestry allows issuance after restart", ctx do
    id = chain(ctx, 5)
    ctx = reopen(ctx)
    assert %{mode: :ready} = Gateway.status(ctx.g)
    issue(ctx, id)
    accept(ctx, receipt(id, "final-success", "succeeded", "delivered"))
    ctx = reopen(ctx)
    assert %{mode: :ready} = Gateway.status(ctx.g)
    assert {:ok, %{"held" => 0, "consumed" => 1, "available" => 19}} = ledger(ctx)
  end

  for deadline <- [nil, "500", 499, 501] do
    @deadline deadline
    test "acceptance: explicit deadline #{inspect(deadline)} is refused by policy", ctx do
      accept(ctx, policy() |> Map.put("policy_id", "bounded") |> put_in(["value", "allowed_deadlines"], [500]))
      reserve(ctx, "r-e", "e")
      op = effect("e") |> Map.put("policy_id", "bounded") |> put_in(["request", "deadline"], @deadline)
      rejected(submit(ctx, op))
      assert {:ok, %{"held" => 0, "available" => 20}} = ledger(ctx)
      ctx = reopen(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.g)
    end
  end

  test "acceptance: approved deadline survives claim issue settlement and restart", ctx do
    accept(ctx, policy() |> Map.put("policy_id", "bounded") |> put_in(["value", "allowed_deadlines"], [500]))
    prepare(ctx, "e", fn op -> op |> Map.put("policy_id", "bounded") |> put_in(["request", "deadline"], 500) end)
    issue(ctx)
    accept(ctx, receipt("e", "bounded-success", "succeeded", "delivered"))
    ctx = reopen(ctx)
    assert %{mode: :ready} = Gateway.status(ctx.g)
    assert {:ok, %{"deadline" => 500}} = fact(ctx, "effect", "effect_id", "e")
  end

  test "acceptance: null deadline in explicit allowlist cannot create unbounded admission", ctx do
    accept(ctx, policy() |> Map.put("policy_id", "bounded") |> put_in(["value", "allowed_deadlines"], [nil, 500]))
    reserve(ctx, "r-e", "e")
    rejected(submit(ctx, effect("e") |> Map.put("policy_id", "bounded") |> put_in(["request", "deadline"], nil)))
  end

  defp epoch(ctx, name) do
    :ok = stop_supervised(Gateway)
    ctx = start_again(ctx, name)
    assert %{mode: :ready} = Gateway.status(ctx.g)
    ctx
  end

  defp reclaim(ctx, prior, next) do
    accept(ctx, %{"type" => "reclaim_claim", "claim_id" => "cl-e", "prior_writer_epoch" => prior,
      "new_writer_epoch" => next, "proof" => "issuer_quiescent"})
  end

  defp command_log(path) do
    {:ok, conn} = Sqlite3.open(path)
    {:ok, stmt} = Sqlite3.prepare(conn, "SELECT seq, command_id, actor_id, request_digest, canonical_request, operation, disposition, reason_code, result FROM root_commands ORDER BY seq")
    {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
    :ok = Sqlite3.release(conn, stmt)
    :ok = Sqlite3.close(conn)
    rows
  end

  test "acceptance: two linear reclaims preserve one hold and permit current issue", ctx do
    prepare(ctx)
    accept(ctx, %{"type" => "claim_effect", "effect_id" => "e", "claim_id" => "cl-e", "writer_epoch" => "epoch-A"})
    ctx = epoch(ctx, "epoch-B")
    reclaim(ctx, "epoch-A", "epoch-B")
    ctx = epoch(ctx, "epoch-C")
    rejected(submit(ctx, %{"type" => "reclaim_claim", "claim_id" => "cl-e", "prior_writer_epoch" => "epoch-A",
      "new_writer_epoch" => "epoch-C", "proof" => "issuer_quiescent"}))
    reclaim(ctx, "epoch-B", "epoch-C")
    ctx = epoch(ctx, "epoch-C")
    rejected(submit(ctx, %{"type" => "issue_claim", "claim_id" => "cl-e", "writer_epoch" => "epoch-B"}))
    accept(ctx, %{"type" => "issue_claim", "claim_id" => "cl-e", "writer_epoch" => "epoch-C"})
    assert {:ok, %{"held" => 1, "available" => 19}} = ledger(ctx)
    ctx = epoch(ctx, "epoch-C")
    assert {:ok, %{"writer_epoch" => "epoch-C", "status" => "issued"}} = fact(ctx, "claim", "claim_id", "cl-e")
  end

  test "acceptance: mutually forged claim carriers and retained result cannot invent takeover", ctx do
    prepare(ctx)
    accept(ctx, %{"type" => "claim_effect", "effect_id" => "e", "claim_id" => "cl-e", "writer_epoch" => "epoch-A"})
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_claims", "state", "claim_id = 'cl-e'", &Map.put(&1, "writer_epoch", "epoch-B"))
    sql(ctx.path, "UPDATE root_claims SET writer_epoch = 'epoch-B' WHERE claim_id = 'cl-e'")
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'claim_effect' AND disposition = 'accepted'", &put_in(&1, ["facts", "claim", "writer_epoch"], "epoch-B"))
    ctx = start_again(ctx, "epoch-B")
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  test "acceptance: mutually forged final reclaim carriers cannot replace authenticated epoch", ctx do
    prepare(ctx)
    accept(ctx, %{"type" => "claim_effect", "effect_id" => "e", "claim_id" => "cl-e", "writer_epoch" => "epoch-A"})
    ctx = epoch(ctx, "epoch-B")
    reclaim(ctx, "epoch-A", "epoch-B")
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_claims", "state", "claim_id = 'cl-e'", &Map.put(&1, "writer_epoch", "epoch-C"))
    sql(ctx.path, "UPDATE root_claims SET writer_epoch = 'epoch-C' WHERE claim_id = 'cl-e'")
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'reclaim_claim' AND disposition = 'accepted'", &put_in(&1, ["facts", "claim", "writer_epoch"], "epoch-C"))
    ctx = start_again(ctx, "epoch-C")
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  test "acceptance: mutually forged delegated credit cannot exceed authenticated allocation", ctx do
    accept(ctx, %{"type" => "delegate_allocation", "parent_ledger_id" => "root", "parent_generation" => 0,
      "child_ledger_id" => "child", "child_generation" => 0, "dimension" => "starts.developer", "units" => 4})
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_ledgers", "state", "ledger_id = 'root'", &(&1 |> Map.put("available", 12) |> Map.put("delegated", 8)))
    mutate_blob(ctx.path, "root_ledgers", "state", "ledger_id = 'child'", &(&1 |> Map.put("authorized", 8) |> Map.put("available", 8)))
    sql(ctx.path, "UPDATE root_ledgers SET available = 12, delegated = 8 WHERE ledger_id = 'root'; UPDATE root_ledgers SET authorized = 8, available = 8 WHERE ledger_id = 'child'")
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'delegate_allocation' AND disposition = 'accepted'", fn r ->
      r |> update_in(["facts", "child_ledger"], &(&1 |> Map.put("authorized", 8) |> Map.put("available", 8)))
        |> update_in(["facts", "parent_ledger"], &(&1 |> Map.put("available", 12) |> Map.put("delegated", 8)))
    end)
    ctx = start_again(ctx)
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  test "acceptance: mutually forged reset credit cannot exceed authenticated reset grant", ctx do
    accept(ctx, %{"type" => "reset_generation", "ledger_id" => "root", "old_generation" => 0,
      "new_generation" => 1, "parent_ledger_id" => nil, "parent_generation" => nil, "units" => 7})
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_ledgers", "state", "ledger_id = 'root' AND generation = 1", &(&1 |> Map.put("authorized", 70) |> Map.put("available", 70)))
    sql(ctx.path, "UPDATE root_ledgers SET authorized = 70, available = 70 WHERE ledger_id = 'root' AND generation = 1")
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'reset_generation' AND disposition = 'accepted'", &update_in(&1, ["facts", "new_generation"], fn l -> l |> Map.put("authorized", 70) |> Map.put("available", 70) end))
    ctx = start_again(ctx)
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  test "acceptance: immutable predecessor cannot be invented in mutually forged effect and result", ctx do
    prepare(ctx)
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_effects", "state", "effect_id = 'e'", &Map.put(&1, "predecessor_effect_id", "invented"))
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'create_effect' AND disposition = 'accepted'", &put_in(&1, ["facts", "effect", "predecessor_effect_id"], "invented"))
    ctx = start_again(ctx)
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  for takeover <- [false, true] do
    @takeover takeover
  test "acceptance: recovery cannot rewind an issued claim into fresh delivery authority takeover=#{takeover}", ctx do
    prepare(ctx)
    issue(ctx)
    :ok = stop_supervised(Gateway)
    original_commands = command_log(ctx.path)
    for {table, where, status} <- [{"root_claims", "claim_id = 'cl-e'", "claimed"}, {"root_effects", "effect_id = 'e'", "claimed"}, {"root_reservations", "reservation_id = 'r-e'", "reserved"}] do
      mutate_blob(ctx.path, table, "state", where, &Map.put(&1, "status", status))
      sql(ctx.path, "UPDATE #{table} SET status = '#{status}' WHERE #{where}")
    end
    assert original_commands == command_log(ctx.path)
    next_epoch = if @takeover, do: "epoch-B", else: "epoch-A"
    ctx = start_again(ctx, next_epoch)
    status = Gateway.status(ctx.g)
    if @takeover and status.mode == :ready, do: reclaim(ctx, "epoch-A", "epoch-B")
    result = submit(ctx, %{"type" => "issue_claim", "claim_id" => "cl-e", "writer_epoch" => next_epoch})
    IO.inspect({status, result}, label: "ACCEPTANCE issued rewind")
    assert %{mode: :recovery} = status
  end
  end

  test "acceptance: recovery cannot reopen closed generation by matching forged carriers", ctx do
    accept(ctx, %{"type" => "close_generation", "ledger_id" => "root", "generation" => 0})
    :ok = stop_supervised(Gateway)
    original_commands = command_log(ctx.path)
    mutate_blob(ctx.path, "root_ledgers", "state", "ledger_id = 'root'", fn state ->
      state |> Map.put("status", "open") |> Map.put("available", 20) |> Map.put("retired", 0)
    end)
    sql(ctx.path, "UPDATE root_ledgers SET status = 'open', available = 20, retired = 0 WHERE ledger_id = 'root'")
    assert original_commands == command_log(ctx.path)
    ctx = start_again(ctx)
    status = Gateway.status(ctx.g)
    if status.mode == :ready do
      prepare(ctx)
      issue(ctx)
    end
    IO.inspect({status, ledger(ctx)}, label: "ACCEPTANCE closed generation reopened")
    assert %{mode: :recovery} = status
  end

  test "acceptance: recovery cannot reduce an issued hold without settlement", ctx do
    reserve(ctx, "r-e", "e", 4)
    accept(ctx, effect("e"))
    issue(ctx)
    :ok = stop_supervised(Gateway)
    original_commands = command_log(ctx.path)
    mutate_blob(ctx.path, "root_reservations", "state", "reservation_id = 'r-e'", &Map.put(&1, "units", 1))
    mutate_blob(ctx.path, "root_ledgers", "state", "ledger_id = 'root'", &(&1 |> Map.put("available", 19) |> Map.put("held", 1)))
    sql(ctx.path, "UPDATE root_reservations SET units = 1 WHERE reservation_id = 'r-e'; UPDATE root_ledgers SET available = 19, held = 1 WHERE ledger_id = 'root'")
    assert original_commands == command_log(ctx.path)
    ctx = start_again(ctx)
    IO.inspect({Gateway.status(ctx.g), ledger(ctx)}, label: "ACCEPTANCE issued hold reduced")
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end
end
"""
Code.eval_string(base <> extra, [], file: __ENV__.file)
