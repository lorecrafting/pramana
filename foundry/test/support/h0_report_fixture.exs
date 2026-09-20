alias PramanaFoundry.DurableStore.{Gateway, Kernel, LegacyImport, RecordCodec}
alias PramanaFoundry.Repair.H0AcceptedFR07Boundary

modules = [Gateway, Kernel, LegacyImport, RecordCodec]

modules =
  case System.fetch_env!("H0_LOAD_ORDER") do
    "normal" -> modules
    "reverse" -> Enum.reverse(modules)
  end

Enum.each(modules, fn module -> {:module, ^module} = Code.ensure_loaded(module) end)

System.fetch_env!("H0_ADAPTER_REVISION")
|> H0AcceptedFR07Boundary.report_artifact()
|> IO.write()
