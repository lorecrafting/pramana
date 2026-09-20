alias PramanaFoundry.DurableStore.Gateway

[path] = System.argv()
{:ok, gateway} = Gateway.start_link(path: path)
id = "rlimit-write"

key =
  "projection/" <>
    Base.url_encode64("kernel-v1", padding: false) <>
    "/" <> Base.url_encode64("ticket-" <> id, padding: false)

command = %{
  "schema_version" => 1,
  "command_id" => id,
  "expected_revisions" => %{key => "absent"},
  "type" => "request_effect",
  "target_ids" => %{},
  "payload" => %{"bytes" => String.duplicate("x", 128 * 1024)}
}

proposal = %{
  schema_version: 1,
  result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
  events: [
    %{
      schema_version: 1,
      event_id: "event-" <> id,
      type: "effect_requested",
      payload: %{
        "projection" => %{
          "namespace" => "kernel-v1",
          "entity_id" => "ticket-" <> id,
          "revision" => 0,
          "value" => %{}
        }
      }
    }
  ],
  projections: [%{schema_version: 1, namespace: "kernel-v1", entity_id: "ticket-" <> id, expected_revision: -1, revision: 0, last_event_id: "event-" <> id, value: %{}}]
}

case Gateway.transact(gateway, "rlimit-probe", command, proposal) do
  {:error, {:storage_unavailable, reason}} ->
    IO.inspect(reason, label: "real_rlimit_write_failure")
    System.halt(0)

  other ->
    IO.inspect(other, label: "unexpected_write_result")
    System.halt(1)
end
