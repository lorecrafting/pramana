defmodule PramanaFoundry.Relocation.JournalTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Relocation.Journal

  @moduletag :journal

  setup do
    tmp = Path.join(System.tmp_dir!(), "journal-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    journal_path = Path.join(tmp, "test_journal.jsonl")
    on_exit(fn -> File.rm_rf(tmp) end)
    {:ok, tmp: tmp, journal_path: journal_path}
  end

  test "init creates journal and writes init record", %{journal_path: jp} do
    assert {:ok, ^jp} = Journal.init(jp, "tx-init-1")
    assert File.exists?(jp)

    assert {:ok, entries} = Journal.read_entries(jp)
    assert length(entries) == 1
    init_entry = hd(entries)
    assert init_entry["txid"] == "tx-init-1"
    assert init_entry["step_id"] == "init"
    assert init_entry["status"] == "completed"
  end

  test "records atomic steps and reconstructs execution state", %{journal_path: jp} do
    txid = "tx-rec-1"
    {:ok, _} = Journal.init(jp, txid)

    # Step 1: prepared and completed
    assert :ok =
             Journal.record(
               jp,
               txid,
               1,
               "step-1",
               :move_directory,
               :prepared,
               "/src/1",
               "/dst/1",
               %{"meta" => 1}
             )

    assert :ok =
             Journal.record(
               jp,
               txid,
               2,
               "step-1",
               :move_directory,
               :completed,
               "/src/1",
               "/dst/1",
               %{"meta" => 1}
             )

    # Step 2: prepared only (in-flight)
    assert :ok =
             Journal.record(
               jp,
               txid,
               3,
               "step-2",
               :move_worktree,
               :prepared,
               "/src/2",
               "/dst/2",
               %{"meta" => 2}
             )

    # Step 3: prepared and rolled back
    assert :ok =
             Journal.record(
               jp,
               txid,
               4,
               "step-3",
               :move_directory,
               :prepared,
               "/src/3",
               "/dst/3",
               %{}
             )

    assert :ok =
             Journal.record(
               jp,
               txid,
               5,
               "step-3",
               :move_directory,
               :rolled_back,
               "/src/3",
               "/dst/3",
               %{}
             )

    assert {:ok, state} = Journal.reconstruct_state(jp)
    assert state.txid == txid
    assert length(state.entries) == 6

    # Completed steps: step-1
    assert length(state.completed) == 1
    assert hd(state.completed)["step_id"] == "step-1"

    # In-flight steps: step-2
    assert length(state.in_flight) == 1
    assert hd(state.in_flight)["step_id"] == "step-2"
    assert hd(state.in_flight)["status"] == "prepared"

    # Rolled-back steps: step-3
    assert length(state.rolled_back) == 1
    assert hd(state.rolled_back)["step_id"] == "step-3"
    assert hd(state.rolled_back)["status"] == "rolled_back"
  end
end
