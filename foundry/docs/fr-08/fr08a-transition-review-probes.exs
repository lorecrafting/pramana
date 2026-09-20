# Independent residual-F2 variations; reuse only public fixture helpers.
base = File.read!("docs/fr-08/fr08a-final-review-probes.exs")
base = Regex.replace(~r/\nend\s*\z/, base, "\n")
extra = ~S"""
  defp authenticated_commands(path) do
    {:ok, conn} = Sqlite3.open(path)
    {:ok, stmt} = Sqlite3.prepare(conn, "SELECT seq, command_id, actor_id, request_digest, canonical_request, operation, disposition, reason_code FROM root_commands ORDER BY seq")
    {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
    :ok = Sqlite3.release(conn, stmt)
    :ok = Sqlite3.close(conn)
    rows
  end

  for outcome <- ["succeeded", "failed", "non_started"] do
    @outcome outcome
    test "transition: unknown then #{@outcome}, duplicate receipt and restart", ctx do
      prepare(ctx)
      issue(ctx)
      accept(ctx, receipt("e", "u", "unknown", "outcome_unknown"))
      ctx = reopen(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.g)
      proof = if @outcome == "non_started", do: "issuer_quiescent", else: "delivered"
      op = receipt("e", "terminal", @outcome, proof)
      accept(ctx, op)
      accept(ctx, op)
      ctx = reopen(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.g)
      assert {:ok, %{"held" => 0}} = ledger(ctx)
    end
  end

  for shape <- [:effect, :claim, :ledger] do
    @shape shape
    test "transition: legitimate receipt payload with #{@shape} diagnostic shape restarts", ctx do
      prepare(ctx)
      issue(ctx)
      diagnostic = case @shape do
        :effect -> %{"effect_id" => "e", "revision" => 99, "status" => "diagnostic"}
        :claim -> %{"effect_id" => "e", "claim_id" => "cl-e", "revision" => 99, "status" => "diagnostic"}
        :ledger -> %{"ledger_id" => "root", "generation" => 0, "authorized" => 20, "revision" => 99}
      end
      accept(ctx, receipt("e", "success", "succeeded", "delivered") |> put_in(["payload", "diagnostic"], diagnostic))
      ctx = reopen(ctx)
      IO.inspect(Gateway.status(ctx.g), label: "DIAGNOSTIC #{@shape}")
      assert %{mode: :ready} = Gateway.status(ctx.g)
    end
  end

  test "transition: accepted issue result cannot falsely attest claimed status", ctx do
    prepare(ctx)
    issue(ctx)
    :ok = stop_supervised(Gateway)
    requests = authenticated_commands(ctx.path)
    for {table, where, status} <- [{"root_claims", "claim_id = 'cl-e'", "claimed"}, {"root_effects", "effect_id = 'e'", "claimed"}, {"root_reservations", "reservation_id = 'r-e'", "reserved"}] do
      mutate_blob(ctx.path, table, "state", where, &Map.put(&1, "status", status))
      sql(ctx.path, "UPDATE #{table} SET status = '#{status}' WHERE #{where}")
    end
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", fn r ->
      r |> put_in(["facts", "claim", "status"], "claimed") |> put_in(["facts", "effect", "status"], "claimed")
    end)
    assert requests == authenticated_commands(ctx.path)
    ctx = start_again(ctx)
    status = Gateway.status(ctx.g)
    result = submit(ctx, %{"type" => "issue_claim", "claim_id" => "cl-e", "writer_epoch" => "epoch-A"})
    IO.inspect({status, result}, label: "FORGED ISSUE RESULT")
    assert %{mode: :recovery} = status
  end

  for stage <- [:pending, :claimed] do
    @stage stage
    test "transition: reset cancels #{@stage} with attributable restart", ctx do
      prepare(ctx)
      if @stage == :claimed, do: accept(ctx, %{"type" => "claim_effect", "effect_id" => "e", "claim_id" => "cl-e", "writer_epoch" => "epoch-A"})
      accept(ctx, %{"type" => "reset_generation", "ledger_id" => "root", "old_generation" => 0, "new_generation" => 1, "parent_ledger_id" => nil, "parent_generation" => nil, "units" => 7})
      ctx = reopen(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.g)
      assert {:ok, %{"status" => "cancelled"}} = fact(ctx, "effect", "effect_id", "e")
    end
  end

  test "transition: repeated close and late nonstart stays retired", ctx do
    prepare(ctx)
    issue(ctx)
    accept(ctx, %{"type" => "close_generation", "ledger_id" => "root", "generation" => 0})
    rejected(submit(ctx, %{"type" => "close_generation", "ledger_id" => "root", "generation" => 0}))
    accept(ctx, receipt("e", "late", "non_started", "issuer_quiescent"))
    ctx = reopen(ctx)
    assert %{mode: :ready} = Gateway.status(ctx.g)
    assert {:ok, %{"status" => "closed", "retired" => 20, "available" => 0}} = ledger(ctx)
  end

  test "transition: missing issue result facts cannot erase issuance", ctx do
    prepare(ctx)
    issue(ctx)
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", &Map.put(&1, "facts", %{}))
    ctx = start_again(ctx)
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  test "transition: duplicate identical fact carriers are harmless", ctx do
    prepare(ctx)
    issue(ctx)
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", fn r -> put_in(r, ["facts", "duplicate"], r["facts"]["effect"]) end)
    ctx = start_again(ctx)
    assert %{mode: :ready} = Gateway.status(ctx.g)
  end

  test "transition: conflicting duplicate fact carrier fences", ctx do
    prepare(ctx)
    issue(ctx)
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", fn r -> put_in(r, ["facts", "duplicate"], Map.put(r["facts"]["effect"], "status", "claimed")) end)
    ctx = start_again(ctx)
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  test "transition: unsupported effect revision gap fences even with matching result", ctx do
    prepare(ctx)
    issue(ctx)
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_effects", "state", "effect_id = 'e'", &Map.update!(&1, "revision", fn r -> r + 10 end))
    sql(ctx.path, "UPDATE root_effects SET revision = revision + 10 WHERE effect_id = 'e'")
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", &update_in(&1, ["facts", "effect", "revision"], fn r -> r + 10 end))
    ctx = start_again(ctx)
    IO.inspect(Gateway.status(ctx.g), label: "REVISION GAP")
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  test "transition: lost terminal-settlement reply retries once across restart", ctx do
    prepare(ctx)
    issue(ctx)
    op = receipt("e", "lost", "succeeded", "delivered")
    {:ok, %{"facts" => %{"required_revisions" => reads}}, :committed} = Gateway.protected_command(ctx.g, ctx.cap, "operator", req(op, %{}))
    request = req(op, reads)
    :ok = stop_supervised(Gateway)
    g = start_supervised!({Gateway, path: ctx.path, protected_capability: ctx.cap, writer_epoch: "epoch-A", fault: :after_commit_before_reply})
    assert {:error, {:storage_unavailable, :injected_after_commit_before_reply}} = Gateway.protected_command(g, ctx.cap, "operator", request)
    ctx = reopen(%{ctx | g: g})
    assert %{mode: :ready} = Gateway.status(ctx.g)
    assert {:ok, %{"disposition" => "accepted"}, :idempotent} = Gateway.protected_command(ctx.g, ctx.cap, "operator", request)
    assert {:ok, %{"consumed" => 1, "held" => 0, "available" => 19}} = ledger(ctx)
  end

  for reversed <- [false, true] do
    @reversed reversed
    test "transition: regressive duplicate snapshots fence in either nested order #{@reversed}", ctx do
      prepare(ctx)
      issue(ctx)
      :ok = stop_supervised(Gateway)
      mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", fn r ->
        current = r["facts"]["effect"]
        old = current |> Map.update!("revision", &(&1 - 1)) |> Map.put("status", "claimed")
        facts = if @reversed, do: [current, old], else: [old, current]
        put_in(r, ["facts", "duplicates"], facts)
      end)
      ctx = start_again(ctx)
      assert %{mode: :recovery} = Gateway.status(ctx.g)
    end
  end
end
"""
Code.eval_string(base <> extra, [], file: __ENV__.file)
