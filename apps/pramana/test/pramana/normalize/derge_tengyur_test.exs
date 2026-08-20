defmodule Pramana.Normalize.DergeTengyurTest do
  @moduledoc """
  The Tengyur's annotated plain text.

  Every test here is about the same rule: **what the woodblock prints is what enters the
  text**. The editors' corrections, modern spellings and note markers are real and are
  recorded — beside the printed reading, never in place of it. A normalizer that accepted
  the corrections would produce a text no edition contains, and every citation into it
  would still resolve.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.DergeTengyur, as: Tengyur

  defp volume(lines), do: Enum.join(lines, "\n")

  describe "the anchor" do
    test "folio and line are read from the head of each line" do
      {:ok, [ir], _} =
        volume(["[1b]", "[1b.1]{D1109}first", "[1b.2]second"])
        |> Tengyur.normalize_file(volume: 1)

      assert Enum.map(ir.lines, & &1.anchor) == ["1.1b.1", "1.1b.2"]
      assert Enum.map(ir.lines, & &1.text) == ["first", "second"]
    end

    test "a folio header carries no text and is not a line" do
      # `[1b]` alone announces the leaf; the lines that follow carry their own anchors.
      {:ok, [ir], _} =
        volume(["[1b]", "[1b.1]{D1109}only line"]) |> Tengyur.normalize_file(volume: 1)

      assert length(ir.lines) == 1
    end

    test "an inserted leaf keeps the x the edition prints" do
      {:ok, [ir], _} =
        volume(["[355xb.7]{D1109}on the inserted leaf"]) |> Tengyur.normalize_file(volume: 102)

      assert [%{anchor: "102.355xb.7"}] = ir.lines
    end

    test "a line printed twice under one address is marked, not merged" do
      {:ok, [ir], _} =
        volume(["[39b.6]{D1109}first", "[39b.6]second"]) |> Tengyur.normalize_file(volume: 7)

      assert Enum.map(ir.lines, & &1.anchor) == ["7.39b.6", "7.39b.6+2"]
    end
  end

  describe "where a work begins" do
    test "a {D…} marker starts a work" do
      {:ok, irs, _} =
        volume(["[1b.1]{D1109}first work", "[2a.1]{D1110}second work"])
        |> Tengyur.normalize_file(volume: 1)

      assert Enum.map(irs, & &1.work_id) == ["toh1109", "toh1110"]
    end

    test "a marker part-way through a line splits it, and both halves keep the address" do
      # The page prints one line; two works meet on it. They are told apart by the work in
      # the URN, exactly as in the Kangyur.
      {:ok, irs, _} =
        volume(["[1b.1]{D1109}end of one{D1110}start of the next"])
        |> Tengyur.normalize_file(volume: 1)

      texts = Map.new(irs, &{&1.work_id, Enum.map(&1.lines, fn l -> {l.anchor, l.text} end)})

      assert texts["toh1109"] == [{"1.1b.1", "end of one"}]
      assert texts["toh1110"] == [{"1.1b.1", "start of the next"}]
    end

    test "a work in progress carries into the next volume" do
      # 33 Tengyur works span volumes, and only the first says which work it is.
      {:ok, [ir], continuing} =
        volume(["[1a.1]continues from the volume before"])
        |> Tengyur.normalize_file(volume: 121, continuing: "toh4017")

      assert ir.work_id == "toh4017"
      assert continuing == "toh4017"
    end

    test "a letter suffix is a real work, not a malformed number" do
      # rKTs writes a text absent from the Tōhoku catalogue as the preceding number with a
      # letter: D7, D7a, D8.
      {:ok, [ir], _} = volume(["[1b.1]{D1109a}a text"]) |> Tengyur.normalize_file(volume: 1)

      assert ir.work_id == "toh1109a"
    end
  end

  describe "what the editors added" do
    test "a modern spelling is recorded beside the archaic one, not instead of it" do
      {:ok, [ir], _} =
        volume(["[1b.1]{D1109}མཁའ་ལ་{མི་,མེ་}ཏོག"]) |> Tengyur.normalize_file(volume: 1)

      [line] = ir.lines
      assert line.text == "མཁའ་ལ་མི་ཏོག"

      assert [%{"lem" => "མི་", "kind" => "modern_spelling", "rdgs" => [%{"text" => "མེ་"}]}] =
               line.apparatus
    end

    test "a suggested correction is recorded beside the printed reading" do
      {:ok, [ir], _} =
        volume(["[1b.1]{D1109}ངང་ཚུལ་(བཟད་,བཟང་)པོ"]) |> Tengyur.normalize_file(volume: 1)

      [line] = ir.lines
      assert line.text == "ངང་ཚུལ་བཟད་པོ"
      assert [%{"lem" => "བཟད་", "kind" => "correction"}] = line.apparatus
    end

    test "a Pedurma note mark leaves the text but is counted" do
      # `#` is not Tibetan and would end up inside a quoted passage. Removing it silently
      # is how a normalizer loses something nobody can check.
      {:ok, [ir], _} = volume(["[1b.1]{D1109}ཆོས#གསལ#"]) |> Tengyur.normalize_file(volume: 1)

      [line] = ir.lines
      assert line.text == "ཆོསགསལ"
      assert Enum.count(line.apparatus, &(&1["kind"] == "pedurma_note")) == 2
    end

    test "extract/1 separates the page from what is said about it" do
      assert {"ཆོས", [%{"kind" => "pedurma_note"}]} = Tengyur.extract("ཆོས#")
      assert {"", []} = Tengyur.extract("   ")
    end
  end

  describe "volumes_at/1" do
    setup do
      root = Path.join(System.tmp_dir!(), "tengyur-#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "the volume number comes from the filename, which is where it is", %{root: root} do
      File.write!(Path.join(root, "001_བསྟོད་ཚོགས།_ཀ.txt"), "[1b.1]{D1109}x")
      File.write!(Path.join(root, "002_རྒྱུད་འགྲེལ།_ཀ.txt"), "[1b.1]{D1110}y")

      assert {:ok, [{1, _}, {2, _}]} = Tengyur.volumes_at(root)
    end

    test "a gap is refused rather than renumbered", %{root: root} do
      File.write!(Path.join(root, "001_a.txt"), "x")
      File.write!(Path.join(root, "003_c.txt"), "y")

      # Two files numbered 1 and 3: volume 2 is the one that is not there, and a walk
      # over 1 then 3 would thread a continuation across a volume it never read.
      assert {:error, {:volumes_not_contiguous, [2], _}} = Tengyur.volumes_at(root)
    end

    test "an empty directory says so", %{root: root} do
      assert {:error, {:no_volumes_at, ^root}} = Tengyur.volumes_at(root)
    end
  end
end
