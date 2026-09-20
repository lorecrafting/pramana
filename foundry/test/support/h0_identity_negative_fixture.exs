alias PramanaFoundry.DurableStore.Gateway
alias PramanaFoundry.Repair.H0AcceptedFR07Boundary

source = Gateway.module_info(:compile)[:source] |> List.to_string()
original = File.read!(source)
needle = "  def command(server, command_id), do: GenServer.call(server, {:command, command_id})"

replacement = """
  def command(_server, "H0-IDENTITY-NEGATIVE"), do: {:ok, :changed_loaded_implementation}
#{needle}
"""

changed = String.replace(original, needle, replacement, global: false)
true = changed != original
Code.compiler_options(ignore_module_conflict: true)
Code.compile_string(changed, source)
{:ok, :changed_loaded_implementation} = Gateway.command(nil, "H0-IDENTITY-NEGATIVE")

report = H0AcceptedFR07Boundary.report(System.fetch_env!("H0_ADAPTER_REVISION"))

%{status: "mismatch", method: "source-sha256+beam-md5/v1"} =
  report.identity.implementation_binding

%{status: "blocked", passed_count: 0, failed_count: 0, unavailable_count: 7} = report.gate

true =
  Enum.all?(report.gate.capabilities, fn capability ->
    capability.status == "unavailable" and
      capability.reason == "h0:loaded_accepted_api_identity_mismatch"
  end)

IO.write("identity_mismatch_refused\n")
