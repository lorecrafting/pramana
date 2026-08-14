defmodule Pramana.Bake.WorkerTest do
  @moduledoc """
  One Oban job per work is what buys fault isolation, resumability and bounded
  concurrency at 5,000 files. These tests check the properties that matters most: a
  bad file fails ONE job rather than the run, and re-running converges.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Bake.Worker
  alias Pramana.Corpus
  alias Pramana.Corpus.Segment
  alias Pramana.Repo

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title><author>鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body><milestone n="1" unit="juan"/>
  <lb n="0001c19"/>如是我聞：一時，佛住王舍城
  </body></text></TEI>
  """

  setup do
    root = Path.join(System.tmp_dir!(), "pramana-worker-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:pramana, :project_root)
    Application.put_env(:pramana, :project_root, root)

    on_exit(fn ->
      File.rm_rf!(root)
      if prev, do: Application.put_env(:pramana, :project_root, prev)
    end)

    write_raw = fn path, contents ->
      target = Path.join([root, "raw", "cbeta", path])
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, contents)
    end

    write_raw.("T/T09/T09n0262.xml", @xml)
    %{root: root, write_raw: write_raw}
  end

  # Invoke the worker directly rather than through Oban.Testing.perform_job/2, whose
  # signature changed in Oban 2.23. What these tests exercise is the worker's logic,
  # not Oban's dispatch, so going straight at it is both stabler and more honest.
  defp run(args), do: Worker.perform(%Oban.Job{args: args})

  defp args(overrides \\ %{}) do
    Map.merge(
      %{
        "source" => "cbeta",
        "canon" => "T",
        "volume" => 9,
        "number" => "0262",
        "work_id" => "T0262"
      },
      overrides
    )
  end

  describe "perform/1" do
    test "bakes a work and reports how many segments it produced" do
      assert {:ok, %{work_id: "T0262", segments: 1}} =
               run(args())

      assert {:ok, span} = Corpus.resolve("pramana:cbeta.T:T0262_001@p0001c19")
      assert span.content == "如是我聞：一時，佛住王舍城"
    end

    test "applies the Taishō volume provenance rule", %{write_raw: write_raw} do
      # Vols 56-84 are mechanically Japanese-composed commentary.
      write_raw.("T/T84/T84n2688.xml", @xml)

      assert {:ok, _} =
               run(args(%{"volume" => 84, "number" => "2688", "work_id" => "T2688"}))

      work = Repo.get!(Pramana.Corpus.Work, "T2688")
      assert work.composition_origin == "japanese"
      assert work.text_role == "commentary"
    end

    test "leaves provenance null for volumes needing catalogue data" do
      assert {:ok, _} = run(args())
      work = Repo.get!(Pramana.Corpus.Work, "T0262")

      # Vol 9 is Indic translations AND Chinese compositions; guessing would be worse
      # than a gap, so the rule declines.
      assert work.composition_origin == nil
    end

    test "is idempotent — re-running converges rather than duplicating" do
      {:ok, _} = run(args())
      count = Repo.aggregate(Segment, :count)

      {:ok, _} = run(args())
      assert Repo.aggregate(Segment, :count) == count
    end
  end

  describe "fault isolation" do
    test "a missing raw file fails the job, not the run" do
      assert {:error, {:raw_unreadable, _path, :enoent}} =
               run(args(%{"number" => "9999", "work_id" => "T9999"}))
    end

    test "a malformed TEI file fails only its own job", %{write_raw: write_raw} do
      write_raw.("T/T09/T09n0263.xml", "<TEI><text><body>unclosed")

      assert {:error, _} =
               run(args(%{"number" => "0263", "work_id" => "T0263"}))

      # The good work still bakes afterwards.
      assert {:ok, %{work_id: "T0262"}} = run(args())
    end

    test "an unregistered source is rejected" do
      assert {:error, :unsupported_source} =
               run(args(%{"source" => "nope"}))
    end
  end

  describe "args/2" do
    test "builds job args from a catalog entry" do
      entry = %{canon: "T", volume: 9, number: "0262", work_id: "T0262"}

      assert Worker.args("cbeta", entry) == %{
               "source" => "cbeta",
               "canon" => "T",
               "volume" => 9,
               "number" => "0262",
               "work_id" => "T0262"
             }
    end
  end
end
