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

  describe "lines whose only printed content is an inline note" do
    # Dropping these cost the corpus 5,213 printed lines and 266,547 characters,
    # concentrated in the catalogues and commentaries where interlinear notes carry
    # much of the substance. The line exists in the printed edition; it needs a URN.
    test "still get a segment, so the note is reachable and the line is citable" do
      {_ir, segs} =
        segments!(~s(<lb n="0001a01"/>甲<lb n="0001a02"/><note place="inline">乙丙</note>))

      assert length(segs) == 2

      note_only = List.last(segs)
      assert note_only.urn == "pramana:cbeta.T:T0262@p0001a02"
      assert note_only.content == ""
      assert note_only.meta["notes"] == ["乙丙"]
    end

    test "a line carrying only apparatus keeps its anchor too" do
      {_ir, segs} =
        segments!("""
        <lb n="0001a01"/>甲<lb n="0001a02"/><app><lem wit="\#{T}"></lem><rdg wit="\#{S}">丙</rdg></app>
        """)

      assert length(segs) == 2
      assert List.last(segs).content == ""
      assert List.last(segs).meta["apparatus"] != nil
    end

    test "a genuinely blank line is still skipped" do
      # No text, no note, no apparatus: nothing was printed but the line number.
      {_ir, segs} = segments!(~s(<lb n="0001a01"/>甲<lb n="0001a02"/><lb n="0001a03"/>乙))

      assert length(segs) == 2
      refute Enum.any?(segs, &(&1.content == ""))
    end

    test "an empty segment's offsets still slice its (empty) content out of the body" do
      {ir, segs} =
        segments!(~s(<lb n="0001a01"/>甲<lb n="0001a02"/><note place="inline">乙</note>))

      body = IR.body(ir)

      for seg <- segs do
        assert String.slice(body, seg.char_start, seg.char_end - seg.char_start) == seg.content
      end
    end
  end

  describe "an anchor the markup re-announces" do
    # CBETA re-emits `<lb>` when an element spans the line it opened on, so one printed
    # line arrives as two fragments with the SAME number and edition. Emitting both gives
    # them one URN between them, and the insert dies on `segments_urn_index` — which
    # killed 284 of 1,236 works when CBETA's X collection was first baked. The Taishō
    # survived only because its repeats carry nothing on the second occurrence.
    test "is one segment, not two" do
      {_ir, segments} =
        segments!(
          ~s(<milestone n="1" unit="juan"/><lb n="0831b01"/>馬鳴菩薩<lb n="0831b01"/><note place="inline">吉備大臣</note>)
        )

      assert length(segments) == 1
      assert hd(segments).urn =~ "p0831b01"
    end

    test "keeps the note, which is printed content and must stay addressable" do
      {_ir, [seg]} =
        segments!(
          ~s(<milestone n="1" unit="juan"/><lb n="0831b01"/>馬鳴菩薩<lb n="0831b01"/><note place="inline">吉備大臣</note>)
        )

      # The note is not inline in `content` — the normalizer routes inline notes to
      # `meta["notes"]` and leaves that fragment's text empty. So the merge has to carry
      # META across, not only text: dropping the second fragment would lose the note, and
      # rule 3 says an inline note is printed content that needs an address.
      assert seg.content =~ "馬鳴菩薩"
      assert inspect(seg.meta) =~ "吉備大臣"
    end

    test "stays byte-verifiable against the body, newline included" do
      # THE ASSERTION THAT CONSTRAINS THE FIX. `IR.body/1` joins lines with "\n", so the
      # bytes between the two fragments in the body ARE a newline. A merged span must
      # contain it or the slice stops equalling the content and invariant #1 breaks
      # silently for exactly these lines.
      {ir, [seg]} =
        segments!(
          ~s(<milestone n="1" unit="juan"/><lb n="0831b01"/>馬鳴菩薩<lb n="0831b01"/><note place="inline">吉備大臣</note>)
        )

      body = IR.body(ir)

      assert binary_part(body, seg.byte_start, seg.byte_end - seg.byte_start) == seg.content

      assert :crypto.hash(:sha256, seg.content) |> Base.encode16(case: :lower) ==
               seg.content_sha256
    end

    test "leaves ordinals contiguous" do
      # `Corpus.between/4` selects by ordinal RANGE, so a gap left by merging would
      # silently shorten every chunk and range URN crossing it.
      {_ir, segments} =
        segments!(
          ~s(<milestone n="1" unit="juan"/><lb n="0001a01"/>甲<lb n="0001a01"/><note place="inline">乙</note><lb n="0001a02"/>丙<lb n="0001a03"/>丁)
        )

      assert Enum.map(segments, & &1.ordinal) == Enum.to_list(0..(length(segments) - 1))
    end

    test "an anchor repeated NON-adjacently is left alone" do
      # Two fragments with a different line between them are not one printed line — they
      # are the edition printing an anchor twice, which is a different problem with a
      # different remedy (see the Derge `+2` precedent). Merging them would fuse distinct
      # passages, so this deliberately still produces two segments.
      {_ir, segments} =
        segments!(
          ~s(<milestone n="1" unit="juan"/><lb n="0019a01"/>甲<lb n="0019a02"/>乙<lb n="0019a01"/>丙)
        )

      assert length(segments) == 3
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
