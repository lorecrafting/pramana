# Fresh typed-replay rereview; public fixtures, disposable SQLite corruption only.
base = File.read!("docs/fr-08/fr08a-final-review-probes.exs")
base = Regex.replace(~r/\nend\s*\z/, base, "\n")
extra = ~S"""
  for reverse <- [false, true], nesting <- [:direct, :list] do
    @reverse reverse
    @nesting nesting
    test "typed: conflicting known effect carriers #{@reverse}/#{@nesting} fence", ctx do
      prepare(ctx)
      issue(ctx)
      :ok = stop_supervised(Gateway)
      mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", fn r ->
        current = r["facts"]["effect"]
        old = current |> Map.update!("revision", &(&1 - 1)) |> Map.put("status", "claimed")
        values = if @reverse, do: [current, old], else: [old, current]
        values = if @nesting == :list, do: [values], else: values
        put_in(r, ["facts", "effect"], values)
      end)
      ctx = start_again(ctx)
      assert %{mode: :recovery} = Gateway.status(ctx.g)
    end
  end

  test "typed: superseded claim result cannot attest impossible issued status", ctx do
    prepare(ctx)
    issue(ctx)
    :ok = stop_supervised(Gateway)
    mutate_blob(ctx.path, "root_commands", "result", "operation = 'claim_effect' AND disposition = 'accepted'", fn r ->
      r |> put_in(["facts", "claim", "status"], "issued") |> put_in(["facts", "effect", "status"], "issued")
    end)
    ctx = start_again(ctx)
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  for placement <- [:diagnostic, :artifact, :receipt, :nested_list] do
    @placement placement
    test "typed: opaque #{@placement} maps stay opaque", ctx do
      prepare(ctx)
      issue(ctx)
      :ok = stop_supervised(Gateway)
      mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", fn r ->
        fake = r["facts"]["effect"] |> Map.put("revision", 999) |> Map.put("status", "diagnostic")
        {key, value} = case @placement do
          :diagnostic -> {"diagnostic", %{"details" => fake}}
          :artifact -> {"artifact", %{"content" => [fake]}}
          :receipt -> {"receipt", %{"payload" => fake}}
          :nested_list -> {"diagnostic", [[fake]]}
        end
        put_in(r, ["facts", key], value)
      end)
      ctx = start_again(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.g)
    end
  end

  for kind <- [:effect, :claim, :reservation, :ledger], delta <- [-1, 1] do
    @kind kind
    @delta delta
    test "typed: #{@kind} current revision delta #{@delta} fences", ctx do
      prepare(ctx)
      issue(ctx)
      :ok = stop_supervised(Gateway)
      {table, where} = case @kind do
        :effect -> {"root_effects", "effect_id = 'e'"}
        :claim -> {"root_claims", "claim_id = 'cl-e'"}
        :reservation -> {"root_reservations", "reservation_id = 'r-e'"}
        :ledger -> {"root_ledgers", "ledger_id = 'root'"}
      end
      mutate_blob(ctx.path, table, "state", where, &Map.update!(&1, "revision", fn r -> r + @delta end))
      sql(ctx.path, "UPDATE #{table} SET revision = revision + (#{@delta}) WHERE #{where}")
      ctx = start_again(ctx)
      assert %{mode: :recovery} = Gateway.status(ctx.g)
    end
  end

  for variation <- [:missing_revision, :nested_map, :identical_duplicates] do
    @variation variation
    test "typed: carrier schema #{@variation}", ctx do
      prepare(ctx)
      issue(ctx)
      :ok = stop_supervised(Gateway)
      mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", fn r ->
        current = r["facts"]["effect"]
        value = case @variation do
          :missing_revision -> Map.delete(current, "revision")
          :nested_map -> %{"payload" => current}
          :identical_duplicates -> [current, current]
        end
        put_in(r, ["facts", "effect"], value)
      end)
      ctx = start_again(ctx)
      expected = if @variation == :identical_duplicates, do: :ready, else: :recovery
      assert %{mode: ^expected} = Gateway.status(ctx.g)
    end
  end

  test "typed: reordered claim and issue commands fence", ctx do
    prepare(ctx)
    issue(ctx)
    :ok = stop_supervised(Gateway)
    sql(ctx.path, "UPDATE root_commands SET seq = -seq WHERE operation IN ('claim_effect', 'issue_claim') AND disposition = 'accepted'")
    ctx = start_again(ctx)
    assert %{mode: :recovery} = Gateway.status(ctx.g)
  end

  for placement <- [:deep, :list, :root] do
    @placement placement
    test "typed: public receipt payload #{@placement} restarts", ctx do
      prepare(ctx)
      issue(ctx)
      fake = %{"effect_id" => "e", "claim_id" => "cl-e", "ledger_id" => "root", "generation" => 0, "authorized" => 999, "revision" => 999, "status" => "diagnostic"}
      payload = case @placement do
        :deep -> %{"artifact" => %{"diagnostic" => fake}}
        :list -> %{"artifact" => [[fake], %{"inner" => fake}]}
        :root -> fake
      end
      accept(ctx, Map.put(receipt("e", "receipt-opaque", "succeeded", "delivered"), "payload", payload))
      ctx = reopen(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.g)
    end
  end
end
"""
Code.eval_string(base <> extra, [], file: __ENV__.file)
