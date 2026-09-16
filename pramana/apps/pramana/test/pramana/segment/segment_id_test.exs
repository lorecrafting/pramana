defmodule Pramana.Segment.SegmentIdTest do
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Bilara
  alias Pramana.Segment.SegmentId

  @opts [source: "sc", witness: "ms"]

  defp segments!(map, work_id \\ "mn1") do
    {:ok, ir} = Bilara.normalize(Jason.encode!(map), work_id: work_id)
    {:ok, segments} = SegmentId.segments(ir, @opts)
    segments
  end

  describe "URNs" do
    test "adopt SuttaCentral's segment id verbatim" do
      [segment] = segments!(%{"mn1:1.1" => "Evaṁ me sutaṁ—"})

      assert segment.urn == "pramana:sc.ms:mn1@1.1"
    end

    test "carry the work id from the segment id, not the file" do
      [segment] = segments!(%{"an1.1:1.1" => "text"}, "an1.1")

      assert segment.urn == "pramana:sc.ms:an1.1@1.1"
    end
  end

  describe "printed coordinates" do
    # Pāli has no printed page in this edition. Manufacturing page/register/line would be
    # inventing coordinates a reader cannot check against anything.
    test "are null rather than manufactured" do
      [segment] = segments!(%{"mn1:1.1" => "Evaṁ me sutaṁ—"})

      assert segment.page == nil
      assert segment.register == nil
      assert segment.line == nil
      assert segment.juan == nil
    end
  end

  describe "content" do
    test "is hashed so the guard can check a quote against it" do
      [segment] = segments!(%{"mn1:1.1" => "Evaṁ me sutaṁ—"})

      assert segment.content == "Evaṁ me sutaṁ—"

      assert segment.content_sha256 ==
               :crypto.hash(:sha256, "Evaṁ me sutaṁ—") |> Base.encode16(case: :lower)
    end

    test "spans track offsets into the joined body, including the newline between lines" do
      [first, second] = segments!(%{"mn1:1.1" => "abc", "mn1:1.2" => "de"})

      assert {first.char_start, first.char_end} == {0, 3}
      assert {second.char_start, second.char_end} == {4, 6}
    end

    test "byte spans differ from char spans where the text is not ASCII" do
      [segment] = segments!(%{"mn1:1.1" => "sutaṁ"})

      assert segment.char_end == 5
      assert segment.byte_end == 7
    end
  end

  describe "empty segments" do
    test "produce no citable address, but still advance the offsets" do
      segments = segments!(%{"mn1:1.1" => "abc", "mn1:1.2" => "", "mn1:1.3" => "xyz"})

      assert Enum.map(segments, & &1.urn) == [
               "pramana:sc.ms:mn1@1.1",
               "pramana:sc.ms:mn1@1.3"
             ]

      # Ordinals number the addressable segments consecutively...
      assert Enum.map(segments, & &1.ordinal) == [0, 1]
      # ...while the offsets still account for the skipped line in the body.
      assert Enum.map(segments, & &1.char_start) == [0, 5]
    end
  end
end
