ExUnit.start(seed: 9293)

defmodule FR08ARereview do
  use ExUnit.Case, async: false
  alias PramanaFoundry.DurableStore.{Gateway, Encoding}
  alias Exqlite.Sqlite3

  setup do
    path = Path.join(System.tmp_dir!(), "hostile-#{System.pid()}-#{uid()}.sqlite3")
    :ok = Gateway.initialize(path)
    # Without this every run left its store behind, and once an OS pid was reused the next
    # run collided with it (:already_initialized). 63,709 had accumulated by 2026-09-23.
    on_exit(fn -> Enum.each(Path.wildcard(path <> "*"), &File.rm_rf/1) end)
    cap = make_ref()

    g =
      start_supervised!({Gateway, path: path, protected_capability: cap, writer_epoch: "epoch-A"})

    ctx = %{g: g, cap: cap, path: path}
    accept(ctx, policy())

    accept(ctx, %{
      "type" => "set_control",
      "control_id" => "c",
      "value" => %{"status" => "active"}
    })

    accept(ctx, grant("root", "starts.developer", 20))
    ctx
  end

  defp uid, do: "c#{System.unique_integer([:positive, :monotonic])}"

  defp policy,
    do: %{
      "type" => "set_policy",
      "policy_id" => "p",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:T"],
        "allowed_roles" => ["developer"],
        "allowed_profiles" => ["sol"],
        "launch_non_start_limit" => 1
      }
    }

  defp grant(id, dimension, units),
    do: %{
      "type" => "grant_ledger",
      "ledger_id" => id,
      "generation" => 0,
      "dimension" => dimension,
      "units" => units
    }

  defp req(op, reads),
    do: %{
      "schema_version" => 1,
      "command_id" => uid(),
      "operation" => op,
      "expected_revisions" => reads
    }

  defp submit(ctx, op) do
    first = req(op, %{})

    case Gateway.protected_command(ctx.g, ctx.cap, "operator", first) do
      {:ok,
       %{"reason_code" => "incomplete_read_set", "facts" => %{"required_revisions" => reads}},
       :committed} ->
        Gateway.protected_command(ctx.g, ctx.cap, "operator", req(op, reads))

      result ->
        result
    end
  end

  defp accept(ctx, op) do
    assert {:ok, %{"disposition" => "accepted"} = result, :committed} = submit(ctx, op)
    result
  end

  defp fact(ctx, type, key, id),
    do:
      Gateway.protected_query(ctx.g, ctx.cap, %{"schema_version" => 1, "type" => type, key => id})

  defp ledger(ctx, id \\ "root", gen \\ 0),
    do:
      Gateway.protected_query(ctx.g, ctx.cap, %{
        "schema_version" => 1,
        "type" => "ledger",
        "ledger_id" => id,
        "generation" => gen
      })

  defp reserve(ctx, id, effect, units \\ 1, ledger \\ "root") do
    accept(ctx, %{
      "type" => "reserve",
      "reservation_id" => id,
      "ledger_id" => ledger,
      "generation" => 0,
      "units" => units,
      "owner_kind" => "effect",
      "owner_id" => effect
    })
  end

  defp effect(id) do
    %{
      "type" => "create_effect",
      "effect_id" => id,
      "request" => %{"request_id" => "req-" <> id, "role" => "developer", "profile" => "sol"},
      "operation" => "launch",
      "scope" => "ticket:T",
      "ticket_id" => "T",
      "attempt_id" => "A",
      "execution_id" => "x-" <> id,
      "policy_id" => "p",
      "policy_revision" => 0,
      "control_id" => "c",
      "control_revision" => 0,
      "reservation_ids" => ["r-" <> id],
      "leases" => []
    }
  end

  defp prepare(ctx, id \\ "e", change \\ & &1) do
    reserve(ctx, "r-" <> id, id)
    accept(ctx, change.(effect(id)))
  end

  defp issue(ctx, id \\ "e") do
    accept(ctx, %{
      "type" => "claim_effect",
      "effect_id" => id,
      "claim_id" => "cl-" <> id,
      "writer_epoch" => "epoch-A"
    })

    accept(ctx, %{"type" => "issue_claim", "claim_id" => "cl-" <> id, "writer_epoch" => "epoch-A"})
  end

  defp receipt(id, receipt, outcome, proof),
    do: %{
      "type" => "settle_claim",
      "claim_id" => "cl-" <> id,
      "receipt_id" => receipt,
      "request_id" => "req-" <> id,
      "outcome" => outcome,
      "proof" => proof,
      "payload" => %{"quiescence_epoch" => "epoch-A"}
    }

  defp reopen(ctx) do
    :ok = stop_supervised(Gateway)

    %{
      ctx
      | g:
          start_supervised!(
            {Gateway, path: ctx.path, protected_capability: ctx.cap, writer_epoch: "epoch-A"}
          )
    }
  end

  defp sql(path, statements) do
    {:ok, conn} = Sqlite3.open(path)

    try do
      :ok = Sqlite3.execute(conn, statements)
    after
      :ok = Sqlite3.close(conn)
    end
  end

  defp rejected(result),
    do: assert(match?({:ok, %{"disposition" => "rejected"}, :committed}, result))

  test "changing phase generation cannot duplicate an outstanding owner launch", ctx do
    prepare(ctx)
    issue(ctx)
    reserve(ctx, "r-e2", "e2")
    result = submit(ctx, put_in(effect("e2"), ["request", "phase_generation"], 99))
    IO.inspect(result, label: "phase-generation bypass")
    rejected(result)
  end

  test "terminal non-start cannot reset ordinal and finite infrastructure limit", ctx do
    prepare(ctx)
    issue(ctx)
    accept(ctx, receipt("e", "nonstart", "non_started", "issuer_quiescent"))
    reserve(ctx, "r-e2", "e2")
    result = submit(ctx, effect("e2"))
    IO.inspect(result, label: "ordinal zero reused after non-start limit")
    rejected(result)
  end

  test "unapproved profile and expired deadline cannot issue", ctx do
    reserve(ctx, "r-e", "e")

    op =
      put_in(effect("e")["request"], %{
        "request_id" => "req-e",
        "role" => "developer",
        "profile" => "unapproved",
        "deadline" => 1
      })

    admission = submit(ctx, op)
    result = maybe_issue(ctx, "e", admission)
    IO.inspect(result, label: "unapproved profile and expired deadline")
    rejected(result)
  end

  test "invalid control rejection cannot mutate the control or break reopening", ctx do
    {:ok, before} = fact(ctx, "control", "control_id", "c")

    result =
      submit(ctx, %{
        "type" => "set_control",
        "control_id" => "c",
        "value" => %{"status" => "bogus"}
      })

    rejected(result)
    after_value = fact(ctx, "control", "control_id", "c")
    reopened = reopen(ctx)

    IO.inspect({result, after_value, Gateway.status(reopened.g)},
      label: "rejected control mutation"
    )

    assert after_value == {:ok, before}
    assert %{mode: :ready} = Gateway.status(reopened.g)
  end

  test "overcommitted proposal admission rejection is atomic", ctx do
    reserve(ctx, "r1", "e", 12)
    reserve(ctx, "r2", "e", 12)
    result = submit(ctx, %{effect("e") | "reservation_ids" => ["r1", "r2"]})
    rejected(result)

    observed =
      {ledger(ctx), fact(ctx, "effect", "effect_id", "e"),
       fact(ctx, "reservation", "reservation_id", "r1")}

    reopened = reopen(ctx)

    IO.inspect({result, observed, Gateway.status(reopened.g)},
      label: "partial rejected admission"
    )

    assert {:ok, %{"held" => 0, "available" => 20}} = elem(observed, 0)
    assert {:error, :not_found} = elem(observed, 1)
    assert %{mode: :ready} = Gateway.status(reopened.g)
  end

  test "same observation ID changing unknown to terminal quarantines without storage fence",
       ctx do
    prepare(ctx)
    issue(ctx)
    accept(ctx, receipt("e", "observation", "unknown", "outcome_unknown"))
    result = submit(ctx, receipt("e", "observation", "succeeded", "delivered"))
    IO.inspect({result, Gateway.status(ctx.g)}, label: "same observation conflict")
    assert %{mode: :ready} = Gateway.status(ctx.g)
    rejected(result)
  end

  test "cross-claim observation identity conflict quarantines without storage fence", ctx do
    prepare(ctx)
    issue(ctx)
    accept(ctx, receipt("e", "observation", "succeeded", "delivered"))
    prepare(ctx, "e2", &Map.put(&1, "attempt_id", "A2"))
    issue(ctx, "e2")
    result = submit(ctx, receipt("e2", "observation", "succeeded", "delivered"))
    IO.inspect({result, Gateway.status(ctx.g)}, label: "cross-claim observation conflict")
    assert %{mode: :ready} = Gateway.status(ctx.g)
    rejected(result)
  end

  test "recovery binds ledger amounts to authenticated grants", ctx do
    {:ok, l} = ledger(ctx)
    :ok = stop_supervised(Gateway)

    {:ok, bytes} =
      Encoding.json(Map.drop(%{l | "authorized" => 2000, "available" => 2000}, ["reservations"]))

    sql(
      ctx.path,
      "UPDATE root_ledgers SET authorized = 2000, available = 2000, state = X'#{Base.encode16(bytes)}' WHERE ledger_id = 'root'"
    )

    g =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.cap, writer_epoch: "epoch-A"}
      )

    IO.inspect({Gateway.status(g), ledger(%{ctx | g: g})}, label: "forged conserved grant")
    assert %{mode: :recovery} = Gateway.status(g)
  end

  test "recovery binds effect issuer to original admission", ctx do
    prepare(ctx)
    {:ok, e} = fact(ctx, "effect", "effect_id", "e")
    :ok = stop_supervised(Gateway)
    # The public effect includes attached reservations and claims; use the exact persisted
    # state as the negative corruption carrier, after cleanly stopping the public owner.
    {:ok, conn} = Sqlite3.open(ctx.path)
    {:ok, stmt} = Sqlite3.prepare(conn, "SELECT state FROM root_effects WHERE effect_id = 'e'")
    {:row, [state]} = Sqlite3.step(conn, stmt)
    :ok = Sqlite3.release(conn, stmt)
    :ok = Sqlite3.close(conn)
    decoded = :json.decode(state) |> normalize_json()
    {:ok, bytes} = Encoding.json(%{decoded | "issuer" => "impostor"})

    sql(
      ctx.path,
      "UPDATE root_effects SET state = X'#{Base.encode16(bytes)}' WHERE effect_id = 'e'"
    )

    g =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.cap, writer_epoch: "epoch-A"}
      )

    IO.inspect({e["issuer"], Gateway.status(g), fact(%{ctx | g: g}, "effect", "effect_id", "e")},
      label: "forged issuer recovery"
    )

    assert %{mode: :recovery} = Gateway.status(g)
  end

  defp normalize_json(:null), do: nil
  defp normalize_json(x) when is_map(x), do: Map.new(x, fn {k, v} -> {k, normalize_json(v)} end)
  defp normalize_json(x) when is_list(x), do: Enum.map(x, &normalize_json/1)
  defp normalize_json(x), do: x

  test "a closed child cannot prevent closing its still-open parent", ctx do
    accept(ctx, %{
      "type" => "delegate_allocation",
      "parent_ledger_id" => "root",
      "parent_generation" => 0,
      "child_ledger_id" => "child",
      "child_generation" => 0,
      "dimension" => "starts.developer",
      "units" => 4
    })

    accept(ctx, %{"type" => "close_generation", "ledger_id" => "child", "generation" => 0})

    result =
      submit(ctx, %{"type" => "close_generation", "ledger_id" => "root", "generation" => 0})

    IO.inspect({result, ledger(ctx)}, label: "closed child blocks parent close")
    assert {:ok, %{"disposition" => "accepted"}, :committed} = result
    assert {:ok, %{"status" => "closed"}} = ledger(ctx)
  end

  test "late conflicting terminal observation prevents owner successor issue", ctx do
    accept(
      ctx,
      policy() |> Map.put("policy_id", "p2") |> put_in(["value", "launch_non_start_limit"], 3)
    )

    prepare(ctx, "e", &Map.put(&1, "policy_id", "p2"))
    issue(ctx)
    accept(ctx, receipt("e", "nonstart", "non_started", "issuer_quiescent"))

    prepare(ctx, "e2", fn op ->
      op
      |> Map.put("policy_id", "p2")
      |> put_in(["request"], %{
        "request_id" => "req-e2",
        "role" => "developer",
        "profile" => "sol",
        "operation_ordinal" => 1,
        "predecessor_effect_id" => "e"
      })
    end)

    rejected(submit(ctx, receipt("e", "late-start", "succeeded", "delivered")))
    result = maybe_issue(ctx, "e2", {:ok, %{"disposition" => "accepted"}, :committed})
    IO.inspect(result, label: "successor after predecessor quarantine")
    rejected(result)
  end

  defp maybe_issue(ctx, id, {:ok, %{"disposition" => "accepted"}, :committed}) do
    case submit(ctx, %{
           "type" => "claim_effect",
           "effect_id" => id,
           "claim_id" => "cl-" <> id,
           "writer_epoch" => "epoch-A"
         }) do
      {:ok, %{"disposition" => "accepted"}, :committed} ->
        submit(ctx, %{
          "type" => "issue_claim",
          "claim_id" => "cl-" <> id,
          "writer_epoch" => "epoch-A"
        })

      result ->
        result
    end
  end

  defp maybe_issue(_ctx, _id, result), do: result

  test "admission enforces ticket identity scope before acknowledging", ctx do
    reserve(ctx, "r-e", "e")
    result = submit(ctx, %{effect("e") | "ticket_id" => "other-ticket"})
    ctx = reopen(ctx)
    IO.inspect({result, Gateway.status(ctx.g)}, label: "mismatched scope admitted then recovery")
    rejected(result)
    assert %{mode: :ready} = Gateway.status(ctx.g)
  end

  test "old wrong dimension probe now rejects durably without hold", ctx do
    accept(ctx, grant("validation", "validations", 1))
    reserve(ctx, "r-e", "e", 1, "validation")
    {:ok, result, :committed} = submit(ctx, effect("e"))
    assert result["reason_code"] == "operation_dimension_mismatch"
    ctx = reopen(ctx)
    assert {:ok, ^result} = fact(ctx, "command", "command_id", result["command_id"])
    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "e")
    assert {:ok, %{"available" => 1, "held" => 0}} = ledger(ctx, "validation")
    assert %{mode: :ready} = Gateway.status(ctx.g)
  end

  test "old closed return probe now rejects durably preserving conservation", ctx do
    accept(ctx, %{
      "type" => "delegate_allocation",
      "parent_ledger_id" => "root",
      "parent_generation" => 0,
      "child_ledger_id" => "child",
      "child_generation" => 0,
      "dimension" => "starts.developer",
      "units" => 4
    })

    accept(ctx, %{"type" => "close_generation", "ledger_id" => "root", "generation" => 0})

    {:ok, result, :committed} =
      submit(ctx, %{
        "type" => "return_allocation",
        "child_ledger_id" => "child",
        "child_generation" => 0,
        "units" => 1
      })

    assert result["reason_code"] == "allocation_return_not_permitted"
    ctx = reopen(ctx)
    assert {:ok, ^result} = fact(ctx, "command", "command_id", result["command_id"])
    assert {:ok, %{"available" => 0, "retired" => 16, "delegated" => 4}} = ledger(ctx)
    assert {:ok, %{"available" => 0, "retired" => 4, "status" => "closed"}} = ledger(ctx, "child")
  end

  test "old duplicate early rejection and distinct-owner lease collision stay durable", ctx do
    lease = fn id -> [%{"lease_id" => id, "resource_id" => "slot"}] end
    prepare(ctx, "e", &Map.put(&1, "leases", lease.("l1")))
    reserve(ctx, "r-e2", "e2")
    {:ok, result, :committed} = submit(ctx, %{effect("e2") | "leases" => lease.("l2")})
    assert result["reason_code"] == "duplicate_semantic_operation"
    # A distinct legitimate owner reaches the lease guard, so the earlier duplicate
    # rejection does not hide required resource-conflict behavior.
    accept(ctx, %{effect("e2") | "attempt_id" => "A2", "leases" => lease.("l2")})
    issue(ctx)

    {:ok, conflict, :committed} =
      submit(ctx, %{
        "type" => "claim_effect",
        "effect_id" => "e2",
        "claim_id" => "cl-e2",
        "writer_epoch" => "epoch-A"
      })

    assert conflict["reason_code"] == "lease_conflict"
    ctx = reopen(ctx)
    assert {:ok, ^result} = fact(ctx, "command", "command_id", result["command_id"])
    assert {:ok, ^conflict} = fact(ctx, "command", "command_id", conflict["command_id"])
    assert {:error, :not_found} = fact(ctx, "claim", "claim_id", "cl-e2")
    assert {:ok, %{"held" => 2, "available" => 18}} = ledger(ctx)
    assert %{mode: :ready} = Gateway.status(ctx.g)
  end
end
