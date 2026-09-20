# Residual B2 acceptance probes for candidate 9ed32575. No host/provider calls.
System.put_env("MIX_ENV", "test")
Code.require_file("../../ci/validate_fr15aa.exs", __DIR__)
alias PramanaFoundry.CI.FR15aAValidator, as: V
{manifest, _} = Code.eval_file(Path.join(__DIR__, "provisioning-manifest.exs"))
:ok = V.validate(manifest)

for field <- [:id, :kind, :version, :path, :status, :sha256],
    pin <- manifest.pins,
    operation <- [:erase, :change] do
  changed =
    update_in(manifest.pins, fn pins ->
      Enum.map(pins, fn p ->
        if p.id == pin.id do
          case operation do
            :erase -> Map.delete(p, field)
            :change -> Map.put(p, field, "unreviewed-value")
          end
        else
          p
        end
      end)
    end)

  {:error, _} = V.validate(changed)
end

IO.puts("All six pin identity fields: individual erasure/change rejected for every pin")

erased =
  update_in(manifest.pins, &Enum.map(&1, fn p -> Map.drop(p, [:path, :kind, :version]) end))

{:error, _} = V.validate(erased)

redirected =
  update_in(manifest.pins, fn pins ->
    Enum.map(pins, fn p ->
      if p.id == "foundry-config", do: %{p | path: "/tmp/unreviewed-config.exs"}, else: p
    end)
  end)

{:error, errors} = V.validate(redirected)
true = Enum.any?(errors, &String.contains?(&1, "kind/version/path/status"))
IO.puts("Prior erased-metadata and redirected-config mutations: rejected")

for {collection, id, hostile_fields} <- [
      {:principals, "workflow_kernel", %{account: "root"}},
      {:channels, "model-request", %{callers: ["slot_developer"]}},
      {:pins, "foundry-config", %{path: "/tmp/unreviewed-config.exs"}},
      {:routes, "shell", %{principal: "root", channel: "model-request"}}
    ],
    order <- [:first, :last] do
  entries = manifest[collection]
  original = Enum.find(entries, &(&1.id == id))
  hostile = Map.merge(original, hostile_fields)
  values = if order == :first, do: [hostile | entries], else: entries ++ [hostile]
  {:error, [error]} = V.validate(Map.put(manifest, collection, values))
  true = String.starts_with?(error, "duplicate ")
  IO.puts("Duplicate #{collection}, hostile #{order}: rejected before semantic validation")
end

for field <- [:allowed_operations, :forbidden_fields, :root_checks] do
  changed =
    update_in(manifest, [:kernel_protocol, field], fn [first | _] = xs -> [first | xs] end)

  {:error, [error]} = V.validate(changed)
  true = String.starts_with?(error, "duplicate kernel ")
end

for {collection, field, id} <- [
      {:channels, :callers, "model-request"},
      {:routes, :executable_ids, "shell"}
    ] do
  changed =
    update_in(manifest, [collection], fn entries ->
      Enum.map(entries, fn entry ->
        if entry.id == id,
          do: Map.update!(entry, field, fn [first | _] = xs -> [first | xs] end),
          else: entry
      end)
    end)

  {:error, [error]} = V.validate(changed)
  true = String.starts_with?(error, "duplicate ")
end

IO.puts("Nested caller/dependency and all kernel authority-list duplicates: rejected")
