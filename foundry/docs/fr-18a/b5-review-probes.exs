# Independent FR-18A review of 6812e5e; only disposable fixture stores are mutated.
# MIX_ENV=test mix run --no-start docs/fr-18a/b5-review-probes.exs
ExUnit.start(seed: 18055)

defmodule FR18AReviewTap do
  alias PramanaFoundry.Observations.GatewaySource
  def snapshot(state), do: GatewaySource.snapshot(state)
  def fact(state, query) do
    result = GatewaySource.fact(state, query)
    if match?({:ok, _, _}, result) do
      {:ok, fact, _} = result
      send(self(), {:materialized, query["type"], :erlang.external_size(fact), length(Map.get(fact, "items", []))})
    end
    result
  end
end

defmodule FR18AReviewChangedSource do
  alias PramanaFoundry.Observations.GatewaySource
  def snapshot(state), do: GatewaySource.snapshot(state)
  def fact(state, %{"type" => "effect_observation_page"} = query) do
    with {:ok, fact, at} <- GatewaySource.fact(state, query) do
      {:ok, state.change.(fact), at}
    end
  end
  def fact(state, query), do: GatewaySource.fact(state, query)
end

base = File.read!("test/pramana_foundry/durable_store/atomic_bundle_test.exs")
base = String.replace(base, "PramanaFoundry.DurableStore.AtomicBundleTest", "PramanaFoundry.FR18AB5Review")
base = Regex.replace(~r/\nend\s*\z/, base, "\n")
extra = ~S"""
  alias PramanaFoundry.Observations
  alias PramanaFoundry.Observations.Query

  defp observation_request(limit \\ 20, bytes \\ 65_536) do
    %{"schema_version" => 1, "type" => "effect_observation_page", "effect_id" => "effect-1", "limit" => limit, "max_bytes" => bytes, "cursor" => nil}
  end

  test "review: public page still materializes control and inbox payloads beyond its cap", ctx do
    seed_issued_launch!(ctx)
    payload = String.duplicate("x", 262_144)
    accept_current!(ctx, %{"type" => "set_control", "control_id" => "control-1", "value" => %{"status" => "active", "diagnostic" => payload}})
    for sequence <- 1..8 do
      accept_current!(ctx, %{"type" => "append_inbox", "execution_id" => "execution-1", "sequence" => sequence, "item_kind" => "observation", "payload" => %{"diagnostic" => payload}})
    end
    query = %Query{effect_ids: ["effect-1"], include_pointers: false, max_bytes: 8_192, limit: 1}
    page = Observations.query_source(query, {FR18AReviewTap, ctx})
    assert page.status == :ok
    assert page.size_bytes <= query.max_bytes
    assert_received {:materialized, "control", control_bytes, 0}
    assert_received {:materialized, "inbox", inbox_bytes, 8}
    assert control_bytes > 262_144
    assert inbox_bytes > 2_097_152
    IO.puts("REPRODUCED: 8 KiB public cap materializes control >256 KiB and 8 inbox rows >2 MiB")
  end

  test "review: valid nonstart conflict is mislabeled corrupt", ctx do
    seed_issued_launch!(ctx)
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", nonstart_bundle("review-nonstart"))
    conflict = nonstart_bundle("review-conflict")
      |> put_in(["operations", Access.at(0), "expected_revisions"], %{"claim/claim-1" => 2, "effect/effect-1" => 3, "policy/policy-1" => 0, "control/control-1" => 0, "reservation/reservation-1" => 4, "ledger/ledger-1/0" => 2, "receipt/receipt-2" => "absent"})
      |> put_in(["operations", Access.at(0), "operation", "receipt_id"], "receipt-2")
      |> put_in(["operations", Access.at(0), "operation", "outcome"], "failed")
      |> put_in(["operations", Access.at(0), "operation", "proof"], "delivered")
    assert {:ok, %{"disposition" => "quarantined"}, :quarantined} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", conflict)
    assert {:ok, %{"status" => "reconciliation_required"}} = fact(ctx, "effect", "effect_id", "effect-1")
    assert {:ok, _} = Gateway.backup(ctx.gateway, ctx.path <> ".backup")
    page = Observations.query(%Query{effect_ids: ["effect-1"], include_pointers: false}, ctx.gateway, ctx.capability)
    assert page.status == :corrupt
    assert page.error_code == :source_corrupt
    IO.puts("REPRODUCED: verified-backup-valid nonstart conflict becomes source_corrupt")
  end

  for {column, value} <- [{"role", "pm"}, {"work_owner", "wrong-owner"}, {"infrastructure_generation", 9}, {"predecessor_effect_id", "wrong-predecessor"}, {"failure_class", "wrong-failure"}, {"ordinal", 900}] do
    @review_column column
    @review_value value
    test "review: bounded settlement accepts mismatched #{column}", ctx do
      seed_issued_launch!(ctx)
      assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", nonstart_bundle("review-field"))
      assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readwrite)
      assert :ok = Database.execute(raw, "UPDATE root_infrastructure_settlements SET " <> @review_column <> " = ? WHERE effect_id = ?", [@review_value, "effect-1"])
      assert :ok = Sqlite3.close(raw)
      page = Observations.query(%Query{effect_ids: ["effect-1"], include_pointers: false}, ctx.gateway, ctx.capability)
      assert page.status == :ok
      assert page.quality == :canonical
      assert hd(page.items).fact["infrastructure_settlement"][@review_column] == @review_value
      IO.puts("REPRODUCED: canonical settlement accepts mismatched " <> @review_column)
    end
  end

  test "review: exact requests and cursor malformations refuse; supported pages are deterministic", ctx do
    seed_issued_launch!(ctx)
    request = observation_request(1)
    assert {:error, :unauthorized_protected_operation} = Gateway.protected_query(ctx.gateway, make_ref(), request)
    for malformed <- [Map.put(request, "sql", "SELECT 1"), Map.delete(request, "cursor"), Map.put(request, "effect_id", ""), Map.put(request, "effect_id", String.duplicate("e", 257)), Map.put(request, "limit", 51), Map.put(request, "max_bytes", 262_145)] do
      assert {:error, :invalid_protected_query} = Gateway.protected_query(ctx.gateway, ctx.capability, malformed)
    end
    assert {:ok, first} = Gateway.protected_query(ctx.gateway, ctx.capability, request)
    cursor = first["page"]["next_cursor"]
    for malformed <- [Map.put(cursor, "extra", 1), Map.delete(cursor, "offset"), Map.put(cursor, "schema_version", 2), Map.put(cursor, "offset", -1), Map.put(cursor, "offset", 1_000_001), Map.put(cursor, "offset", "0"), Map.put(cursor, "section", "effects"), Map.put(cursor, "effect_revision", nil)] do
      assert {:error, :invalid_protected_query} = Gateway.protected_query(ctx.gateway, ctx.capability, %{request | "cursor" => malformed})
    end
    assert {:ok, second} = Gateway.protected_query(ctx.gateway, ctx.capability, %{request | "cursor" => cursor})
    assert Enum.map(first["relations"] ++ second["relations"], & &1["kind"]) == ["claim", "reservation"]
    assert second["page"]["next_cursor"] == nil
    assert {:ok, all} = Gateway.protected_query(ctx.gateway, ctx.capability, observation_request())
    assert all["relations"] == first["relations"] ++ second["relations"]
  end

  test "review: bounded response source and nested versions are not validated", ctx do
    seed_issued_launch!(ctx)
    changes = [
      {"missing source", &Map.delete(&1, "source")},
      {"cross-repository source", &put_in(&1, ["source", "repository_id"], "another-repository")},
      {"wrong frontier", &put_in(&1, ["source", "last_protected_command_sequence"], 999_999)},
      {"wrong effect revision", &put_in(&1, ["source", "effect_revision"], 999_999)},
      {"effect schema version", &put_in(&1, ["effect", "schema_version"], 999)},
      {"relation schema version", &put_in(&1, ["relations", Access.at(0), "schema_version"], 999)}
    ]
    for {label, change} <- changes do
      page = Observations.query_source(%Query{effect_ids: ["effect-1"], include_pointers: false}, {FR18AReviewChangedSource, Map.put(ctx, :change, change)})
      assert page.status == :ok
      assert page.quality == :canonical
      IO.puts("REPRODUCED: canonical page ignores " <> label)
    end
  end

  test "review: relation boundary plus one has no overlap or gap", ctx do
    seed_issued_launch!(ctx)
    accept_current!(ctx, %{"type" => "grant_ledger", "ledger_id" => "review-ledger", "generation" => 0, "dimension" => "starts.developer", "units" => 100})
    for n <- 1..51 do
      accept_current!(ctx, %{"type" => "reserve", "reservation_id" => "review-reservation-#{String.pad_leading(Integer.to_string(n), 2, "0")}", "ledger_id" => "review-ledger", "generation" => 0, "owner_kind" => "effect", "owner_id" => "effect-1", "units" => 1})
    end
    request = observation_request(50)
    assert {:ok, first} = Gateway.protected_query(ctx.gateway, ctx.capability, request)
    assert first["page"]["item_count"] == 50
    assert first["page"]["truncated_reason"] == "item_limit"
    assert {:ok, second} = Gateway.protected_query(ctx.gateway, ctx.capability, %{request | "cursor" => first["page"]["next_cursor"]})
    assert second["page"]["item_count"] == 3
    assert second["page"]["next_cursor"] == nil
    ids = Enum.map(first["relations"] ++ second["relations"], fn row -> if row["kind"] == "claim", do: row["claim_id"], else: row["reservation_id"] end)
    assert length(Enum.uniq(ids)) == 53
    assert Enum.sort(tl(ids)) == tl(ids)
  end

  test "review: byte limits and singleton accounting stay within the requested cap", ctx do
    seed_issued_launch!(ctx)
    assert {:ok, _, :committed} = Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", nonstart_bundle("review-byte-budget"))
    observations = for cap <- 1_024..8_192//64 do
      case Gateway.protected_query(ctx.gateway, ctx.capability, observation_request(50, cap)) do
        {:ok, page} ->
          assert page["infrastructure_settlement"]["ordinal"] == 1
          assert page["page"]["size_bytes"] == :erlang.external_size(page)
          assert :erlang.external_size(page) <= cap
          page["page"]["truncated_reason"]
        {:error, :protected_observation_oversized} -> :oversized
      end
    end
    assert :oversized in observations
    assert "byte_limit" in observations
    assert nil in observations
  end
end
"""
Code.compile_string(base <> extra, "fr18a_b5_review_generated.exs")
