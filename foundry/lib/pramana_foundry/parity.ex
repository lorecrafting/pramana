defmodule PramanaFoundry.Parity do
  @moduledoc """
  Executable parity against the live Python supervisor serializers.

  The Python probe imports the tracked production module and writes only below a disposable
  temporary root. Checked-in sanitized records must match what those serializers emit.
  """

  alias PramanaFoundry.Import

  @python_probe """
  import json, pathlib, sys, tempfile
  sys.path.insert(0, sys.argv[1])
  import pramana_supervisor as supervisor


  def sanitize(value, root):
      if isinstance(value, dict):
          return {key: sanitize(item, root) for key, item in value.items()}
      if isinstance(value, list):
          return [sanitize(item, root) for item in value]
      if isinstance(value, str):
          return value.replace(str(root), "/sanitized/runtime")
      return value
  fixed_at = "2026-09-08T00:00:00Z"
  kind = sys.argv[2]
  with tempfile.TemporaryDirectory(prefix="pramana-parity-") as directory:
      root = pathlib.Path(directory)
      store = supervisor.StateStore(root)

      if kind == "snapshot":
          record = store.load()
          record["updated_at"] = fixed_at
      elif kind == "control":
          path = store.enqueue_control("pause", {"fixture": True})
          record = supervisor.read_json(path)
          record["created_at"] = fixed_at
      elif kind == "event":
          store.event(
              "assignment_admitted",
              task_id="T1",
              run_id="run-1",
              role="developer",
              diagnostic={"kept": True},
          )
          record = json.loads(store.events_path.read_text(encoding="utf-8").splitlines()[0])
          record["at"] = fixed_at
      elif kind == "assignment":
          instance = object.__new__(supervisor.Supervisor)
          instance.store = store
          instance.config = {"backend": {}, "disabled_operations": ["remote_push"]}
          instance.state = {"accepted_revision": "a" * 40}
          profile = {
              "model": "model",
              "model_id": "provider/model",
              "reasoning": "medium",
              "profile": "profile",
          }
          ticket = {
              "task_id": "T1",
              "base_revision": "a" * 40,
              "outcome": "sanitized parity fixture",
              "priority": "P0",
              "evidence": ["fixture contract"],
              "dependencies": [],
              "scope": ["workflow/**"],
              "exclusions": ["secrets/**"],
              "acceptance_criteria": ["fixture check passes"],
              "required_checks": [["sh", "-c", "true"]],
              "review_required_checks": [["sh", "-c", "true"]],
              "checkout": str(root / "checkout"),
              "role": "developer",
              "model": "model",
              "requested_operations": [],
              "handoff_path": str(root / "handoff.json"),
              "review_path": str(root / "review.json"),
              "workload": "standard",
          }
          assignment = {
              "run_id": "run-1",
              "active_profile_config": profile,
              "ticket": ticket,
          }
          instance.write_assignment_artifact(assignment, "developer")
          record = supervisor.read_json(
              store.artifacts / "assignments" / "run-1-developer.json"
          )
      else:
          raise ValueError(f"unsupported kind: {kind}")

      print(json.dumps(sanitize(record, root), sort_keys=True, separators=(",", ":")))
  """

  @spec compare_fixture(atom(), Path.t()) :: map()
  def compare_fixture(kind, path) when kind in [:snapshot, :control, :assignment, :event] do
    with {:ok, fixture} <- decode_fixture(kind, path),
         {:ok, python} <- python_record(kind),
         :ok <- compare_records(fixture, python),
         {:ok, normalized} <- validate_fixture(kind, path) do
      %{
        status: :equal,
        kind: kind,
        identity: Map.take(normalized, ~w(task_id run_id role)),
        evidence_preserved: evidence_preserved?(kind, normalized)
      }
    else
      {:error, reason} -> %{status: :unexpected_difference, kind: kind, reason: reason}
    end
  end

  def shadow(input, opts \\ []) do
    if Keyword.has_key?(opts, :herdr) or Keyword.has_key?(opts, :live_state_writer) do
      {:error, :effects_forbidden_in_shadow_mode}
    else
      {:ok, %{input: input, herdr_calls: 0, live_state_writes: 0}}
    end
  end

  defp decode_fixture(:event, path) do
    with {:ok, bytes} <- File.read(path),
         [line] <- String.split(bytes, "\n", trim: true) do
      decode_json(line)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :event_fixture_must_have_one_record}
    end
  end

  defp decode_fixture(_kind, path) do
    with {:ok, bytes} <- File.read(path), do: decode_json(bytes)
  end

  defp decode_json(bytes) do
    try do
      {:ok, :json.decode(bytes)}
    rescue
      _ -> {:error, :malformed_fixture}
    catch
      _, _ -> {:error, :malformed_fixture}
    end
  end

  defp python_record(kind) do
    workflows = Path.expand("../../", __DIR__)

    case System.cmd("python3", ["-c", @python_probe, workflows, Atom.to_string(kind)],
           stderr_to_stdout: true
         ) do
      {output, 0} -> decode_json(output)
      {output, status} -> {:error, {:python_baseline_failed, status, output}}
    end
  end

  defp compare_records(record, record), do: :ok
  defp compare_records(_fixture, _python), do: {:error, :python_baseline_drift}

  defp validate_fixture(:event, path) do
    with {:ok, [record]} <- Import.read_jsonl(path, :event), do: {:ok, record}
  end

  defp validate_fixture(kind, path), do: Import.read(path, kind)

  defp evidence_preserved?(:event, %{"evidence" => %{"diagnostic" => %{"kept" => true}}}),
    do: true

  defp evidence_preserved?(:control, %{"evidence" => %{"python_wire_record" => record}}),
    do: is_map(record)

  defp evidence_preserved?(_kind, _record), do: true
end
