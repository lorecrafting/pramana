defmodule Pramana.Acquire.SATTest do
  @moduledoc """
  Taishō 56–84 acquisition, in the parts that touch no network.

  The fetching itself is deliberately untested here — it talks to a university service this
  project has asked permission from and not yet received it. What is testable is everything
  that decides WHAT would be fetched, and that is where the errors would be silent.
  """
  use ExUnit.Case, async: true

  alias Pramana.Acquire.SAT

  describe "catalogue/1 — the gap, enumerated from a saved directory listing" do
    @tag :tmp_dir
    test "keeps only work numbers inside T2185–T2731", %{tmp_dir: dir} do
      # Shaped like SAT's Apache index: manifests for the whole Taishō, most of them
      # outside the gap. A filter that let T0001 through would send us fetching material
      # CBETA already holds.
      path = Path.join(dir, "index.html")

      File.write!(path, """
      <a href="1_1_manifest.json">1_1_manifest.json</a>
      <a href="2184_55_manifest.json">2184_55_manifest.json</a>
      <a href="2185_56_manifest.json">2185_56_manifest.json</a>
      <a href="2688_84_manifest.json">2688_84_manifest.json</a>
      <a href="2731_84_manifest.json">2731_84_manifest.json</a>
      <a href="2732_85_manifest.json">2732_85_manifest.json</a>
      """)

      assert {:ok, pairs} = SAT.catalogue(path)
      assert pairs == [{2185, 56}, {2688, 84}, {2731, 84}]
    end

    test "a missing index is an error, not an empty catalogue" do
      # An empty list here would read as "the gap is closed" and stop the fetch silently.
      assert {:error, :enoent} = SAT.catalogue("does/not/exist.html")
    end
  end

  describe "URLs" do
    test "a fascicle page is addressed by zero-padded page" do
      url = SAT.fascicle_url(2185, 56, 1)
      assert url =~ "useid=2185_56_0001"
      assert url =~ "satdb2018pre.php"
    end

    test "a manifest is addressed by work and volume" do
      assert SAT.manifest_url(2185, 56) =~ "/2185_56_manifest.json"
    end
  end

  describe "summarize_manifest/1" do
    test "pulls the title, byline and 部 division a missing work can be named by" do
      manifest = %{
        "label" => "立正安國論",
        "license" => "http://creativecommons.org/licenses/by-nc-sa/4.0/",
        "attribution" => "SAT Daizōkyō Text Database Committee",
        "metadata" => [
          %{"label" => "分類", "value" => "續諸宗部"},
          %{"label" => "Author", "value" => " 日蓮 撰"},
          %{"label" => "Translator", "value" => ""}
        ],
        "sequences" => [%{"canvases" => [%{}, %{}, %{}]}]
      }

      summary = SAT.summarize_manifest(manifest)

      assert summary.title == "立正安國論"

      # 續諸宗部, NOT 續經疏部 — the division that was wrong for 452 works until 2026-08-30.
      assert summary.division == "續諸宗部"
      assert summary.author == "日蓮 撰"
      assert summary.pages == 3
      # The IMAGES are non-commercial where the text is CC BY-SA. Different obligations.
      assert summary.license =~ "by-nc-sa"
    end

    test "a language-tagged value is unwrapped rather than inspected" do
      manifest = %{
        "label" => "x",
        "metadata" => [%{"label" => "分類", "value" => [%{"@value" => "悉曇部"}]}],
        "sequences" => [%{"canvases" => []}]
      }

      assert SAT.summarize_manifest(manifest).division == "悉曇部"
    end

    test "a manifest with no sequences reports zero pages rather than raising" do
      assert SAT.summarize_manifest(%{"label" => "x"}).pages == 0
    end
  end

  test "every request identifies itself with a contact address" do
    # A crawl that cannot be contacted is an anonymous one, and this project asked
    # permission before fetching anything.
    assert SAT.user_agent() =~ "@"
    assert SAT.user_agent() =~ "pramana"
  end

  test "gap_range/0 is the range the coverage caveat quotes" do
    assert SAT.gap_range() == 2185..2731
  end
end
