# B3 (2026-09-22): reachable-state counts at depth 6 and 7, and whether the three B3 atoms fire.
# Measures the tree it runs on. From foundry/:
#   TMPDIR=/private/tmp MIX_ENV=test mix run --no-start docs/fr-08/b3-measurements-2026-09-22/search_states.exs
ExUnit.start(autorun: false)
root = Path.expand("../../../test/support", __DIR__)
for f <- ~w(kernel_harness.ex kernel_walk.ex kernel_search.ex), do: Code.require_file(Path.join(root, f))
alias PramanaFoundry.Test.KernelSearch
PramanaFoundry.Test.Harness.start()

for d <- [6, 7] do
  {t, states} = :timer.tc(fn -> KernelSearch.search(d) end)
  IO.puts("depth #{d}: #{length(states)} states in #{div(t, 1000)} ms")
end

reasons = KernelSearch.rejection_reasons(7)

IO.inspect(
  Enum.filter(MapSet.to_list(reasons), &(&1 in [:control_paused, :control_draining, :cancel_pending])),
  label: "new atoms fired at 7"
)
