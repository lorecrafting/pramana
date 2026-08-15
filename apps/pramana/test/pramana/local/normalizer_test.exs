defmodule Pramana.Local.NormalizerTest do
  @moduledoc """
  Normalizing and segmenting a page-anchored local text.

  The running-head rule is the dangerous part. About half the pages of the real test
  source repeat the book title and page number as a running head; leaving them in makes
  every one of those pages match a search for the title, and stripping them carelessly
  deletes content — page 837 of that book opens `九九、往生要集 … 一○○、本源清淨大圓鏡`,
  where `一○○` is a **list number**, not a page number.
  """
  use ExUnit.Case, async: true

  alias Pramana.Local.Manifest
  alias Pramana.Local.Normalizer
  alias Pramana.Normalize.IR
  alias Pramana.Segment.Page

  @title "測試經解"

  setup do
    dir = Path.join(System.tmp_dir!(), "pramana-local-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "text"))
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp page!(dir, name, contents), do: File.write!(Path.join([dir, "text", name]), contents)

  defp manifest!(dir, overrides \\ %{}) do
    base = %{
      "id" => "test-text",
      "title" => @title,
      "format" => "text",
      "provenance" => %{"composition_origin" => "chinese", "text_role" => "commentary"},
      "citation" => %{"addressing" => "edition_page", "anchor_source" => "printed page numbers"}
    }

    {:ok, manifest} = Manifest.validate(Map.merge(base, overrides), dir)
    manifest
  end

  defp normalize!(dir, overrides \\ %{}) do
    manifest = manifest!(dir, overrides)
    {:ok, ir} = Normalizer.normalize(dir, manifest: manifest)
    {ir, manifest}
  end

  describe "page anchors" do
    test "one segment per page, anchored to the printed page number", %{dir: dir} do
      page!(dir, "0001.txt", "第一頁內容")
      page!(dir, "0002.txt", "第二頁內容")

      {ir, _} = normalize!(dir)
      {:ok, segments} = Page.segments(ir, source: "local-test", witness: "ed")

      assert Enum.map(segments, & &1.urn) == [
               "pramana:local-test.ed:test-text@p0001",
               "pramana:local-test.ed:test-text@p0002"
             ]
    end

    test "front matter keeps its own numbering sequence", %{dir: dir} do
      # A book that restarts numbering for its contents and preface has three page-1s.
      # Renumbering them into one run would produce references matching no printed page.
      page!(dir, "0001.txt", "本文")
      page!(dir, "toc-0001.txt", "目錄")
      page!(dir, "pref-0001.txt", "序")

      {ir, _} = normalize!(dir)
      {:ok, segments} = Page.segments(ir, source: "local-test", witness: "ed")

      locators = Enum.map(segments, &(String.split(&1.urn, "@") |> List.last()))
      assert "p0001" in locators
      assert "ptoc-0001" in locators
      assert "ppref-0001" in locators
      assert length(Enum.uniq(locators)) == 3
    end

    test "offsets slice each segment's exact content out of the body", %{dir: dir} do
      page!(dir, "0001.txt", "第一頁內容")
      page!(dir, "0002.txt", "第二頁比較長的內容在這裡")

      {ir, _} = normalize!(dir)
      {:ok, segments} = Page.segments(ir, source: "local-test", witness: "ed")
      body = IR.body(ir)

      for s <- segments do
        assert String.slice(body, s.char_start, s.char_end - s.char_start) == s.content
      end
    end
  end

  describe "running heads" do
    test "a head of title plus page number is stripped", %{dir: dir} do
      page!(dir, "0100.txt", "#{@title}            一○○\n正文開始")

      {ir, _} = normalize!(dir)
      assert [%{text: "正文開始"}] = ir.lines
    end

    test "handles ○ (U+25CB) as zero, which is how the book writes it", %{dir: dir} do
      # NOT 〇 (U+3007). Confusing the two silently mis-cut ~158 of 837 pages in the
      # source project's first extraction pass.
      page!(dir, "0500.txt", "#{@title}           五○○\n內容")

      {ir, _} = normalize!(dir)
      assert [%{text: "內容"}] = ir.lines
    end

    test "does NOT strip a first line that merely contains numerals", %{dir: dir} do
      # The real page 837 case: a list whose items are numbered in the same style.
      content = "九九、往生要集                  一○○、本源清淨大圓鏡"
      page!(dir, "0837.txt", content)

      {ir, _} = normalize!(dir)
      assert [%{text: ^content}] = ir.lines
    end

    test "does NOT strip a first line that is ordinary content", %{dir: dir} do
      page!(dir, "0003.txt", "即眾生本具之化儀。此一句佛號")

      {ir, _} = normalize!(dir)
      assert [%{text: "即眾生本具之化儀。此一句佛號"}] = ir.lines
    end

    test "reports how many heads it stripped", %{dir: dir} do
      # A silent change to hundreds of pages is exactly what should not be silent.
      page!(dir, "0001.txt", "#{@title} 一\n甲")
      page!(dir, "0002.txt", "乙")
      page!(dir, "0003.txt", "#{@title} 三\n丙")

      {_ir, manifest} = normalize!(dir)
      assert Normalizer.stripped_running_heads(dir, manifest) == 2
    end
  end

  describe "pages with nothing on them" do
    test "a page that is only a running head yields no segment", %{dir: dir} do
      page!(dir, "0001.txt", "甲")
      page!(dir, "0380.txt", "#{@title}            三八○")

      {ir, _} = normalize!(dir)
      {:ok, segments} = Page.segments(ir, source: "local-test", witness: "ed")

      assert length(ir.lines) == 2
      assert length(segments) == 1
    end

    test "a skipped page still consumes its position, so offsets stay correct", %{dir: dir} do
      page!(dir, "0001.txt", "甲")
      page!(dir, "0002.txt", "#{@title} 二")
      page!(dir, "0003.txt", "丙")

      {ir, _} = normalize!(dir)
      {:ok, segments} = Page.segments(ir, source: "local-test", witness: "ed")
      body = IR.body(ir)

      for s <- segments do
        assert String.slice(body, s.char_start, s.char_end - s.char_start) == s.content
      end

      assert Enum.map(segments, & &1.ordinal) == [0, 1]
    end
  end

  describe "metadata carried onto the text" do
    test "witness and work ids come from the manifest when declared", %{dir: dir} do
      page!(dir, "0001.txt", "甲")

      citation = %{
        "addressing" => "edition_page",
        "anchor_source" => "printed page numbers",
        "witness_id" => "1990-cn",
        "work_id" => "jie"
      }

      {ir, _} = normalize!(dir, %{"citation" => citation})
      {:ok, [segment]} = Page.segments(ir, source: "local-test", witness: ir.canon)

      assert segment.urn == "pramana:local-test.1990-cn:jie@p0001"
    end

    test "content hashes cover the segment text exactly", %{dir: dir} do
      page!(dir, "0001.txt", "甲乙丙")

      {ir, _} = normalize!(dir)
      {:ok, [segment]} = Page.segments(ir, source: "local-test", witness: "ed")

      expected = :crypto.hash(:sha256, "甲乙丙") |> Base.encode16(case: :lower)
      assert segment.content_sha256 == expected
    end
  end
end
