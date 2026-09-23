# B3 (2026-09-22): walk-accepted label counts over the 40 broad + 25 deep walks of
# kernel_properties_test. Measures the tree it runs on; the "guards off" and "old proposer"
# rows of the log table were taken by temporarily neutralising the three guard bodies and
# dropping the second control proposal, then reversing both. From foundry/:
#   TMPDIR=/private/tmp MIX_ENV=test mix run --no-start docs/fr-08/b3-measurements-2026-09-22/walk_labels.exs
ExUnit.start(autorun: false)
root = Path.expand("../../../test/support", __DIR__)
for f <- ~w(kernel_harness.ex kernel_walk.ex), do: Code.require_file(Path.join(root, f))
alias PramanaFoundry.Test.KernelWalk
alias PramanaFoundry.Workflow.Kernel.State
PramanaFoundry.Test.Harness.start()

broad = Enum.map(1..40, &KernelWalk.walk(State.new(), &1, 600))
deep = Enum.map(1..25, &KernelWalk.deep(State.new(), &1, 800))
walks = broad ++ deep

labels = Enum.flat_map(walks, fn w -> Enum.map(w.accepted, &KernelWalk.label/1) end)
freq = Enum.frequencies(labels)

for l <- ~w(launch_planned review_planned integration_planned attempt_settled:superseded_base
            integration_recorded:ref_created cancellation_requested control_changed) do
  IO.puts("#{l}: #{freq[l] || 0}")
end

# superseded_base witnesses: was the ticket's cancel pending when it settled?
under_cancel =
  Enum.sum(
    for w <- walks do
      {_, n} =
        Enum.reduce(w.accepted, {State.new(), 0}, fn e, {s, n} ->
          {:ok, next} = PramanaFoundry.Test.Harness.apply(s, e)

          n =
            if KernelWalk.label(e) == "attempt_settled:superseded_base" and
                 s["tickets"][e["entity_id"]]["cancel_requested"],
               do: n + 1,
               else: n

          {next, n}
        end)

      n
    end
  )

IO.puts("superseded_base settled under a pending cancel: #{under_cancel}")

refused =
  walks
  |> Enum.flat_map(& &1.rejected)
  |> Enum.filter(fn {_t, r} -> r in [:control_paused, :control_draining, :cancel_pending] end)
  |> Enum.frequencies()

IO.inspect(refused, label: "new-atom refusals in walks")
