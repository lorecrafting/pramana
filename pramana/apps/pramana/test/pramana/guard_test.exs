defmodule Pramana.GuardTest do
  @moduledoc """
  The guard is the keystone: it is what makes a citation trustworthy regardless of
  which model produced it. These tests are the proof of `CLAUDE.md`'s central claim.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus
  alias Pramana.Corpus.Loader
  alias Pramana.Guard
  alias Pramana.Normalize.CBETA

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title>
    <author>姚秦 鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001a05"/>如是我聞：一時佛住王舍城
  <lb n="0001a06"/>耆闍崛山中，與大比丘眾萬二千人俱
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

    %{
      urn: "pramana:cbeta.T:T0262_001@p0001a05",
      content: "如是我聞：一時佛住王舍城"
    }
  end

  describe "resolve/1" do
    test "returns a span with everything needed to verify it", ctx do
      assert {:ok, span} = Corpus.resolve(ctx.urn)

      assert span.urn == ctx.urn
      assert span.content == ctx.content
      assert span.sha256 == :crypto.hash(:sha256, ctx.content) |> Base.encode16(case: :lower)
      assert is_integer(span.char_start) and is_integer(span.byte_start)
    end

    test "carries multi-axis provenance, not a source string", ctx do
      {:ok, span} = Corpus.resolve(ctx.urn)

      assert span.provenance.composition_origin == "indic"
      assert span.provenance.text_role == "translation"
      assert span.provenance.attributed_author == "姚秦 鳩摩羅什譯"
      assert span.provenance.witness == "T"
      assert span.provenance.source == "cbeta"
      assert span.provenance.license_class == "nc"
      assert span.provenance.juan == 1
      assert span.provenance.page == "0001"
    end

    test "marks canonical addressing, distinguishable from derived", ctx do
      {:ok, span} = Corpus.resolve(ctx.urn)
      assert span.provenance.addressing == "canonical"
    end

    test "rejects a malformed URN without raising" do
      assert {:error, :bad_urn} = Corpus.resolve("not-a-urn")
      assert {:error, :bad_urn} = Corpus.resolve("")
      assert {:error, :bad_urn} = Corpus.resolve(nil)
    end

    test "reports a well-formed but nonexistent URN as not_found" do
      assert {:error, :not_found} = Corpus.resolve("pramana:cbeta.T:T9999_001@p0001a01")
    end
  end

  describe "verify/2 — the central guarantee" do
    test "accepts a genuine quotation", ctx do
      assert Guard.verify(ctx.urn, "如是我聞")
      assert Guard.verify(ctx.urn, ctx.content)
    end

    test "tolerates surrounding whitespace but not altered characters", ctx do
      assert Guard.verify(ctx.urn, "  如是我聞  ")
      refute Guard.verify(ctx.urn, "如是我闻"), "simplified 闻 is a different character"
    end

    test "rejects a quotation that is not in the span", ctx do
      refute Guard.verify(ctx.urn, "舍利弗白佛言")
    end

    test "rejects a plausible-looking fabricated URN" do
      refute Guard.verify("pramana:cbeta.T:T0262_001@p9999a01", "如是我聞")
    end

    test "rejects a real quote attached to the wrong URN", ctx do
      # The subtlest failure: both the text and the citation exist, but not together.
      other = "pramana:cbeta.T:T0262_001@p0001a06"
      assert Guard.verify(ctx.urn, "如是我聞")
      refute Guard.verify(other, "如是我聞")
    end

    test "rejects a quote with one character silently changed", ctx do
      # This is the damaging case: it reads correctly to anyone not checking.
      refute Guard.verify(ctx.urn, "如是我聞：一時佛住王舍國")
    end
  end

  describe "check/2" do
    test "reports the actual text alongside the verdict", ctx do
      finding = Guard.check(ctx.urn, "如是我闻")

      assert finding.verdict == :quote_mismatch
      assert finding.actual == ctx.content
      assert finding.quoted == "如是我闻"
    end

    test "a URN with no quotation is checked for existence only", ctx do
      assert %{verdict: :ok, quoted: nil} = Guard.check(ctx.urn)
    end

    test "invariant #7: generated text is not citable as source" do
      # Translation layers arrive in Phase 3. Proving the rule now with a synthetic
      # span keeps the guard from being retrofitted around existing content later.
      span = %{content: "Thus have I heard", provenance: %{method: "llm"}}
      assert Guard.check_span(span, "Thus have I heard").verdict == :not_citable_as_source

      human = %{content: "Thus have I heard", provenance: %{method: "human"}}
      assert Guard.check_span(human, "Thus have I heard").verdict == :ok
    end
  end

  describe "extract_urns/1" do
    test "finds URNs in the forms a model actually emits" do
      text = """
      The sūtra opens 「如是我聞」【pramana:cbeta.T:T0262_001@p0001a05】, and see also
      pramana:cbeta.T:T0262_001@p0001a06 as well as (pramana:sc.pali:mn1@1.1).
      """

      assert Guard.extract_urns(text) == [
               "pramana:cbeta.T:T0262_001@p0001a05",
               "pramana:cbeta.T:T0262_001@p0001a06",
               "pramana:sc.pali:mn1@1.1"
             ]
    end

    test "de-duplicates while preserving order" do
      text = "pramana:a.b:c@1 then pramana:x.y:z@2 then pramana:a.b:c@1"
      assert Guard.extract_urns(text) == ["pramana:a.b:c@1", "pramana:x.y:z@2"]
    end

    test "returns nothing for text without citations" do
      assert Guard.extract_urns("A paragraph with no citations at all.") == []
    end

    # A URN AT THE END OF A SENTENCE KEPT THE FULL STOP AND RESOLVED TO NOTHING.
    #
    # `.` is legal inside a locator — `sc.ms:mn1@1.1` — so the pattern must admit it, and
    # it therefore swallowed the period closing the sentence. The guard then reported
    # `:not_found` for a perfectly good citation: a false accusation rather than a missed
    # one, in the place where citations mostly live, which is prose.
    #
    # `evals/` could not see it because its gold citations are constructed rather than
    # written in sentences. Found 2026-09-02 while building `Pramana.Repair`.
    test "a URN closing a sentence does not keep the punctuation" do
      assert Guard.extract_urns("As stated at pramana:cbeta.T:T0262_001@p0001a05.") ==
               ["pramana:cbeta.T:T0262_001@p0001a05"]

      for trailing <- [",", ";", ":", "!", "?", ")", "】", "」"] do
        assert Guard.extract_urns("see pramana:a.b:c@1" <> trailing) == ["pramana:a.b:c@1"],
               "failed on #{trailing}"
      end
    end

    # And a locator that legitimately CONTAINS a period keeps it. SuttaCentral segment ids
    # are `1.1`, and trimming them would break every Pāli citation in the corpus.
    test "an internal period is part of the locator and survives" do
      assert Guard.extract_urns("(pramana:sc.ms:mn1@1.1)") == ["pramana:sc.ms:mn1@1.1"]
    end
  end

  describe "check_output/1 — post-generation verification" do
    test "passes output whose citations are all genuine", ctx do
      output = "The sūtra opens 「如是我聞」【#{ctx.urn}】."
      result = Guard.check_output(output)

      assert result.ok?
      assert result.checked == 1
      assert result.failed == 0
      # Asserting the quote was actually PAIRED and byte-compared. Without this the
      # test passes even when pairing is broken and the guard silently degrades to
      # existence-checking, which is precisely the bug this suite once missed.
      assert result.verified_quotes == 1
      assert result.existence_only == 0
      assert [%{quoted: "如是我聞"}] = result.findings
    end

    test "a bare URN with no quotation is reported as existence-only, not verified", ctx do
      result = Guard.check_output("See #{ctx.urn} for the opening.")

      assert result.ok?
      assert result.verified_quotes == 0
      assert result.existence_only == 1
    end

    test "catches a fabricated citation in otherwise plausible prose" do
      output = """
      As the Lotus Sūtra states, 「一切眾生皆有佛性」【pramana:cbeta.T:T0262_003@p0012b07】,
      which established the doctrine.
      """

      result = Guard.check_output(output)

      refute result.ok?
      assert result.failed == 1
      assert [%{verdict: :not_found}] = result.findings
    end

    test "catches a real citation whose quotation was altered", ctx do
      output = "The sūtra opens 「如是我聞：一時佛住舍衛國」【#{ctx.urn}】."
      result = Guard.check_output(output)

      refute result.ok?
      assert [%{verdict: :quote_mismatch, actual: actual}] = result.findings
      assert actual == ctx.content
    end

    test "reports each citation separately in mixed output", ctx do
      output = """
      First 「如是我聞」【#{ctx.urn}】 is genuine.
      Second 「捏造的經文」【pramana:cbeta.T:T0262_001@p9999a99】 is not.
      """

      result = Guard.check_output(output)

      assert result.checked == 2
      assert result.failed == 1
      assert Enum.map(result.findings, & &1.verdict) == [:ok, :not_found]
    end

    test "output with no citations passes but reports nothing checked" do
      result = Guard.check_output("A confident paragraph citing nothing.")

      assert result.ok?
      assert result.checked == 0
    end

    # ▸ F1 REGRESSION — repeated URNs are assessed independently
    #
    # The bug: `check_output/1` built a Map keyed by URN, keeping only the last
    # associated quote. A fabricated quote followed by a genuine one with the
    # same URN was silently dropped, and the guard reported `ok? true` for output
    # containing an unverified invention.
    #
    # Fix: every occurrence is tracked by its byte position in the text, so
    # the same URN appearing multiple times yields one independent finding per
    # occurrence.
    test "repeated URN with a fabricated then genuine quote fails on the fabrication", ctx do
      output = """
      The sūtra begins 「INVENTED WORDS」【#{ctx.urn}】.
      It also opens 「#{ctx.content}」【#{ctx.urn}】.
      """

      result = Guard.check_output(output)

      assert result.checked == 2, "both occurrences must be checked independently"
      assert result.failed == 1, "the fabricated quote must fail independently"
      refute result.ok?, "a fabrication in any occurrence must make ok? false"

      assert [
               %{verdict: :quote_mismatch, source_offset: first_off},
               %{verdict: :ok, source_offset: second_off}
             ] = result.findings

      assert first_off < second_off, "findings must be in document order"
      assert is_integer(first_off) and first_off >= 0
    end

    test "repeated URN with genuine then fabricated quote fails on the second", ctx do
      output =
        "It opens 「#{ctx.content}」【#{ctx.urn}】. " <>
          "But also claims 「MADE UP TEXT」【#{ctx.urn}】."

      result = Guard.check_output(output)

      assert result.checked == 2
      assert result.failed == 1
      refute result.ok?

      assert [
               %{verdict: :ok, source_offset: first_off},
               %{verdict: :quote_mismatch, source_offset: second_off}
             ] = result.findings

      assert first_off < second_off
    end

    test "repeated URN in separate paragraphs are all independently checked", ctx do
      output = """
      First para: 「#{ctx.content}」【#{ctx.urn}】.

      Second para: 「ALSO INVENTED」【#{ctx.urn}】.

      Third para: 「又引」【#{ctx.urn}】.
      """

      result = Guard.check_output(output)

      assert result.checked == 3
      assert result.failed == 2
      assert result.verified_quotes == 1

      assert [
               %{verdict: :ok},
               %{verdict: :quote_mismatch},
               %{verdict: :quote_mismatch}
             ] = result.findings
    end

    test "blank quotations remain independent existence checks, never verified quotes", ctx do
      output = "Empty 「」【#{ctx.urn}】. Space only 「   」【#{ctx.urn}】."
      result = Guard.check_output(output)
      assert result.checked == 2
      assert result.failed == 0
      assert result.verified_quotes == 0
      assert result.existence_only == 2

      assert [%{quoted: nil, source_offset: first}, %{quoted: nil, source_offset: second}] =
               result.findings

      assert first < second
      refute Guard.verify(ctx.urn, "")
      refute Guard.verify(ctx.urn, "   ")
      assert Guard.verify(ctx.urn, "如是我聞")
    end
  end

  describe "extract_urns/1 — +2 locator suffix" do
    test "preserves +N locator extension (F1 regression)" do
      assert Guard.extract_urns("pramana:derge.D:toh1@1.1a.1+2") ==
               ["pramana:derge.D:toh1@1.1a.1+2"]
    end

    test "preserves +N in context of prose" do
      assert Guard.extract_urns("see pramana:derge.D:toh1@1.1a.1+2 for details.") ==
               ["pramana:derge.D:toh1@1.1a.1+2"]
    end

    test "multiple +N locators in one paragraph" do
      text = "first pramana:derge.D:toh1@1.1a.1+2 then pramana:derge.D:toh2@2.1b.3+5"

      assert Guard.extract_urns(text) == [
               "pramana:derge.D:toh1@1.1a.1+2",
               "pramana:derge.D:toh2@2.1b.3+5"
             ]
    end
  end
end
