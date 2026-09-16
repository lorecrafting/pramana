defmodule Pramana.GuardDiagnoseTest do
  @moduledoc """
  How a quotation failed, not only that it did.

  `:quote_mismatch` covers a fabricated sūtra, a scholar quoting from an edition that
  punctuates differently, and a citation naming the first of the two lines it quotes. Those
  are three defects in three layers, and a guard that reports them identically teaches people
  to ignore it — which is what happened to `integrity` while it called 1,228 X texts broken.

  The two verdicts that change how a refusal reads get the most attention here:
  `:wrong_address`, where the model found real text and mis-cited it, and
  `:absent_from_corpus`, which is the only one of the five that is a fabrication.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Loader
  alias Pramana.Guard
  alias Pramana.Normalize.CBETA

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt><title level="m">妙法蓮華經</title>
  <author>姚秦 鳩摩羅什譯</author></titleStmt></fileDesc></teiHeader>
  <text><body><milestone n="1" unit="juan"/>
  <lb n="0001c17"/>如是我聞一時佛住
  <lb n="0001c18"/>王舍城耆闍崛山中
  </body></text></TEI>
  """

  @first "pramana:cbeta.T:T0262_001@p0001c17"

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "translation"}
      )

    :ok
  end

  defp reason(urn, quoted), do: urn |> Guard.check(quoted) |> Guard.diagnose() |> Map.get(:reason)

  test "a verdict that is already specific is not second-guessed" do
    # `:not_found` says what is wrong with the address. Asking how the characters differ
    # would add nothing, and there are no characters to compare.
    assert reason("pramana:cbeta.T:T9999_001@p0001a01", "如是我聞") == nil
    assert reason(@first, "如是我聞一時佛住") == nil
  end

  test "punctuation the editor added is not a different text" do
    # CBETA's punctuation is a modern editorial addition and is not in the witness, so an
    # edition that punctuates differently is the same passage.
    assert reason(@first, "如是我聞，一時佛住。") == :editorial_punctuation
  end

  test "a quote running into the next line is a citation to tighten, not a false claim" do
    # A Taishō line breaks wherever the block-cutter reached. This quotation is continuous on
    # the printed page and the citation named only its first line.
    assert reason(@first, "如是我聞一時佛住王舍城耆闍崛山中") == :spans_line_boundary
  end

  test "real text at the wrong address indicts the ADDRESS, not the model" do
    # The words are in the corpus, one line further on. That is retrieval or addressing
    # handing back a span whose URN did not travel with it — the inversion worth
    # remembering, because it looks exactly like a hallucination and is not one.
    finding = @first |> Guard.check("王舍城耆闍崛山中") |> Guard.diagnose()

    assert finding.reason == :wrong_address
    assert "pramana:cbeta.T:T0262_001@p0001c18" in finding.found_at
    assert finding.explanation =~ "the text is real"
  end

  test "words that are nowhere in the bake are the fabrication case" do
    finding = @first |> Guard.check("這段文字根本不存在於藏經之中") |> Guard.diagnose()

    assert finding.reason == :absent_from_corpus
    assert finding.explanation =~ "only one"
  end

  test "cheap punctuation diagnosis performs no query, while a wrong-address diagnosis does" do
    cheap = Guard.check(@first, "如是我聞，")
    expensive = Guard.check(@first, "王舍城耆闍崛山中")

    {finding, queries} = Pramana.QueryCapture.capture(fn -> Guard.diagnose(cheap) end)
    assert finding.reason == :editorial_punctuation
    assert queries == []

    {finding, queries} = Pramana.QueryCapture.capture(fn -> Guard.diagnose(expensive) end)
    assert finding.reason == :wrong_address
    assert queries != [], "the positive control must establish that query capture is attached"
    assert Enum.any?(queries, &String.contains?(&1, "segments"))
  end
end
