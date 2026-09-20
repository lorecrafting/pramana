# Historical reproduction of the frozen ca4094e FR-15aA validation gaps.
# This is evidence, not an acceptance test: :ok for a hostile mutation is the defect.
# Run from the repository root with MIX_ENV=test elixir <this file>.
Code.require_file("../../ci/validate_fr15aa.exs", __DIR__)
{manifest, _} = Code.eval_file(Path.join(__DIR__, "provisioning-manifest.exs"))
validator = &PramanaFoundry.CI.FR15aAValidator.validate/1
:ok = validator.(manifest)
IO.puts("baseline: :ok")

mutations = [
  {"collapse every principal to root with interactive login",
   update_in(manifest.principals, fn principals ->
     Enum.map(principals, &Map.merge(&1, %{account: "root", login: true}))
   end)},
  {"erase channel transport and path",
   update_in(manifest.channels, &Enum.map(&1, fn channel -> Map.take(channel, [:id]) end))},
  {"promote unimplemented routes and remove fail-closed assertion",
   update_in(manifest.routes, fn routes ->
     Enum.map(routes, &Map.merge(&1, %{production_status: "supported", fail_closed: false}))
   end)},
  {"execute shell as root over model-request channel",
   update_in(manifest.routes, fn routes ->
     Enum.map(routes, fn route ->
       if route.category == "shell",
         do: Map.merge(route, %{principal: "root", channel: "model-request"}),
         else: route
     end)
   end)},
  {"erase provenance and host profile",
   manifest |> Map.delete(:source) |> update_in([:authority], &Map.delete(&1, :host_profile))},
  {"replace every repository digest with an unrelated digest",
   update_in(manifest.pins, fn pins ->
     Enum.map(pins, fn pin ->
       if pin.status == "blocked", do: pin, else: %{pin | sha256: String.duplicate("0", 64)}
     end)
   end)},
  {"replace every executable dependency with the package lock pin",
   update_in(
     manifest.routes,
     &Enum.map(&1, fn route -> %{route | executable_ids: ["foundry-lock"]} end)
   )}
]

Enum.each(mutations, fn {name, changed} ->
  result = validator.(changed)
  IO.puts("#{name}: #{inspect(result)}")
  :ok = result
end)

# All observation commands below are shell functions. No host process/socket inspection,
# privilege command, or provisioning operation is performed.
shell_cases = [
  {"earlier live principal masked by final absent principal",
   "pgrep() { if [ \"$2\" = first ]; then return 0; else return 1; fi; }; for name in first last; do ! pgrep -U \"$name\"; done"},
  {"process observer error interpreted as absence", "pgrep() { return 2; }; ! pgrep -U fake"},
  {"socket observer error interpreted as absence",
   "sudo() { return 1; }; test -z \"$(sudo lsof -nP -U | grep /var/run/pramana-foundry || true)\""}
]

Enum.each(shell_cases, fn {name, script} ->
  {"", 0} = System.cmd("/bin/sh", ["-c", script], stderr_to_stdout: true)
  IO.puts("#{name}: exit 0")
end)
