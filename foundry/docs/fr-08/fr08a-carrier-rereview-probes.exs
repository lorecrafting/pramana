# Independent bounded T3 rereview. Reuse public setup and the 22 baseline controls.
base = File.read!("docs/fr-08/fr08a-final-review-probes.exs")
base = Regex.replace(~r/\nend\s*\z/, base, "\n")
extra = ~S"""
  for {operation, key} <- [{"reserve", "ledger"}, {"reserve", "reservation"}, {"issue_claim", "claim"}, {"issue_claim", "effect"}],
      shape <- [:direct, :absent, :null, :empty, :single, :nested, :duplicate, :scalar, :wrapped, :missing_schema, :missing_revision, :extra, :wrong_schema] do
    @carrier_operation operation
    @carrier_key key
    @carrier_shape shape
    test "fresh singular #{@carrier_operation}/#{@carrier_key}/#{@carrier_shape}", ctx do
      prepare(ctx)
      issue(ctx)
      :ok = stop_supervised(Gateway)
      # Remove superseded carriers for absence controls; current snapshots must
      # still be attested by the later issue command.
      operation = if @carrier_shape == :absent and @carrier_operation == "issue_claim", do: "claim_effect", else: @carrier_operation
      mutate_blob(ctx.path, "root_commands", "result", "operation = '#{operation}' AND disposition = 'accepted'", fn r ->
        current = r["facts"][@carrier_key]
        value = case @carrier_shape do
          :direct -> current
          :absent -> current
          :null -> nil
          :empty -> []
          :single -> [current]
          :nested -> [[current]]
          :duplicate -> [current, current]
          :scalar -> 1
          :wrapped -> %{"payload" => current}
          :missing_schema -> Map.delete(current, "schema_version")
          :missing_revision -> Map.delete(current, "revision")
          :extra -> Map.put(current, "extra", true)
          :wrong_schema -> Map.put(current, "schema_version", 2)
        end
        if @carrier_shape == :absent,
          do: Map.update!(r, "facts", &Map.delete(&1, @carrier_key)),
          else: put_in(r, ["facts", @carrier_key], value)
      end)
      ctx = start_again(ctx)
      expected = if @carrier_shape in [:direct, :absent], do: :ready, else: :recovery
      if @carrier_shape == :absent and @carrier_key == "claim" do
        # Claim creation independently requires its provenance result even though
        # absent is permitted by the typed carrier shape validator.
        assert %{mode: :recovery, reason: {:storage_unavailable, :invalid_claim_command_provenance}} = Gateway.status(ctx.g)
      else
        assert %{mode: ^expected} = Gateway.status(ctx.g)
      end
    end
  end

  for key <- ["reservations", "ledgers"],
      shape <- [:direct, :empty, :map, :nested, :duplicate, :ascending, :descending, :scalar, :wrong_kind, :extra, :missing_schema] do
    @plural_key key
    @plural_shape shape
    test "fresh plural #{@plural_key}/#{@plural_shape}", ctx do
      prepare(ctx)
      :ok = stop_supervised(Gateway)
      mutate_blob(ctx.path, "root_commands", "result", "operation = 'create_effect' AND disposition = 'accepted'", fn r ->
        [current] = r["facts"][@plural_key]
        old = Map.update!(current, "revision", &(&1 - 1))
        value = case @plural_shape do
          :direct -> [current]
          :empty -> []
          :map -> current
          :nested -> [[current]]
          :duplicate -> [current, current]
          :ascending -> [old, current]
          :descending -> [current, old]
          :scalar -> [1]
          :wrong_kind -> [r["facts"]["effect"]]
          :extra -> [Map.put(current, "extra", true)]
          :missing_schema -> [Map.delete(current, "schema_version")]
        end
        put_in(r, ["facts", @plural_key], value)
      end)
      ctx = start_again(ctx)
      # Empty is a valid list shape, but removing the last ledger snapshot cannot
      # satisfy independent current-row provenance.
      expected = if @plural_shape == :direct or (@plural_shape == :empty and @plural_key == "reservations"), do: :ready, else: :recovery
      assert %{mode: ^expected} = Gateway.status(ctx.g)
    end
  end

  for reverse <- [false, true] do
    @multi_reverse reverse
    test "fresh distinct plural reservations order #{@multi_reverse}", ctx do
      reserve(ctx, "r-e", "e")
      reserve(ctx, "r-extra", "e")
      accept(ctx, Map.put(effect("e"), "reservation_ids", ["r-e", "r-extra"]))
      :ok = stop_supervised(Gateway)
      mutate_blob(ctx.path, "root_commands", "result", "operation = 'create_effect' AND disposition = 'accepted'", fn r ->
        values = r["facts"]["reservations"]
        assert length(values) == 2
        put_in(r, ["facts", "reservations"], if(@multi_reverse, do: Enum.reverse(values), else: values))
      end)
      ctx = start_again(ctx)
      assert %{mode: :ready} = Gateway.status(ctx.g)
    end
  end
end
"""
Code.eval_string(base <> extra, [], file: __ENV__.file)
