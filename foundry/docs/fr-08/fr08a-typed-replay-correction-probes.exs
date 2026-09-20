# Maintained T3 correction matrix. It preserves the independent 46 cases while
# applying the corrected singular-cardinality contract and adds shape permutations.
source = File.read!("docs/fr-08/fr08a-typed-replay-review-probes.exs")

source =
  String.replace(
    source,
    "expected = if @variation == :identical_duplicates, do: :ready, else: :recovery",
    "expected = :recovery"
  )

additional = ~S"""

  for variation <- [:single_list, :nested_single, :duplicate, :scalar, :wrong_kind, :extra_key, :wrong_schema] do
    @singular_variation variation
    test "typed correction: singular effect shape #{@singular_variation} fences", ctx do
      prepare(ctx)
      issue(ctx)
      :ok = stop_supervised(Gateway)
      mutate_blob(ctx.path, "root_commands", "result", "operation = 'issue_claim' AND disposition = 'accepted'", fn r ->
        current = r["facts"]["effect"]
        value = case @singular_variation do
          :single_list -> [current]
          :nested_single -> [[current]]
          :duplicate -> [current, current]
          :scalar -> "effect"
          :wrong_kind -> r["facts"]["claim"]
          :extra_key -> Map.put(current, "extra", true)
          :wrong_schema -> Map.put(current, "schema_version", 2)
        end
        put_in(r, ["facts", "effect"], value)
      end)
      ctx = start_again(ctx)
      assert %{mode: :recovery} = Gateway.status(ctx.g)
    end
  end

  for variation <- [:map, :nested, :duplicate, :conflict] do
    @plural_variation variation
    test "typed correction: plural reservation shape #{@plural_variation} fences", ctx do
      prepare(ctx)
      :ok = stop_supervised(Gateway)
      mutate_blob(ctx.path, "root_commands", "result", "operation = 'create_effect' AND disposition = 'accepted'", fn r ->
        [current] = r["facts"]["reservations"]
        value = case @plural_variation do
          :map -> current
          :nested -> [[current]]
          :duplicate -> [current, current]
          :conflict -> [current, Map.put(current, "status", "released")]
        end
        put_in(r, ["facts", "reservations"], value)
      end)
      ctx = start_again(ctx)
      assert %{mode: :recovery} = Gateway.status(ctx.g)
    end
  end
"""

source =
  String.replace(
    source,
    "\nend\n\"\"\"\n\nCode.eval_string(base <> extra, [], file: __ENV__.file)",
    additional <>
      "\nend\n\"\"\"\n\nCode.eval_string(base <> extra, [], file: __ENV__.file)"
  )

Code.eval_string(source, [], file: __ENV__.file)
