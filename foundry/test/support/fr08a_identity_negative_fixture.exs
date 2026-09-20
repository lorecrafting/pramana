alias PramanaFoundry.DurableStore.Gateway
alias PramanaFoundry.Repair.FR08AProtectedBoundary

source = Gateway.module_info(:compile)[:source] |> List.to_string()
original = File.read!(source)
needle = "  def command(server, command_id), do: GenServer.call(server, {:command, command_id})"

replacement = """
  def command(_server, "FR08A-IDENTITY-NEGATIVE"), do: {:ok, :changed_loaded_implementation}
#{needle}
"""

changed = String.replace(original, needle, replacement, global: false)
true = changed != original
Code.compiler_options(ignore_module_conflict: true)
Code.compile_string(changed, source)
{:ok, :changed_loaded_implementation} = Gateway.command(nil, "FR08A-IDENTITY-NEGATIVE")

report = FR08AProtectedBoundary.report()
"mismatch:source-sha256+beam-md5/v1" = report.identity.implementation_binding
%{status: "blocked", passed_count: 0, failed_count: 0, unavailable_count: 7} = report.gate

true =
  Enum.all?(report.gate.capabilities, fn capability ->
    capability.status == "unavailable" and
      capability.reason == "fr08a:loaded_subject_identity_mismatch"
  end)

IO.write("identity_mismatch_refused\n")
