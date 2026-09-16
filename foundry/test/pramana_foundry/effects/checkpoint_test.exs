defmodule PramanaFoundry.Effects.CheckpointTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Effects.Checkpoint

  setup do
    root = Path.join(System.tmp_dir!(), "checkpoint-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{log_path: Path.join(root, "events.jsonl")}
  end

  test "events/1 is an empty list before any checkpoint exists", %{log_path: log_path} do
    assert {:ok, []} = Checkpoint.events(log_path)
  end

  test "append/6 is durable and readable back in order", %{log_path: log_path} do
    assert {:ok, first} = Checkpoint.append(log_path, "launch_intent", "T1", "R1", "developer")

    assert {:ok, _second} =
             Checkpoint.append(log_path, "launch_completed", "T1", "R1", "developer")

    assert {:ok, [read_first, read_second]} = Checkpoint.events(log_path)
    assert read_first["event"] == "launch_intent"
    assert read_second["event"] == "launch_completed"
    assert first["schema_version"] == 1
  end

  test "matching/5 requires event, task, run and role to agree independently", %{
    log_path: log_path
  } do
    expected = ["launch_intent", "T1", "R1", "developer"]
    assert {:ok, record} = apply(Checkpoint, :append, [log_path | expected])

    assert {:ok, ^record} = apply(Checkpoint, :matching, [log_path | expected])

    for {index, other} <- [{0, "prompt_intent"}, {1, "T2"}, {2, "R2"}, {3, "reviewer"}] do
      different = List.replace_at(expected, index, other)
      assert {:ok, nil} = apply(Checkpoint, :matching, [log_path | different])
      assert {:ok, _} = apply(Checkpoint, :append, [log_path | different])
      assert {:ok, ^record} = apply(Checkpoint, :matching, [log_path | expected])
    end
  end
end
