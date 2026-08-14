defmodule Pramana.Segment.TaishoTest do
  use ExUnit.Case, async: true

  alias Pramana.Normalize.CBETA
  alias Pramana.Normalize.IR
  alias Pramana.Segment.Taisho
  alias Pramana.URN

  @opts [source: "cbeta", witness: "T"]

  defp segments!(body_xml) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <text><body>#{body_xml}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
    {:ok, segments} = Taisho.segments(ir, @opts)
    {ir, segments}
  end

  describe "URNs" do
    test "are built from the tradition's own citation grammar" do
      {_ir, [seg]} = segments!(~s(<milestone n="9" unit="juan"/><lb n="0037a13"/>如是我聞))

      assert seg.urn == "pramana:cbeta.T:T0262_009@p0037a13"
    end

    test "round-trip through the URN parser" do
      {_ir, segs} =
        segments!(~s(<milestone n="1" unit="juan"/><lb n="0001a05"/>甲<lb n="0001a06"/>乙))

      for seg <- segs do
        assert {:ok, urn} = URN.parse(seg.urn)
        assert URN.to_string(urn) == seg.urn
        assert urn.work == "T0262_001"
      end
    end

    test "omit the juan when the source gives none" do
      {_ir, [seg]} = segments!(~s(<lb n="0001a05"/>甲))
      assert seg.urn == "pramana:cbeta.T:T0262@p0001a05"
    end

    test "are unique across a text" do
      body =
        Enum.map_join(1..30, "", fn i ->
          n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
          ~s(<lb n="#{n}"/>文#{i})
        end)

      {_ir, segs} = segments!(body)
      urns = Enum.map(segs, & &1.urn)
      assert length(urns) == 30
      assert urns == Enum.uniq(urns)
    end
  end

  describe "anchor decomposition" do
    test "page, register, and line are stored as queryable columns" do
      {_ir, [seg]} = segments!(~s(<milestone n="9" unit="juan"/><lb n="0037b02"/>文))

      assert seg.page == "0037"
      assert seg.register == "b"
      assert seg.line == 2
      assert seg.juan == 9
    end

    test "the page keeps its zero padding" do
      {_ir, [seg]} = segments!(~s(<lb n="0001a05"/>文))
      assert seg.page == "0001"
    end
  end

  describe "offsets into IR.body/1 — the basis of verification" do
    test "every segment's offsets slice its exact content back out of the body" do
      {ir, segs} =
        segments!(~s(<lb n="0001a05"/>昔如來於<lb n="0001a06"/>耆闍崛山中<lb n="0001a07"/>與大))

      body = IR.body(ir)

      for seg <- segs do
        sliced = String.slice(body, seg.char_start, seg.char_end - seg.char_start)
        assert sliced == seg.content, "offsets do not resolve for #{seg.urn}"
      end
    end

    test "offsets are CHARACTER offsets, not byte offsets" do
      # Classical Chinese is multi-byte throughout; byte offsets would be unusable
      # from any client that slices by codepoint.
      {_ir, [seg]} = segments!(~s(<lb n="0001a05"/>昔如來於耆闍崛山中))

      assert seg.char_start == 0
      assert seg.char_end == 9
      assert byte_size(seg.content) == 27
    end

    test "empty lines are skipped but still consume their position" do
      {ir, segs} = segments!(~s(<lb n="0001a01"/><lb n="0001a02"/>甲<lb n="0001a03"/>乙))
      body = IR.body(ir)

      assert length(segs) == 2

      for seg <- segs do
        assert String.slice(body, seg.char_start, seg.char_end - seg.char_start) == seg.content
      end
    end

    test "ordinals are contiguous over the emitted segments" do
      {_ir, segs} = segments!(~s(<lb n="0001a01"/>甲<lb n="0001a02"/><lb n="0001a03"/>乙))
      assert Enum.map(segs, & &1.ordinal) == [0, 1]
    end
  end

  describe "content hashes" do
    test "cover the segment content exactly" do
      {_ir, [seg]} = segments!(~s(<lb n="0001a05"/>如是我聞))

      expected = :crypto.hash(:sha256, "如是我聞") |> Base.encode16(case: :lower)
      assert seg.content_sha256 == expected
    end

    test "differ for visually similar but distinct Han variants" do
      {_ir, [a]} = segments!(~s(<lb n="0001a05"/>戶))
      {_ir, [b]} = segments!(~s(<lb n="0001a05"/>户))

      refute a.content_sha256 == b.content_sha256
    end
  end

  describe "metadata carried onto the segment" do
    test "the variant apparatus travels with the line it annotates" do
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text>
      <body><lb n="0001b20"/>秦弘始，<anchor xml:id="beg1"/>龜<anchor xml:id="end1"/>茲</body>
      <back><p><app from="#beg1"><lem>龜</lem><rdg wit="#wit1">丘</rdg></app></p></back>
      </text></TEI>
      """

      {:ok, ir} = CBETA.normalize(xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
      {:ok, [seg]} = Taisho.segments(ir, @opts)

      assert %{"apparatus" => [%{"lem" => "龜", "rdgs" => [%{"text" => "丘"}]}]} = seg.meta
    end

    test "editorial punctuation is flagged so nobody cites it as original" do
      {_ir, [seg]} = segments!(~s(<lb n="0001a05"/>陳如、摩訶迦葉。))
      assert seg.meta["editorial_punctuation"] == true
    end

    test "clean lines carry no empty metadata keys" do
      {_ir, [seg]} = segments!(~s(<lb n="0001a05"/>如是我聞))
      assert seg.meta == %{}
    end

    test "verse and heading kinds survive into the row" do
      {_ir, segs} =
        segments!(~s(<lb n="0001a05"/>散文<lg><lb n="0001a06"/><l>偈頌</l></lg>))

      assert Enum.map(segs, & &1.kind) == ["prose", "verse"]
    end
  end

  describe "urn_prefix/3" do
    test "identifies a text without a locator" do
      assert Taisho.urn_prefix("cbeta", "T", "T0262") == "pramana:cbeta.T:T0262"
    end
  end
end
