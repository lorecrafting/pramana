defmodule Pramana.CorpusContextTest do
  @moduledoc """
  Context windows, outlines, and range URNs.

  Taishō lines are typographic, not syntactic — they break mid-sentence — so a single
  segment is frequently unreadable alone. And no context window holds a whole work, so
  structure has to be surveyable without pulling text.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus
  alias Pramana.Corpus.Loader
  alias Pramana.Guard
  alias Pramana.Normalize.CBETA

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title><author>鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001c18"/><cb:mulu level="1" n="1" type="品">1 序品</cb:mulu>序品第一
  <lb n="0001c19"/>如是我聞：一時，佛住王舍城
  <lb n="0001c20"/>耆闍崛山中，與大比丘眾萬二千人俱
  <lb n="0001c21"/>皆是阿羅漢，諸漏已盡
  <milestone n="2" unit="juan"/>
  <lb n="0010b24"/><cb:mulu level="1" n="3" type="品">3 譬喻品</cb:mulu>譬喻品第三
  </body></text></TEI>
  """

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "translation"}
      )

    %{urn: "pramana:cbeta.T:T0262_001@p0001c19"}
  end

  describe "outline — surveying structure without pulling text" do
    test "captures cb:mulu entries with resolvable URNs" do
      assert {:ok, outline} = Corpus.outline("T0262")
      assert outline.title == "妙法蓮華經"
      assert [first, second] = outline.entries

      assert first.title == "1 序品"
      assert first.type == "品"
      assert first.urn == "pramana:cbeta.T:T0262_001@p0001c18"
      assert second.title == "3 譬喻品"
      # The second chapter is in juan 2, so its URN must say so.
      assert second.urn == "pramana:cbeta.T:T0262_002@p0010b24"
    end

    test "every outline URN actually resolves" do
      {:ok, outline} = Corpus.outline("T0262")

      for entry <- outline.entries do
        assert {:ok, _span} = Corpus.resolve(entry.urn), "#{entry.urn} does not resolve"
      end
    end

    test "outline titles never leak into body text" do
      {:ok, span} = Corpus.resolve("pramana:cbeta.T:T0262_001@p0001c18")
      assert span.content == "序品第一"
      refute String.contains?(span.content, "1 序品")
    end

    test "reports not_found for an unknown work" do
      assert {:error, :not_found} = Corpus.outline("T9999")
    end
  end

  describe "context/2 — making a passage readable" do
    test "returns the focus with its neighbours", ctx do
      assert {:ok, c} = Corpus.context(ctx.urn, before: 1, after: 2)

      assert c.focus.urn == ctx.urn
      assert length(c.before) == 1
      assert length(c.after) == 2
      assert c.segment_count == 4
    end

    test "the joined text reads continuously across line breaks", ctx do
      {:ok, c} = Corpus.context(ctx.urn, before: 0, after: 1)
      # The focus alone cuts mid-sentence at 王舍城; with context it completes.
      assert c.text == "如是我聞：一時，佛住王舍城耆闍崛山中，與大比丘眾萬二千人俱"
    end

    test "every neighbour is a full, independently verifiable span", ctx do
      {:ok, c} = Corpus.context(ctx.urn, before: 1, after: 1)

      for span <- [c.focus | c.before ++ c.after] do
        assert Guard.verify(span.urn, span.content)
        assert span.sha256 == :crypto.hash(:sha256, span.content) |> Base.encode16(case: :lower)
      end
    end

    test "clamps context size rather than allowing a context flood", ctx do
      {:ok, c} = Corpus.context(ctx.urn, before: 10_000, after: 10_000)
      # Bounded by the text, and the requested window is capped at 50 either way.
      assert c.segment_count == 5
    end

    test "does not run off the start of a text", ctx do
      first = "pramana:cbeta.T:T0262_001@p0001c18"
      assert {:ok, c} = Corpus.context(first, before: 5, after: 1)
      assert c.before == []
      assert c.focus.urn == first
      refute ctx.urn == first
    end

    test "propagates errors for bad input" do
      assert {:error, :bad_urn} = Corpus.context("nonsense")
      assert {:error, :not_found} = Corpus.context("pramana:cbeta.T:T0262_001@p9999a99")
    end
  end

  describe "range URNs" do
    test "a context window yields a range URN covering it", ctx do
      {:ok, c} = Corpus.context(ctx.urn, before: 1, after: 2)
      assert c.urn == "pramana:cbeta.T:T0262_001@p0001c18-p0001c21"
    end

    test "a range URN resolves to the concatenated passage", ctx do
      {:ok, c} = Corpus.context(ctx.urn, before: 1, after: 2)
      assert {:ok, span} = Corpus.resolve(c.urn)

      assert span.content == c.text
      assert span.meta["range_of"] == 4
    end

    test "a range span stays byte-verifiable against the stored body" do
      urn = "pramana:cbeta.T:T0262_001@p0001c19-p0001c20"
      {:ok, span} = Corpus.resolve(urn)
      {:ok, body} = Corpus.body("pramana:cbeta.T:T0262")

      # Offsets span first-start to last-end. The body has a "\n" between lines that
      # the concatenated content does not, so compare on length rather than equality —
      # what must hold is that the offsets bracket exactly these segments.
      slice = binary_part(body, span.byte_start, span.byte_end - span.byte_start)
      assert String.replace(slice, "\n", "") == span.content
    end

    test "the guard verifies a quote inside a range citation", ctx do
      {:ok, c} = Corpus.context(ctx.urn, before: 1, after: 2)

      assert Guard.verify(c.urn, "如是我聞")
      assert Guard.verify(c.urn, "耆闍崛山中")
      refute Guard.verify(c.urn, "此文不存在")
    end

    test "a range whose endpoints do not exist is not_found" do
      assert {:error, :not_found} = Corpus.resolve("pramana:cbeta.T:T0262_001@p9999a01-p9999a09")
    end
  end
end
