defmodule Pramana.RelationsSharedTextTaskTest do
  use Pramana.DataCase

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pramana.Relations.SharedText
  alias Pramana.Corpus.DerivationRun
  alias Pramana.Repo

  test "the default shared-text command reports without writing a receipt" do
    output = capture_io(fn -> SharedText.run([]) end)

    assert output =~ "DRY RUN — nothing written; add --write"
    assert Repo.get_by(DerivationRun, derivation: "relations_shared_text") == nil
  end
end
