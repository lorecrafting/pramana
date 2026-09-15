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

  describe "a file carrying several editions' lineations" do
    # CBETA's X collection prints TWO line numberings side by side:
    #
    #     <lb ed="X" n="0019a11"/><lb ed="R055" n="0019a01"/>
    #     <lb ed="X" n="0019a12"/><lb ed="R055" n="0019a01"/>
    #
    # `ed="X"` is the 卍新纂 lineation the collection is cited by; `ed="R055"` is the
    # earlier 卍續藏經 reprint's, and one R line spans many X lines. Treating every `<lb>`
    # as a line boundary conflated them — `0019a01` arrived 56 times in one work, and 284
    # of 1,236 X works died on `segments_urn_index`.
    #
    # Measured: T09n0262 has 5,409 `<lb>`, every one `ed="T"`. X35n0640 has 1,196 `ed="X"`
    # beside 1,194 `ed="R055"`. A rule that was right for one collection stayed invisible
    # until a second arrived.
    defp x_segments!(body_xml) do
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
      <text><body>#{body_xml}</body></text></TEI>
      """

      {:ok, ir} = CBETA.normalize(xml, work_id: "X0640", canon: "X", volume: 35, number: "0640")
      {:ok, segments} = Taisho.segments(ir, source: "cbeta", witness: "X")
      {ir, segments}
    end

    test "only the collection's own lineation becomes a line" do
      {_ir, segs} =
        x_segments!(
          ~s(<lb ed="X" n="0019a11"/><lb ed="R055" n="0019a01"/>甲) <>
            ~s(<lb ed="X" n="0019a12"/><lb ed="R055" n="0019a01"/>乙)
        )

      assert length(segs) == 2

      assert Enum.map(segs, & &1.urn) == [
               "pramana:cbeta.X:X0640@p0019a11",
               "pramana:cbeta.X:X0640@p0019a12"
             ]
    end

    test "the other edition's repeated number cannot collide" do
      # This is the failure it exists to prevent: one R line spanning three X lines used
      # to emit three segments all claiming `p0019a01`.
      {_ir, segs} =
        x_segments!(
          ~s(<lb ed="X" n="0019a11"/><lb ed="R055" n="0019a01"/>甲) <>
            ~s(<lb ed="X" n="0019a12"/><lb ed="R055" n="0019a01"/>乙) <>
            ~s(<lb ed="X" n="0019a13"/><lb ed="R055" n="0019a01"/>丙)
        )

      urns = Enum.map(segs, & &1.urn)
      assert length(urns) == 3
      assert urns == Enum.uniq(urns)
    end

    test "text is attributed to the line it was printed on, not the one before" do
      # Dropping the foreign `<lb>` must not also drop the text following it. If the R tag
      # ended the line, 乙 would be attributed to 0019a11.
      {_ir, segs} =
        x_segments!(
          ~s(<lb ed="X" n="0019a11"/>甲<lb ed="R055" n="0019a01"/>) <>
            ~s(<lb ed="X" n="0019a12"/>乙)
        )

      assert Enum.map(segs, & &1.content) == ["甲", "乙"]
    end

    # A printed line whose entire content is one rare character. Gaiji are recorded as a
    # MAPPING rather than substituted into the body, so such a line has empty `text` and
    # matched the segmenter's "nothing was printed here" test exactly — and a gaiji is
    # the one kind of content a reader cannot reconstruct from anything else. One line in
    # the whole CBETA corpus was in this state: X0575 0966b12, 䦚 (CB12059).
    test "a line that is nothing but a rare character still gets a URN" do
      {_ir, segs} =
        x_segments!(
          ~s(<lb ed="X" n="0966b11"/>甲) <>
            ~s(<lb ed="X" n="0966b12"/><g ref="#CB12059"/>) <>
            ~s(<lb ed="X" n="0966b13"/>乙)
        )

      assert Enum.map(segs, & &1.urn) == [
               "pramana:cbeta.X:X0640@p0966b11",
               "pramana:cbeta.X:X0640@p0966b12",
               "pramana:cbeta.X:X0640@p0966b13"
             ]

      gaiji_line = Enum.find(segs, &(&1.urn =~ "0966b12"))
      assert gaiji_line.content == ""
      assert [%{ref: "CB12059"}] = gaiji_line.meta["gaiji"]
    end

    test "a line with nothing printed on it at all is still skipped" do
      {_ir, segs} =
        x_segments!(
          ~s(<lb ed="X" n="0966b11"/>甲<lb ed="X" n="0966b12"/><lb ed="X" n="0966b13"/>乙)
        )

      assert Enum.map(segs, & &1.urn) == [
               "pramana:cbeta.X:X0640@p0966b11",
               "pramana:cbeta.X:X0640@p0966b13"
             ]
    end

    # `mix pramana.integrity` counts `<lb ` in the raw body and compares. Filtering a
    # foreign lineation looks EXACTLY like losing half the lines unless the count is
    # carried, and for 1,228 X texts it did: `raw 46, bake 25`, reported as `lb_lost`
    # over a bake that was correct.
    test "the skipped edition's lines are counted, so a fidelity check can reconcile" do
      {ir, segs} =
        x_segments!(
          ~s(<lb ed="X" n="0019a11"/><lb ed="R055" n="0019a01"/>甲) <>
            ~s(<lb ed="X" n="0019a12"/><lb ed="R055" n="0019a01"/>乙)
        )

      assert length(segs) == 2
      assert ir.foreign_lb == 2
      # The reconciliation the check performs: every raw <lb/> is a line or a skip.
      assert length(ir.lines) + ir.foreign_lb == 4
    end

    test "a file with one lineation reports nothing skipped" do
      {ir, _segs} = x_segments!(~s(<lb ed="X" n="0019a11"/>甲<lb ed="X" n="0019a12"/>乙))

      assert ir.foreign_lb == 0
      assert length(ir.lines) == 2
    end

    test "an lb with no edition is still a line" do
      # Older CBETA files omit `ed` entirely, and there the collection's own lineation is
      # the only one present. Requiring the attribute would empty those texts silently.
      {_ir, segs} = x_segments!(~s(<lb n="0019a11"/>甲<lb n="0019a12"/>乙))

      assert length(segs) == 2
    end

    test "the Taishō is unaffected, because its files carry one lineation" do
      {_ir, segs} = segments!(~s(<lb ed="T" n="0001a01"/>甲<lb ed="T" n="0001a02"/>乙))

      assert length(segs) == 2
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
