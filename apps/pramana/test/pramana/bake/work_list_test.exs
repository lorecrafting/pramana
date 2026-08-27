defmodule Pramana.Bake.WorkListTest do
  @moduledoc """
  The lockfile lists FILES; the bake needs WORKS. Conflating the two lost six CBETA X
  works half of themselves, and no check downstream could see it: each survivor
  re-derived byte-identically from the one file it recorded.
  """
  use ExUnit.Case, async: false

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake.WorkList
  alias Pramana.Sources

  setup do
    root = Path.join(System.tmp_dir!(), "pramana-worklist-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:pramana, :project_root)
    Application.put_env(:pramana, :project_root, root)

    on_exit(fn ->
      File.rm_rf!(root)
      if prev, do: Application.put_env(:pramana, :project_root, prev)
    end)

    :ok
  end

  defp lock!(paths) do
    {:ok, source} = Sources.fetch("cbeta")

    files = Enum.map(paths, &%{path: &1, sha256: String.duplicate("a", 64), bytes: 1})

    Lockfile.put_source(Lockfile.build_entry(source, files: files, pin: "test"))
  end

  describe "from_lockfile/2" do
    test "one file per work is one job per work" do
      lock!(["T/T09/T09n0262.xml", "T/T01/T01n0001.xml"])

      assert [
               %{work_id: "T0001", volumes: [1], canon: "T", number: "0001"},
               %{work_id: "T0262", volumes: [9]}
             ] = WorkList.from_lockfile("cbeta", nil)
    end

    # X0240 is in X08 and X09 under ONE number. The Taishō never shows this because
    # CBETA gives its split works distinct ids (T0220a, T0220b).
    test "a work spread over two volume files is ONE work, in printed order" do
      lock!(["X/X09/X09n0240.xml", "X/X08/X08n0240.xml"])

      assert [%{work_id: "X0240", volumes: [8, 9]}] = WorkList.from_lockfile("cbeta", nil)
    end

    test "restricts to one canon when asked" do
      lock!(["T/T09/T09n0262.xml", "X/X08/X08n0240.xml"])

      assert [%{work_id: "X0240"}] = WorkList.from_lockfile("cbeta", "X")
    end

    test "ignores paths that are not a canon/volume/work file" do
      lock!(["T/T09/T09n0262.xml", "README.md", "T/notes.txt"])

      assert [%{work_id: "T0262"}] = WorkList.from_lockfile("cbeta", nil)
    end
  end

  describe "census/2" do
    test "states files against works, and names the works that span volumes" do
      lock!([
        "T/T09/T09n0262.xml",
        "X/X08/X08n0240.xml",
        "X/X09/X09n0240.xml"
      ])

      census = WorkList.census("cbeta", nil)

      assert census.files == 3
      assert census.works == 2
      assert [%{work_id: "X0240", volumes: [8, 9]}] = census.multi_volume
    end

    test "reports no spanning works when every work is one file" do
      lock!(["T/T09/T09n0262.xml"])

      assert %{files: 1, works: 1, multi_volume: []} = WorkList.census("cbeta", nil)
    end
  end

  describe "find/2" do
    test "finds a work and every volume it occupies" do
      lock!(["X/X81/X81n1571.xml", "X/X82/X82n1571.xml"])

      assert %{work_id: "X1571", canon: "X", volumes: [81, 82]} =
               WorkList.find("cbeta", "X1571")
    end

    test "is nil for a work the lockfile has never heard of" do
      lock!(["T/T09/T09n0262.xml"])

      assert WorkList.find("cbeta", "X9999") == nil
    end
  end
end
