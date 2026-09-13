defmodule Pramana.Bake.WorkerTest do
  @moduledoc """
  One Oban job per work is what buys fault isolation, resumability and bounded
  concurrency at 5,000 files. These tests check the properties that matters most: a
  bad file fails ONE job rather than the run, and re-running converges.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Bake.Worker
  alias Pramana.Corpus
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
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

      if prev,
        do: Application.put_env(:pramana, :project_root, prev),
        else: Application.delete_env(:pramana, :project_root)
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

  # Paths are DERIVED here from whatever the test overrode, the way `Bake.WorkList` derives
  # them from the lockfile — so a test that changes the work number does not silently keep
  # pointing at T0262's file.
  defp args(overrides \\ %{}) do
    base = %{
      "source" => "cbeta",
      "canon" => "T",
      "volume" => 9,
      "number" => "0262",
      "work_id" => "T0262"
    }

    merged = Map.merge(base, overrides)

    Map.put_new_lazy(merged, "paths", fn ->
      canon = merged["canon"]
      volumes = merged["volumes"] || [merged["volume"]]

      for v <- volumes do
        vol = v |> Integer.to_string() |> String.pad_leading(2, "0")
        "#{canon}/#{canon}#{vol}/#{canon}#{vol}n#{merged["number"]}.xml"
      end
    end)
  end

  describe "perform/1" do
    test "bakes a work and reports how many segments it produced" do
      assert {:ok, %{work_id: "T0262", segments: 1}} =
               run(args())

      assert {:ok, span} = Corpus.resolve("pramana:cbeta.T:T0262_001@p0001c19")
      assert span.content == "如是我聞：一時，佛住王舍城"
    end

    test "applies the Taishō volume provenance rule", %{write_raw: write_raw} do
      # T2688 is 立正安國論, Nichiren's *Risshō Ankoku Ron* — 續諸宗部, the writings of the
      # Japanese schools. This test asserted `text_role: "commentary"` until 2026-08-30,
      # because one table row covered T2185–T2700 as 續經疏部 sub-commentaries. Filing the
      # founding treatise of a school as commentary on someone else's text is the shape of
      # error invariant #4 exists to prevent, and it sat in a passing test.
      write_raw.("T/T84/T84n2688.xml", @xml)

      assert {:ok, _} =
               run(args(%{"volume" => 84, "number" => "2688", "work_id" => "T2688"}))

      work = Repo.get!(Pramana.Corpus.Work, "T2688")
      assert work.composition_origin == "japanese"
      assert work.text_role == "treatise"
    end

    test "assigns division-based provenance during the bake" do
      assert {:ok, _} = run(args())
      work = Repo.get!(Pramana.Corpus.Work, "T0262")

      # T0262 is 法華部. Provenance comes from the DIVISION table, applied during the
      # bake rather than by a later pass — see the convergence test below for why.
      assert work.division == "法華部"
      assert work.composition_origin == "indic"
      assert work.text_role == "root"
    end

    test "re-baking CONVERGES on provenance rather than undoing it" do
      # The loader replaces work attributes on conflict, so if the bake computed weaker
      # provenance than some later backfill, a routine re-bake would silently erase it.
      # One source of truth (the division table), applied in the bake, prevents that.
      {:ok, _} = run(args())
      before = Repo.get!(Pramana.Corpus.Work, "T0262")

      {:ok, _} = run(args())
      after_rebake = Repo.get!(Pramana.Corpus.Work, "T0262")

      assert after_rebake.composition_origin == before.composition_origin
      assert after_rebake.text_role == before.text_role
      assert after_rebake.division == before.division
      refute is_nil(after_rebake.composition_origin)
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
               run(args(%{"source" => "nope", "paths" => ["T/T09/T09n0262.xml"]}))
    end
  end

  # A volume is a unit of printing; a work is the unit of loading. CBETA's X collection
  # reuses one work number across two volume files six times over, and because
  # `Loader.load/2` REPLACES a work's segments, a job per file meant the second volume
  # erased the first with nothing reported. These pin the assembled shape.
  describe "a work that spans printed volumes" do
    @vol_one """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt>
      <title level="m" xml:lang="zh-Hant">卍續藏之作</title><author>唐 某甲撰</author>
    </titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>
    <lb n="0402c01" ed="X"/>第一卷之文
    </body></text></TEI>
    """

    # Page numbering RESTARTS at each volume, so this repeats an anchor the first volume
    # already used — 22,616 of X1571's anchors do exactly this. The juan is what keeps
    # the two URNs apart.
    @vol_two """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt>
      <title level="m" xml:lang="zh-Hant">卍續藏之作</title><author>唐 某甲撰</author>
    </titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="2" unit="juan"/>
    <lb n="0402c01" ed="X"/>第二卷之文
    </body></text></TEI>
    """

    setup %{write_raw: write_raw} do
      write_raw.("X/X81/X81n1571.xml", @vol_one)
      write_raw.("X/X82/X82n1571.xml", @vol_two)

      %{
        spanning:
          args(%{
            "canon" => "X",
            "volumes" => [81, 82],
            "number" => "1571",
            "work_id" => "X1571"
          })
      }
    end

    test "keeps both volumes instead of the last one to finish", %{spanning: spanning} do
      assert {:ok, %{work_id: "X1571", segments: 2}} = run(spanning)

      assert {:ok, first} = Corpus.resolve("pramana:cbeta.X:X1571_001@p0402c01")
      assert {:ok, second} = Corpus.resolve("pramana:cbeta.X:X1571_002@p0402c01")

      assert first.content == "第一卷之文"
      assert second.content == "第二卷之文"
    end

    test "records which volume each repeated anchor belongs to", %{spanning: spanning} do
      {:ok, _} = run(spanning)

      volumes =
        Repo.all(from s in Segment, order_by: s.ordinal, select: s.meta["volume"])

      # The URN is unique because it carries the juan, but `p0402c01` alone names two
      # different printed lines and a reader checking against the print needs the volume.
      assert volumes == [81, 82]
    end

    test "labels the text by its span, and records the files to re-derive it from",
         %{spanning: spanning} do
      {:ok, _} = run(spanning)

      text = Repo.one!(from t in Text, where: t.work_id == "X1571")

      assert text.volume == "81-82"
      assert text.meta["volumes"] == [81, 82]
      assert text.meta["source_file"] =~ "X81n1571.xml"
      assert text.meta["source_file"] =~ "X82n1571.xml"
    end

    test "a single-volume work carries no volume on its lines" do
      {:ok, _} = run(args())

      assert Repo.all(from s in Segment, select: s.meta["volume"]) == [nil]
      assert Repo.one!(from t in Text, where: t.work_id == "T0262").volume == "9"
    end

    test "a job enqueued by an older run, carrying one volume, still runs" do
      assert {:ok, %{work_id: "T0262", segments: 1}} = run(args(%{"volume" => 9}))
    end

    # A job enqueued before paths were carried has to rebuild one, and the rebuild is
    # right for T. It is NOT right for A, P, L or U, whose volume directories are three
    # digits — which is why paths are carried now rather than reconstructed.
    test "a job with no paths falls back to reconstruction rather than failing" do
      args = args() |> Map.delete("paths")

      assert {:ok, %{work_id: "T0262", segments: 1}} = run(args)
    end
  end

  describe "args/2" do
    test "builds job args from a catalog entry" do
      entry = %{
        canon: "T",
        volumes: [9],
        number: "0262",
        work_id: "T0262",
        paths: ["T/T09/T09n0262.xml"]
      }

      assert Worker.args("cbeta", entry) == %{
               "source" => "cbeta",
               "canon" => "T",
               "volumes" => [9],
               # CARRIED, not rebuilt. `work_path/3` pads the volume to two digits and the
               # width belongs to the edition — A, P, L and U use three — so rebuilding
               # `A/A091/...` from volume 91 yields `A/A91/...`, which does not exist.
               "paths" => ["T/T09/T09n0262.xml"],
               "number" => "0262",
               "work_id" => "T0262"
             }
    end
  end
end
