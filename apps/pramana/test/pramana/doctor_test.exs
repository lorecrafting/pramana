defmodule Mix.Tasks.Pramana.DoctorTest do
  @moduledoc """
  The command a session opens with must not be the thing that breaks.

  There is little logic here to test — `doctor` composes figures other modules compute — so
  what is pinned is that it **runs against an empty corpus without raising** and still says
  something true. A diagnostic that only works once everything is loaded is useless at
  exactly the moment it is needed.
  """
  use Pramana.DataCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pramana.Doctor

  test "runs on an empty corpus and reports the absence rather than crashing" do
    output = capture_io(fn -> Doctor.run([]) end)

    assert output =~ "bake"
    assert output =~ "no bake recorded"
    assert output =~ "corpus"
    assert output =~ "sources"
    assert output =~ "migrations"
  end

  test "names every declared source, including ones never acquired" do
    # A source declared and never acquired is a normal state — SAT has been one for phases —
    # and it is exactly what a session needs before wondering why a search returns nothing.
    output = capture_io(fn -> Doctor.run([]) end)

    for id <- Pramana.Sources.ids() do
      assert output =~ id, "#{id} is declared and absent from the report"
    end
  end

  test "leads with whether the bake still describes its inputs" do
    # It invalidates everything printed below it, so it is first. Acquisition rewrites the
    # lockfile and only a bake writes the row; that gap was real for weeks (rule 64).
    output = capture_io(fn -> Doctor.run([]) end)

    bake_at = :binary.match(output, "bake") |> elem(0)
    corpus_at = :binary.match(output, "corpus") |> elem(0)

    assert bake_at < corpus_at
  end
end
