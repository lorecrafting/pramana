# Witness for the `command`-drift defect recorded in the implementation log for 2026-09-22.
#
#   cd foundry && TMPDIR=/private/tmp mix run docs/fr-04/identity-drift-probe.exs
#
# Launches a check through the real `Checks.Runner` path, reads the identity the way a
# caller builds `recorded_identity` (await_child_pid then ProcessGroup.identity/1), reads it
# again after the child has settled, and reports how often the two disagree and what that
# costs. The drift is a race, so it reports a rate over N rather than a single verdict.
#
# Red control: the `stable` bucket. If a run reports 0 drifted, the probe measured nothing
# and its numbers say nothing about the defect -- rerun rather than concluding it is fixed.

alias PramanaFoundry.Checks.{Runner, Status, Adoption}
alias PramanaFoundry.Effects.ProcessGroup

runs = String.to_integer(System.get_env("PROBE_RUNS", "12"))

# A re-execing shim, which is what makes the two reads disagree: /usr/bin/python3 hands off
# to the framework Python and argv[0] changes while pid, group and start time do not.
command = ["python3", "-c", "import time; time.sleep(30)"]

one = fn n ->
  root = Path.join(System.tmp_dir!(), "identity-drift-#{n}-#{System.unique_integer([:positive])}")
  File.mkdir_p!(root)

  spec = %{
    launch_token: "drift-#{n}",
    command: command,
    cwd: root,
    env: %{},
    spec_path: Path.join(root, "spec.json"),
    identity_path: Path.join(root, "identity.json"),
    completion_path: Path.join(root, "completion.json"),
    cancellation_path: Path.join(root, "cancellation.json"),
    output_path: Path.join(root, "output.log")
  }

  {:ok, _port} = Runner.launch(spec)
  {:ok, pid} = Runner.await_child_pid(spec)
  {:ok, recorded} = ProcessGroup.identity(pid)
  Process.sleep(300)
  {:ok, live} = ProcessGroup.identity(pid)

  state = %{
    recorded_identity: recorded,
    live_identity: live,
    completion: nil,
    deadline_epoch: nil,
    cancellation_requested?: false,
    stop_intent_checkpointed?: false
  }

  result = %{
    drifted?: not ProcessGroup.same_process?(recorded, live),
    # Only `command` may move. If anything else does, this is a different process and the
    # probe is measuring pid reuse rather than the defect.
    only_command_moved?:
      recorded.pid == live.pid and recorded.process_group_id == live.process_group_id and
        recorded.started_at == live.started_at,
    alive?: ProcessGroup.presence(live, &ProcessGroup.identity/1),
    classify_running: Status.classify(state),
    classify_cancelling: Status.classify(%{state | cancellation_requested?: true}),
    reconcile:
      case Adoption.reconcile(Map.delete(state, :live_identity)) do
        {:adopted, _identity} -> :adopted
        other -> other
      end,
    signal_direct: ProcessGroup.signal(recorded, :sigterm)
  }

  Process.sleep(300)
  survived = ProcessGroup.presence(live, &ProcessGroup.identity/1)
  if survived != :gone, do: Runner.terminate(spec, live, "probe cleanup")

  # Wait for the trampoline's own completion write before removing the directory under it;
  # deleting first makes it raise FileNotFoundError onto this output, which reads as a probe
  # failure rather than the cleanup race it is.
  Enum.reduce_while(1..100, nil, fn _i, _acc ->
    case Runner.read_completion(spec) do
      {:ok, _completion} -> {:halt, :done}
      _not_yet -> Process.sleep(20) && {:cont, nil}
    end
  end)

  File.rm_rf!(root)

  Map.put(result, :survived_direct_signal, survived)
end

results = Enum.map(1..runs, one)
{drifted, stable} = Enum.split_with(results, & &1.drifted?)

IO.puts("\nlaunches: #{runs}    drifted: #{length(drifted)}    stable: #{length(stable)}")

if drifted == [] do
  IO.puts("\nRED CONTROL: 0 of #{runs} drifted, so this run measured nothing. Rerun.")
else
  IO.puts("  only `command` moved in every drifted run: #{Enum.all?(drifted, & &1.only_command_moved?)}")
  IO.puts("  process alive at classification time:      #{drifted |> Enum.map(& &1.alive?) |> Enum.frequencies() |> inspect()}")
  IO.puts("\nwhat the drift costs, over #{length(drifted)} drifted launches of a LIVE check:")

  for {label, key} <- [
        {"Status.classify, running     ", :classify_running},
        {"Status.classify, cancelling  ", :classify_cancelling},
        {"Adoption.reconcile, restart  ", :reconcile},
        {"ProcessGroup.signal(recorded)", :signal_direct},
        {"  process after that signal  ", :survived_direct_signal}
      ] do
    IO.puts("  #{label}  #{drifted |> Enum.map(&Map.fetch!(&1, key)) |> Enum.frequencies() |> inspect()}")
  end

  IO.puts("\nthe same calls over #{length(stable)} stable launches, for contrast:")
  for {label, key} <- [{"Status.classify, running     ", :classify_running},
                       {"Adoption.reconcile, restart  ", :reconcile}], stable != [] do
    IO.puts("  #{label}  #{stable |> Enum.map(&Map.fetch!(&1, key)) |> Enum.frequencies() |> inspect()}")
  end
end
