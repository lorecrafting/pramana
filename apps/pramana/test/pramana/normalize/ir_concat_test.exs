defmodule Pramana.Normalize.IRConcatTest do
  @moduledoc """
  Assembling a work from the printed volumes it runs across.

  The bug this prevents is not "a text is short". It is that a work arriving as two
  files became two bake jobs, each loading the same work id, and `Loader.load/2`
  replaces a work's segments — so the second job erased the first and the survivor
  still resolved, still verified against the file it recorded, and still reported a
  plausible length. Which volume survived depended on which job finished last.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.IR
  alias Pramana.Normalize.IR.Line

  defp part(volume, juan, anchors) do
    %IR{
      work_id: "X1571",
      canon: "X",
      volume: volume,
      title: "卍續藏之作",
      author: "唐 某甲撰",
      juan_count: 1,
      gaiji: %{"CB#{volume}" => %{}},
      unanchored_apparatus: [%{volume: volume}],
      outline: [%{title: "卷#{juan}", juan: juan}],
      lines:
        Enum.map(anchors, fn anchor ->
          %Line{anchor: anchor, juan: juan, text: "第#{volume}冊#{anchor}"}
        end)
    }
  end

  test "one part is returned untouched, and carries no volume on its lines" do
    only = part(81, 1, ["0402c01"])

    assert IR.concat([only]) == only
    assert only.volumes == []
    assert Enum.all?(only.lines, &is_nil(&1.volume))
  end

  test "concatenates in the order given, which is printed order" do
    assembled = IR.concat([part(81, 1, ["0402c01", "0402c02"]), part(82, 2, ["0001a01"])])

    assert Enum.map(assembled.lines, & &1.anchor) == ["0402c01", "0402c02", "0001a01"]
    assert assembled.volumes == [81, 82]
    assert IR.body(assembled) == "第81冊0402c01\n第81冊0402c02\n第82冊0001a01"
  end

  # X1571's two volumes share 22,616 page/register/line anchors, because page numbering
  # restarts at each volume. The URN survives that — it carries the juan — but the
  # printed locator does not, so the line has to say which volume it is from.
  test "stamps each line with the volume it was printed in" do
    assembled = IR.concat([part(81, 1, ["0402c01"]), part(82, 50, ["0402c01"])])

    assert Enum.map(assembled.lines, &{&1.volume, &1.anchor}) == [
             {81, "0402c01"},
             {82, "0402c01"}
           ]
  end

  test "merges gaiji, apparatus and outline rather than keeping the first part's" do
    assembled = IR.concat([part(81, 1, ["0402c01"]), part(82, 2, ["0001a01"])])

    assert Map.keys(assembled.gaiji) |> Enum.sort() == ["CB81", "CB82"]
    assert length(assembled.unanchored_apparatus) == 2
    assert Enum.map(assembled.outline, & &1.juan) == [1, 2]
  end

  # X0714's juan 3 appears in BOTH its volume files, so summing each part's count
  # reports a 4-fascicle work as having 5.
  test "counts fascicles across the join instead of summing the parts" do
    assembled =
      IR.concat([
        part(39, 3, ["0900a01"]),
        part(40, 3, ["0001a01"])
      ])

    assert assembled.juan_count == 1

    continuing = IR.concat([part(8, 44, ["0896b11"]), part(9, 45, ["0001a01"])])
    assert continuing.juan_count == 2
  end

  test "refuses to assemble parts belonging to different works" do
    other = %{part(82, 2, ["0001a01"]) | work_id: "X1568"}

    assert_raise ArgumentError, ~r/grouped unrelated files/, fn ->
      IR.concat([part(81, 1, ["0402c01"]), other])
    end
  end

  describe "Line.blank?/1" do
    test "a line with no content is blank" do
      line = %Line{anchor: "0001a01", text: ""}
      assert Line.blank?(line)
    end

    test "a line with text is not blank" do
      line = %Line{anchor: "0001a01", text: "如是我聞"}
      refute Line.blank?(line)
    end

    test "a line with only inline notes is not blank (pipeline v2)" do
      line = %Line{anchor: "0001a01", text: "", notes: ["某氏註"]}
      refute Line.blank?(line)
    end

    test "a line with only apparatus is not blank (pipeline v3)" do
      line = %Line{anchor: "0001a01", text: "", apparatus: [%{choice: "甲"}]}
      refute Line.blank?(line)
    end

    test "a line with only gaiji is not blank (pipeline v4)" do
      line = %Line{anchor: "0001a01", text: "", gaiji: ["CB00001"]}
      refute Line.blank?(line)
    end
  end
end
