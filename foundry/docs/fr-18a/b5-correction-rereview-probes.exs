# FR-18A B5a-B5d correction rereview probes.
#
# Independent of the implementation. Unlike the original b5-review-probes.exs, these
# assert the REQUIRED behavior of the corrected candidate plus healthy-store controls
# that the original review did not exercise. A green run is rereview evidence for the
# exact revision named in b5-correction-rereview.md; it is not FR-18A acceptance.
#
#   mix run docs/fr-18a/b5-correction-rereview-probes.exs

ExUnit.start(seed: 20926)

base = File.read!("test/pramana_foundry/durable_store/atomic_bundle_test.exs")

base =
  String.replace(
    base,
    "PramanaFoundry.DurableStore.AtomicBundleTest",
    "PramanaFoundry.FR18AB5CorrectionRereview"
  )

base = Regex.replace(~r/\nend\s*\z/, base, "\n")

extra = ~S"""
  alias PramanaFoundry.Observations
  alias PramanaFoundry.Observations.Query

  defp rr_raw!(ctx, statements) do
    assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readwrite)
    for {sql, args} <- statements, do: assert(:ok = Database.execute(raw, sql, args))
    assert :ok = Sqlite3.close(raw)
  end

  defp rr_page(ctx) do
    Observations.query(
      %Query{effect_ids: ["effect-1"], include_pointers: false},
      ctx.gateway,
      ctx.capability
    )
  end

  defp rr_conflict(name, receipt_id, outcome, proof) do
    nonstart_bundle(name)
    |> put_in(["operations", Access.at(0), "expected_revisions"], %{
      "claim/claim-1" => 2,
      "effect/effect-1" => 3,
      "policy/policy-1" => 0,
      "control/control-1" => 0,
      "reservation/reservation-1" => 4,
      "ledger/ledger-1/0" => 2,
      "receipt/" <> receipt_id => "absent"
    })
    |> put_in(["operations", Access.at(0), "operation", "receipt_id"], receipt_id)
    |> put_in(["operations", Access.at(0), "operation", "outcome"], outcome)
    |> put_in(["operations", Access.at(0), "operation", "proof"], proof)
  end

  # --- B5b: the accepted conflict lifecycle, beyond the single reviewed case -------

  for {label, outcome, proof} <- [
        {"failed", "failed", "delivered"},
        {"succeeded", "succeeded", "delivered"}
      ] do
    @rr_label label
    @rr_outcome outcome
    @rr_proof proof

    test "rereview b5b: quarantined #{label} conflict stays observable", ctx do
      seed_issued_launch!(ctx)

      assert {:ok, _, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_bundle("rr-nonstart")
               )

      assert {:ok, %{"disposition" => "quarantined"}, :quarantined} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 rr_conflict("rr-conflict", "receipt-2", @rr_outcome, @rr_proof)
               )

      assert {:ok, %{"status" => "reconciliation_required"}} =
               fact(ctx, "effect", "effect_id", "effect-1")

      assert {:ok, _} = Gateway.backup(ctx.gateway, ctx.path <> ".backup")

      page = rr_page(ctx)
      assert page.status == :ok
      assert page.quality == :canonical
      assert hd(page.items).fact["infrastructure_settlement"]["ordinal"] == 1
    end
  end

  test "rereview b5b: a second conflict is refused and the page stays canonical", ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("rr-nonstart")
             )

    assert {:ok, %{"disposition" => "quarantined"}, :quarantined} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               rr_conflict("rr-c1", "receipt-2", "failed", "delivered")
             )

    assert {:ok, %{"disposition" => "rejected"}, _} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               rr_conflict("rr-c2", "receipt-3", "failed", "delivered")
             )

    page = rr_page(ctx)
    assert page.status == :ok
    assert page.quality == :canonical
  end

  test "rereview b5b: a duplicate non-start never reaches reconciliation", ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("rr-nonstart")
             )

    assert {:ok, %{"disposition" => "rejected"}, _} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               rr_conflict("rr-dup", "receipt-2", "non_started", "proved")
             )

    assert {:ok, %{"status" => "non_started"}} = fact(ctx, "effect", "effect_id", "effect-1")

    page = rr_page(ctx)
    assert page.status == :ok
    assert page.quality == :canonical
  end

  # --- B5c: the binding is three-way, not settlement-row-local --------------------

  test "rereview b5c: a diverging authoritative effect scalar is corruption", ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("rr-auth")
             )

    rr_raw!(ctx, [
      {"UPDATE root_effects SET state = CAST(json_set(CAST(state AS TEXT), '$.role', 'pm') AS BLOB) WHERE effect_id = ?",
       ["effect-1"]}
    ])

    page = rr_page(ctx)
    assert page.status == :corrupt
    assert page.quality == :corrupt
    assert page.error_code == :source_corrupt
  end

  test "rereview b5c: a coherent settlement/effect pair still fails the operation record",
       ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("rr-coherent")
             )

    rr_raw!(ctx, [
      {"UPDATE root_infrastructure_settlements SET role = 'pm' WHERE effect_id = ?", ["effect-1"]},
      {"UPDATE root_effects SET state = CAST(json_set(CAST(state AS TEXT), '$.role', 'pm') AS BLOB) WHERE effect_id = ?",
       ["effect-1"]}
    ])

    page = rr_page(ctx)
    assert page.status == :corrupt
    assert page.quality == :corrupt
    assert page.error_code == :source_corrupt
  end

  # --- B5a: healthy control states are observable and never materialized ----------

  test "rereview b5a: a cancel_requested control stays canonical and bounded", ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("rr-cancel")
             )

    accept_current!(ctx, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "cancel_requested"}
    })

    page = rr_page(ctx)
    item = hd(page.items)

    assert page.status == :ok
    assert page.quality == :canonical
    assert item.fact["control"]["status"] == "cancel_requested"
    assert item.fact["execution"]["status"] == "absent"
  end

  test "rereview b5a: the closed control vocabulary is enforced at the write boundary",
       ctx do
    seed_issued_launch!(ctx)

    operation = %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"note" => "operator annotation"}
    }

    assert {:ok, first, :committed} =
             Gateway.protected_command(
               ctx.gateway,
               ctx.capability,
               "operator",
               root_command(unique_id(), %{}, operation)
             )

    reads =
      if first["reason_code"] == "incomplete_read_set",
        do: first["facts"]["required_revisions"],
        else: %{}

    assert {:ok, %{"reason_code" => "invalid_control_state"}, :committed} =
             Gateway.protected_command(
               ctx.gateway,
               ctx.capability,
               "operator",
               root_command(unique_id(), reads, operation)
             )
  end

  test "rereview b5a: unrelated control keys do not disturb canonical quality", ctx do
    seed_issued_launch!(ctx)

    accept_current!(ctx, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active", "note" => "ok"}
    })

    page = rr_page(ctx)
    assert page.status == :ok
    assert page.quality == :canonical
  end
end
"""

Code.compile_string(base <> extra, "fr18a_b5_correction_rereview_generated.exs")
