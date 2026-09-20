# Historical reproduction for corrected candidate 5a7eb463. Accepted hostile
# mutations below reproduce residual B2; this is not an acceptance gate.
System.put_env("MIX_ENV", "test")
Code.require_file("../../ci/validate_fr15aa.exs", __DIR__)
alias PramanaFoundry.CI.FR15aAValidator, as: V
alias PramanaFoundry.CI.FR15aAProcedure, as: P
{manifest, _} = Code.eval_file(Path.join(__DIR__, "provisioning-manifest.exs"))
:ok = V.validate(manifest)

for {label, changed} <- [
      {"erased pin executable/config identity",
       update_in(manifest.pins, &Enum.map(&1, fn p -> Map.drop(p, [:path, :kind, :version]) end))},
      {"redirected config outside repository byte validation",
       update_in(manifest.pins, fn pins ->
         Enum.map(pins, fn p ->
           if p.id == "foundry-config", do: %{p | path: "/tmp/unreviewed-config.exs"}, else: p
         end)
       end)},
      {"contradictory duplicate auth channel",
       update_in(manifest.channels, fn channels ->
         auth = Enum.find(channels, &(&1.id == "model-request"))
         [%{auth | callers: ["slot_developer"]} | channels]
       end)},
      {"contradictory duplicate shell route",
       update_in(manifest.routes, fn routes ->
         shell = Enum.find(routes, &(&1.id == "shell"))
         [%{shell | principal: "root", channel: "model-request"} | routes]
       end)}
    ] do
  :ok = V.validate(changed)
  IO.puts("RESIDUAL B2 accepted: #{label}")
end

for {label, changed} <- [
      {"kernel forged fields", put_in(manifest.kernel_protocol.forbidden_fields, [])},
      {"kernel stale epoch check omitted",
       update_in(manifest.kernel_protocol.root_checks, &List.delete(&1, "current_writer_epoch"))},
      {"worker auth access",
       update_in(manifest.channels, fn channels ->
         Enum.map(channels, fn c ->
           if c.id == "model-request", do: %{c | callers: ["slot_developer"]}, else: c
         end)
       end)},
      {"adapter silently implemented",
       update_in(manifest.pins, fn pins ->
         Enum.map(pins, fn p ->
           if p.id == "workflow-kernel", do: %{p | status: "implemented"}, else: p
         end)
       end)}
    ] do
  {:error, _} = V.validate(changed)
  IO.puts("CORRECTLY rejected: #{label}")
end

specification = File.read!(Path.join(__DIR__, "provisioning-specification.md"))
blocks = Regex.scan(~r/```sh\n(.*?)```/s, specification, capture: :all_but_first)
[account_preflight] = Enum.find(blocks, fn [b] -> String.contains?(b, "record_absent()") end)

for {mode, expected} <- [
      {"absent", 0},
      {"user_name", 1},
      {"group_name", 1},
      {"user_id", 1},
      {"group_id", 1},
      {"read_unknown", 1},
      {"list_unknown", 1}
    ] do
  # All directory-service calls are shell functions: no accounts are inspected.
  mock = """
  dscl() {
    case "$2:$3:$MODE" in
      -list:*:list_unknown) return 70 ;;
      -list:/Users:user_id) printf 'foreign 451\\n'; return 0 ;;
      -list:/Groups:group_id) printf 'foreign 451\\n'; return 0 ;;
      -list:*) printf 'ordinary 501\\n'; return 0 ;;
      -read:/Users/_pramana_launcher:user_name) printf 'record\\n'; return 0 ;;
      -read:/Groups/_pramana_launcher:group_name) printf 'record\\n'; return 0 ;;
      -read:*:read_unknown) printf 'transport failure\\n'; return 70 ;;
      -read:*) printf 'DS Error: -14136 (eDSRecordNotFound)\\n'; return 56 ;;
      *) return 99 ;;
    esac
  }
  """

  {_, ^expected} = System.cmd("/bin/sh", ["-c", mock <> account_preflight], env: [{"MODE", mode}])
  IO.puts("PREFLIGHT #{mode}: exit #{expected}")
end

{:error, :resource_present} = P.require_all_absent([{:ok, :present}, {:ok, :absent}])
{:error, :observer_unknown} = P.require_all_absent([P.process_observation("", 2)])
{:error, :observer_unknown} = P.require_all_absent([P.socket_observation("", 1)])

{:ok, [%{resource_id: "created"}]} =
  P.rollback_targets([
    %{resource_id: "created", preexisting: false, created_by_attempt: true},
    %{
      resource_id: "modified",
      preexisting: true,
      created_by_attempt: false,
      modified_by_attempt: true,
      backup: "verified-backup"
    },
    %{resource_id: "untouched", preexisting: true, created_by_attempt: false},
    %{resource_id: "not-created", preexisting: false, created_by_attempt: false}
  ])

{:error, :ownership_unknown} = P.rollback_targets([%{resource_id: "unknown"}])
IO.puts("ROLLBACK observations and created/preexisting/modified selection: expected results")
