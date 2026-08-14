defmodule Pramana.Normalize.CBETATest do
  use ExUnit.Case, async: true

  alias Pramana.Normalize.CBETA
  alias Pramana.Normalize.IR
  alias Pramana.URN.Taisho

  @opts [work_id: "T0262", canon: "T", volume: 9, number: "0262"]

  defp normalize!(xml, opts \\ @opts) do
    {:ok, ir} = CBETA.normalize(xml, opts)
    ir
  end

  defp doc(body, header \\ "") do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader>#{header}</teiHeader>
    <text><body>#{body}</body></text>
    </TEI>
    """
  end

  describe "line anchors — the citation itself" do
    test "every <lb/> becomes a line with its Taishō anchor" do
      ir =
        normalize!(
          doc("""
          <lb n="0001a05" ed="T"/><p>昔如來於耆闍崛山中</p>
          <lb n="0001a06" ed="T"/>陳如、摩訶迦葉無量等眾
          """)
        )

      assert [l1, l2] = ir.lines
      assert l1.anchor == "0001a05"
      assert l1.text == "昔如來於耆闍崛山中"
      assert l2.anchor == "0001a06"
      assert l2.text == "陳如、摩訶迦葉無量等眾"
    end

    test "anchors parse under the Taishō locator grammar" do
      ir = normalize!(doc(~s(<lb n="0001a05" ed="T"/>文)))
      [line] = ir.lines

      assert {:ok, %{page: "0001", register: "a", line: 5}} =
               Taisho.parse_locator("p" <> line.anchor)
    end

    test "no line is silently dropped" do
      body =
        Enum.map_join(1..20, "", fn i ->
          n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
          ~s(<lb n="#{n}" ed="T"/>文字#{i})
        end)

      ir = normalize!(doc(body))
      assert length(ir.lines) == 20
      assert Enum.map(ir.lines, & &1.anchor) |> List.last() == "0001a20"
    end
  end

  describe "juan boundaries" do
    test "milestone sets the juan for following lines" do
      ir =
        normalize!(
          doc("""
          <milestone n="1" unit="juan"/><lb n="0001a05" ed="T"/>一
          <milestone n="2" unit="juan"/><lb n="0010b01" ed="T"/>二
          """)
        )

      assert [%{juan: 1}, %{juan: 2}] = ir.lines
      assert ir.juan_count == 2
    end
  end

  describe "the apparatus — <lem> is text, <rdg> is not" do
    test "only the base reading enters the running text" do
      ir =
        normalize!(
          doc("""
          <lb n="0001a03" ed="T"/>姚秦<app><lem wit="#wit.orig">龜</lem><rdg resp="#resp2" wit="#wit1">丘</rdg></app>茲
          """)
        )

      [line] = ir.lines
      assert line.text == "姚秦龜茲"
      refute String.contains?(line.text, "丘")
    end

    test "variant readings are recorded in the apparatus with their witnesses" do
      ir =
        normalize!(
          doc("""
          <lb n="0001a03" ed="T"/><app from="#beg1"><lem wit="#wit.orig">龜</lem><rdg resp="#resp2" wit="#wit1 #wit2">丘</rdg></app>
          """)
        )

      [line] = ir.lines

      assert [%{lem: "龜", rdgs: [%{text: "丘", wit: "#wit1 #wit2", resp: "#resp2"}]}] =
               line.apparatus
    end

    test "multiple variants on one lemma are all kept, in order" do
      ir =
        normalize!(
          doc("""
          <lb n="0001a03" ed="T"/><app><lem>甲</lem><rdg wit="#wit1">乙</rdg><rdg wit="#wit2">丙</rdg></app>
          """)
        )

      [line] = ir.lines
      assert [%{rdgs: [%{text: "乙"}, %{text: "丙"}]}] = line.apparatus
    end
  end

  describe "content excluded from body text" do
    test "notes are captured separately, never mixed into the text" do
      ir =
        normalize!(doc(~s(<lb n="0001a05" ed="T"/>正文<note n="0001001">校勘註</note>續文)))

      [line] = ir.lines
      assert line.text == "正文續文"
      assert line.notes == ["校勘註"]
    end

    test "navigation apparatus is excluded" do
      ir =
        normalize!(
          doc("""
          <lb n="0001a02" ed="T"/><cb:docNumber>No. 262</cb:docNumber><cb:mulu level="1" type="序">序</cb:mulu>本文
          """)
        )

      [line] = ir.lines
      assert line.text == "本文"
    end

    test "header content never leaks into the body" do
      ir = normalize!(doc(~s(<lb n="0001a01"/>本文), "<title>SHOULD NOT APPEAR</title>"))
      refute Enum.any?(ir.lines, &String.contains?(&1.text, "SHOULD"))
    end
  end

  describe "verse and headings" do
    test "lines inside <lg> are marked verse" do
      ir =
        normalize!(
          doc("""
          <lb n="0001a05"/>散文
          <lg><lb n="0001a06"/><l>偈頌一句</l></lg>
          <lb n="0001a07"/>再散文
          """)
        )

      assert [%{kind: :prose}, %{kind: :verse}, %{kind: :prose}] = ir.lines
    end

    test "headings are marked" do
      ir = normalize!(doc(~s(<lb n="0001a03"/><head>御製大乘妙法蓮華經序</head>)))
      assert [%{kind: :head, text: "御製大乘妙法蓮華經序"}] = ir.lines
    end
  end

  describe "gaiji" do
    @header """
    <charDecl><char xml:id="CB00006">
      <charProp><localName>normalized form</localName><value>璩</value></charProp>
      <mapping type="unicode">U+249B2</mapping>
    </char></charDecl>
    """

    test "declarations are parsed and mapped to a real codepoint" do
      ir = normalize!(doc(~s(<lb n="0001a05"/>文), @header))
      assert %{unicode: "\u{249B2}", normalized: "璩"} = ir.gaiji["CB00006"]
    end

    test "occurrences are recorded on the line that contains them" do
      ir = normalize!(doc(~s(<lb n="0001a05"/>前<g ref="#CB00006">\u{F0006}</g>後), @header))
      [line] = ir.lines
      assert [%{ref: "CB00006", mapping: %{normalized: "璩"}}] = line.gaiji
    end

    test "an unmapped gaiji is recorded rather than dropped" do
      ir = normalize!(doc(~s(<lb n="0001a05"/><g ref="#CB99999">x</g>)))
      [line] = ir.lines
      assert [%{ref: "CB99999", mapping: nil}] = line.gaiji
    end
  end

  describe "CJK integrity" do
    test "characters pass through byte-for-byte with no Unicode normalization" do
      # These are distinct codepoints that NFC/NFKC would happily collapse or alter.
      # In a critical edition that would be silent corruption.
      original = "戶户戸 直𥄎 說説 兔兎"
      ir = normalize!(doc(~s(<lb n="0001a05"/>#{original})))
      [line] = ir.lines
      assert line.text == original
    end

    test "rare plane-2 characters survive" do
      original = "𤦲𧂐𩑔"
      ir = normalize!(doc(~s(<lb n="0001a05"/>#{original})))
      assert [%{text: ^original}] = ir.lines
    end
  end

  describe "editorial punctuation flagging" do
    test "lines with CBETA-added punctuation are flagged" do
      ir = normalize!(doc(~s(<lb n="0001a05"/>陳如、摩訶迦葉，無量等眾。)))
      assert [%{editorial_punctuation: true}] = ir.lines
    end

    test "lines without it are not" do
      ir = normalize!(doc(~s(<lb n="0001a05"/>陳如摩訶迦葉)))
      assert [%{editorial_punctuation: false}] = ir.lines
    end
  end

  describe "back-matter apparatus" do
    # CBETA keeps its collation apparatus in <back>, keyed to <anchor> positions in
    # the body, rather than inline. Everything here was learned by running against
    # the real T0262 rather than assumed from the TEI spec.
    defp apparatus_doc do
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
      <text>
      <body>
      <lb n="0001b19"/>前行
      <lb n="0001b20"/>秦弘始，<anchor xml:id="beg0001004"/>龜<anchor xml:id="end0001004"/>茲沙門
      </body>
      <back><cb:div type="apparatus"><head>校注</head><p>
      <app from="#beg0001004" to="#end0001004"><lem wit="#wit.orig">龜</lem><rdg resp="#resp2" wit="#wit1">丘</rdg></app>
      </p></cb:div></back>
      </text>
      </TEI>
      """
    end

    test "a variant is attached to the body line its anchor points at" do
      ir = normalize!(apparatus_doc())
      target = Enum.find(ir.lines, &(&1.anchor == "0001b20"))

      assert [%{lem: "龜", rdgs: [%{text: "丘", wit: "#wit1"}]}] = target.apparatus
      assert Enum.find(ir.lines, &(&1.anchor == "0001b19")).apparatus == []
    end

    test "apparatus text never leaks into body text" do
      ir = normalize!(apparatus_doc())
      body = IR.body(ir)

      assert body == "前行\n秦弘始，龜茲沙門"
      refute String.contains?(body, "丘")
      refute String.contains?(body, "校注")
    end

    test "<lb/> inside a back-matter lemma does not create a phantom line" do
      # A lemma reproducing body text carries that text's <lb/> with it. Treating
      # those as line boundaries invents lines with DUPLICATE anchors — non-unique
      # URNs, and apparatus attached twice.
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
      <text>
      <body><lb n="0001c16"/>後秦龜茲國三藏法師<lb n="0001c17"/>鳩摩羅什奉　詔譯</body>
      <back><p><app from="#x"><lem>後秦龜茲國三藏法師<lb n="0001c17"/>鳩摩羅什奉　詔譯</lem></app></p></back>
      </text></TEI>
      """

      ir = normalize!(xml)
      anchors = Enum.map(ir.lines, & &1.anchor)

      assert anchors == ["0001c16", "0001c17"]
      assert anchors == Enum.uniq(anchors), "line anchors must be unique — URNs depend on it"
    end

    test "a lemma spanning <lb/> keeps each half on its own line" do
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>
      <lb n="0001c16"/><app><lem>後秦龜茲國三藏法師<lb n="0001c17"/>鳩摩羅什奉　詔譯</lem></app>
      </body></text></TEI>
      """

      ir = normalize!(xml)

      assert [%{anchor: "0001c16", text: "後秦龜茲國三藏法師"}, %{anchor: "0001c17", text: "鳩摩羅什奉　詔譯"}] =
               ir.lines
    end

    test "an <app> nested inside a <lem> inherits its parent's anchor" do
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text>
      <body><lb n="0003a01"/><anchor xml:id="beg1"/>車馬腦<anchor xml:id="end1"/></body>
      <back><p><app from="#beg1"><lem>車馬<app><lem>腦</lem><rdg wit="#博">瑙</rdg></app></lem></app></p></back>
      </text></TEI>
      """

      ir = normalize!(xml)
      [line] = ir.lines
      # Both the outer and the nested entry are real variants and both are recorded.
      assert length(line.apparatus) == 2
      assert Enum.any?(line.apparatus, &match?(%{lem: "腦", rdgs: [%{text: "瑙"}]}, &1))
    end

    test "a <rdg> that is an omission is flagged, not silently empty" do
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text>
      <body><lb n="0001a01"/><anchor xml:id="beg1"/>唐<anchor xml:id="end1"/></body>
      <back><p><app from="#beg1"><lem>唐</lem><rdg wit="#wit1"><space quantity="0"/></rdg></app></p></back>
      </text></TEI>
      """

      ir = normalize!(xml)
      [line] = ir.lines
      assert [%{rdgs: [%{text: "", omitted: true}]}] = line.apparatus
    end

    test "unplaceable apparatus is kept and counted, never dropped" do
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text>
      <body><lb n="0001a01"/>本文</body>
      <back><p><app><lem>孤</lem></app></p></back>
      </text></TEI>
      """

      ir = normalize!(xml)
      assert [%{lem: "孤"}] = ir.unanchored_apparatus
      assert IR.apparatus_count(ir) == 1
    end
  end

  describe "IR.body/1" do
    test "joins lines with newline so offsets are computed one way only" do
      ir = normalize!(doc(~s(<lb n="0001a05"/>甲<lb n="0001a06"/>乙)))
      assert IR.body(ir) == "甲\n乙"
    end
  end
end
