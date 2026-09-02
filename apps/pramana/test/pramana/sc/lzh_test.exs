defmodule Pramana.Sc.LzhTest do
  @moduledoc """
  Anchoring SuttaCentral's Chinese to the Taishō lines this corpus holds.

  The failure to design against is not a crash. It is an English rendering stored
  against a **plausible but wrong** Chinese line: nothing downstream would catch it, the
  citation would resolve, the passage would look like scripture, and a reader following
  it would be told the Buddha said something he did not say here. So the tests are about
  where a segment lands, not about how many land.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Sc.Lzh

  # A miniature T0099: two suttas, each printed under its own number, and both containing
  # the same stock opening — which is the whole reason the sutta number has to do the
  # locating rather than the text.
  @lines [
    "雜阿含經卷第一",
    "（一）如是我聞：一時，佛住舍衛國祇樹給孤",
    "獨園。爾時，世尊告諸比丘：「當觀色無常。」",
    "（二）如是我聞：一時，佛住舍衛國祇樹給孤",
    "獨園。爾時，世尊告諸比丘：「於色當正思惟。」"
  ]

  setup do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      tradition: "chinese",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Witness{id: "T", name: "Taishō"})
    Repo.insert!(%Work{id: "T0099", title: "雜阿含經"})

    text =
      Repo.insert!(%Text{
        work_id: "T0099",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T0099",
        body: Enum.join(@lines, "\n"),
        body_sha256: "x",
        meta: %{}
      })

    for {content, i} <- Enum.with_index(@lines) do
      Repo.insert!(%Segment{
        text_id: text.id,
        urn: "pramana:cbeta.T:T0099_001@p0001a#{String.pad_leading("#{i + 1}", 2, "0")}",
        ordinal: i,
        content: content,
        content_sha256: "h#{i}",
        char_start: 0,
        char_end: String.length(content),
        meta: %{}
      })
    end

    {:ok, index} = Lzh.index("T0099")
    %{index: index}
  end

  defp write!(dir, uid, segments) do
    path = Path.join(dir, "#{uid}_root-lzh-sct.json")
    File.write!(path, Jason.encode!(segments))
    path
  end

  describe "the sutta number, not the text, decides where a segment may match" do
    @tag :tmp_dir
    test "a stock opening anchors inside its own sutta", %{index: index, tmp_dir: dir} do
      # `如是我聞：一時，佛住舍衛國祇樹給孤獨園` opens BOTH suttas here and opens most of
      # the Saṃyukta Āgama. Searching the work for it finds sutta one; this is sutta two.
      path =
        write!(dir, "sa2", %{
          "sa2:0.1" => "雜阿含經",
          "sa2:1.1" => "如是我聞。",
          "sa2:1.2" => "一時，佛住舍衛國祇樹給孤獨園。",
          "sa2:2.1" => "爾時，世尊告諸比丘：「於色當正思惟。」"
        })

      {:ok, placed, _counts} = Lzh.align_file(path, index)

      assert %{urn: urn} = placed["sa2:1.2"]
      assert urn =~ "p0001a04"
      refute urn =~ "p0001a02"
    end

    @tag :tmp_dir
    test "a sutta this text does not print is refused, not placed nearby", %{
      index: index,
      tmp_dir: dir
    } do
      path = write!(dir, "sa999", %{"sa999:1.1" => "如是我聞。"})

      assert {:error, {:no_marker, "九九九"}} = Lzh.align_file(path, index)
    end

    test "the window rests on every number being printed once", %{index: index} do
      assert Lzh.unique_markers?("T0099")
      assert {:ok, {_from, _to}} = Lzh.window(index, 1)
    end
  end

  describe "two editions of one text" do
    @tag :tmp_dir
    test "SAT's Han forms and its own punctuation still match CBETA's", %{
      index: index,
      tmp_dir: dir
    } do
      # `(一)` against CBETA's `（一）`, no `：` or `「」`, and 衞 for 衛 — every difference
      # here is the editor's rather than the text's.
      path =
        write!(dir, "sa1", %{
          "sa1:1.1" => "(一)如是我聞",
          "sa1:1.2" => "一時佛住舍衞國祇樹給孤獨園"
        })

      {:ok, placed, counts} = Lzh.align_file(path, index)

      assert counts.exact >= 1
      assert %{method: :exact} = placed["sa1:1.1"]
    end

    @tag :tmp_dir
    test "a segment the editions disagree on is bounded by its neighbours, and says so", %{
      index: index,
      tmp_dir: dir
    } do
      path =
        write!(dir, "sa1", %{
          "sa1:1.1" => "如是我聞",
          "sa1:1.2" => "此句兩本互異全然不同",
          "sa1:1.3" => "爾時，世尊告諸比丘"
        })

      {:ok, placed, counts} = Lzh.align_file(path, index)

      assert counts.interpolated == 1
      assert %{method: :interpolated} = placed["sa1:1.2"]
      assert %{method: :exact} = placed["sa1:1.1"]
    end
  end

  describe "the anchor that is handed to a rendering" do
    @tag :tmp_dir
    test "a passage crossing a printed line becomes a range", %{index: index, tmp_dir: dir} do
      path = write!(dir, "sa1", %{"sa1:1.1" => "佛住舍衛國祇樹給孤獨園"})

      {:ok, placed, _} = Lzh.align_file(path, index)

      assert %{urn: urn, ordinal_start: 1, ordinal_end: 2} = placed["sa1:1.1"]
      assert urn == "pramana:cbeta.T:T0099_001@p0001a02-p0001a03"
    end

    @tag :tmp_dir
    test "the translation's own headings are never anchored", %{index: index, tmp_dir: dir} do
      path = write!(dir, "sa1", %{"sa1:0.1" => "雜阿含經", "sa1:1.1" => "如是我聞"})

      {:ok, placed, _} = Lzh.align_file(path, index)

      refute Map.has_key?(placed, "sa1:0.1")
      assert Map.has_key?(placed, "sa1:1.1")
    end
  end

  test "a work in no anchorable collection is counted rather than guessed at" do
    {anchors, report} = Lzh.anchors(root: "test/fixtures/does-not-exist")

    assert anchors == %{}
    assert report.works_seen == 0
  end
end
