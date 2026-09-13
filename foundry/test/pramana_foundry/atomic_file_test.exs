defmodule PramanaFoundry.AtomicFileTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.AtomicFile

  setup do
    root = Path.join(System.tmp_dir!(), "atomic-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{path: Path.join(root, "state.json")}
  end

  test "discards an uncheckpointed temporary file after a crash", %{path: path} do
    :ok = AtomicFile.write(path, %{"generation" => 1}, txid: "initial")

    assert {:error, {:injected_crash, :after_temp}} =
             AtomicFile.write(path, %{"generation" => 2},
               txid: "uncheckpointed",
               crash_at: :after_temp
             )

    assert :ok = AtomicFile.recover(path)
    assert %{"generation" => 1} = path |> File.read!() |> :json.decode()
    assert [] = File.ls!(Path.dirname(path)) |> Enum.filter(&String.ends_with?(&1, ".tmp"))
  end

  test "recovers a synced intent without exposing partial canonical JSON", %{path: path} do
    :ok = AtomicFile.write(path, %{"generation" => 1}, txid: "initial")

    assert {:error, {:injected_crash, :after_intent}} =
             AtomicFile.write(path, %{"generation" => 2},
               txid: "pending",
               crash_at: :after_intent
             )

    assert %{"generation" => 1} = path |> File.read!() |> :json.decode()
    assert :ok = AtomicFile.recover(path)
    assert %{"generation" => 2} = path |> File.read!() |> :json.decode()
  end

  test "completes cleanup after rename checkpoint crash", %{path: path} do
    assert {:error, {:injected_crash, :after_rename}} =
             AtomicFile.write(path, %{"generation" => 3},
               txid: "renamed",
               crash_at: :after_rename
             )

    assert %{"generation" => 3} = path |> File.read!() |> :json.decode()
    assert :ok = AtomicFile.recover(path)
    assert [] = Path.wildcard(Path.join(Path.dirname(path), ".state.json.*.intent"))
  end
end
