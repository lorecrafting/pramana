defmodule PramanaFoundry.RelocationContainmentTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Relocation

  test "execute is disabled before creating a journal" do
    root = Path.join(System.tmp_dir!(), "fr19a-relocation-#{System.unique_integer([:positive])}")
    journal = Path.join(root, "journal.jsonl")

    assert {:error, {:relocation_disabled, :fr19b_required}} =
             Relocation.execute(%{steps: [], manifest: %{}, opts: [journal_path: journal]})

    assert {:error, {:relocation_disabled, :fr19b_required}} =
             Relocation.execute(paths: [Path.join(root, "unreadable")], journal_path: journal)

    refute File.exists?(journal)
  end

  test "resume and rollback are disabled before reading a journal" do
    missing = Path.join(System.tmp_dir!(), "fr19a-missing-#{System.unique_integer([:positive])}")

    assert {:error, {:relocation_disabled, :fr19b_required}} = Relocation.resume(missing)
    assert {:error, {:relocation_disabled, :fr19b_required}} = Relocation.rollback(missing)
    refute File.exists?(missing)
  end
end
