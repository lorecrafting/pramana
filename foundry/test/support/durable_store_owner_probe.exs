alias PramanaFoundry.DurableStore.Gateway

[path] = System.argv()
{:ok, gateway} = Gateway.start_link(path: path)

case Gateway.status(gateway) do
  %{mode: :recovery, reason: {:store_owner_unavailable, _reason}} -> System.halt(0)
  other ->
    IO.inspect(other, label: "unexpected_second_owner")
    System.halt(1)
end
