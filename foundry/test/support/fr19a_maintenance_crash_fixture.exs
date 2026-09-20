alias PramanaFoundry.DurableStore.Gateway

[path, operation, destination] = System.argv()
point = if operation == "checkpoint", do: :after_checkpoint, else: :after_backup_snapshot

{:ok, gateway} =
  Gateway.start_link(path: path, maintenance_fault: {:halt, point})

case operation do
  "checkpoint" -> Gateway.checkpoint(gateway)
  "backup" -> Gateway.backup(gateway, destination)
end

raise "maintenance interruption fixture did not halt"
