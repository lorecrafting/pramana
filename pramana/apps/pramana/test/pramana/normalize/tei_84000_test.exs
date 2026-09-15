defmodule Pramana.Normalize.Tei84000Test do
  @moduledoc """
  Reading an 84000 translation.

  The tests that matter here are about what is *not* taken: a journal name from a
  footnote is not a title, an endnote is not the translation, and a folio number that
  could be computed from the page range is taken from the reference instead, because the
  two disagree and the reference is the one that matches the Tibetan.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Tei84000

  defp tei(opts) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0">
      <teiHeader><fileDesc>
        <titleStmt>
          <title type="mainTitle" xml:lang="en">The Dhāraṇī for Secret Relics</title>
          <title type="mainTitle" xml:lang="Sa-Ltn">Guhya­dhātu­dhāraṇī</title>
          <title type="mainTitle" xml:lang="bo">གསང་བ་རིང་བསྲེལ་གྱི་གཟུངས།</title>
          <title type="mainTitle" xml:lang="Bo-Ltn">gsang ba ring bsrel gyi gzungs</title>
          <author role="translatorMain">Translated by Dylan Esler under the patronage
            of 84000</author>
          <author role="translatorEng">Dylan Esler</author>
        </titleStmt>
        <editionStmt><edition>v 1.0.14 <date>2024</date></edition></editionStmt>
        <sourceDesc>#{opts[:bibls]}</sourceDesc>
      </fileDesc></teiHeader>
      <text><body>
        <div type="summary"><p>A summary, which renders no folio.</p></div>
        <div type="translation">#{opts[:body]}</div>
      </body></text>
    </TEI>
    """
  end

  defp bibl(key, volumes) do
    entries =
      Enum.map_join(volumes, fn {number, start_page, end_page} ->
        ~s(<volume number="#{number}" start-page="#{start_page}" end-page="#{end_page}"/>)
      end)

    """
    <bibl key="#{key}" type="text">
      <biblScope>Degé Kangyur, vol. whatever</biblScope>
      <location work="UT4CZ5369">#{entries}</location>
    </bibl>
    """
  end

  defp folio(cref), do: ~s(<ref cRef="#{cref}" type="folio"/>)

  describe "what the file says about itself" do
    test "every place in the Degé that it renders" do
      xml =
        tei(bibls: bibl("toh507", [{88, 2, 14}]) <> bibl("toh883", [{101, 243, 255}]), body: "")

      {:ok, parsed} = Tei84000.parse(xml)

      assert parsed.locations == [
               %{toh: "toh507", volume: 88, start_page: 2, end_page: 14},
               %{toh: "toh883", volume: 101, start_page: 243, end_page: 255}
             ]
    end

    test "titles in every language it publishes them in" do
      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh507", [{88, 2, 14}]), body: ""))

      assert parsed.titles["en"] == "The Dhāraṇī for Secret Relics"
      assert parsed.titles["Sa-Ltn"] == "Guhya­dhātu­dhāraṇī"
      assert parsed.titles["bo"] == "གསང་བ་རིང་བསྲེལ་གྱི་གཟུངས།"
      assert parsed.titles["Bo-Ltn"] == "gsang ba ring bsrel gyi gzungs"
    end

    test "the translator, not the sentence about the translator" do
      # `translatorMain` is prose — "Translated by X under the patronage of…" — and
      # storing it as the attribution would put a paragraph where a name goes.
      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh507", [{88, 2, 14}]), body: ""))

      assert parsed.translators == ["Dylan Esler"]
    end

    test "the edition, which is what decides between two copies of one translation" do
      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh507", [{88, 2, 14}]), body: ""))

      assert parsed.edition == "v 1.0.14 2024"
    end
  end

  describe "the body" do
    test "folio references and text arrive in document order" do
      body = "#{folio("F.1.b")}Homage to all the buddhas.#{folio("F.2.a")}Thus did I hear."

      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh507", [{88, 2, 14}]), body: body))

      assert parsed.events == [
               {:folio, "F.1.b"},
               {:text, "Homage to all the buddhas."},
               {:folio, "F.2.a"},
               {:text, "Thus did I hear."}
             ]
    end

    test "endnotes are not the translation" do
      body =
        folio("F.1.b") <>
          "Thus did I hear<note place=\"end\">Kamalaśīla reads this differently.</note> at one time."

      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh507", [{88, 2, 14}]), body: body))

      text = parsed.events |> Enum.filter(&match?({:text, _}, &1)) |> Enum.map_join(&elem(&1, 1))

      assert text =~ "Thus did I hear"
      assert text =~ "at one time"
      refute text =~ "Kamalaśīla"
    end

    test "a title inside a note is a journal, not this text's title" do
      body =
        folio("F.1.b") <>
          ~s(Thus did I hear<note><title type="mainTitle" xml:lang="en">Indo-Iranian Journal</title></note>.)

      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh507", [{88, 2, 14}]), body: body))

      assert parsed.titles["en"] == "The Dhāraṇī for Secret Relics"
    end

    test "text outside the translation division renders no folio and is skipped" do
      # The summary and the introduction are 84000's own scholarship about the text.
      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh507", [{88, 2, 14}]), body: ""))

      assert parsed.events == []
    end

    test "an explicit volume crossing is kept, because most crossings have none" do
      body = folio("F.91.a") <> ~s(<ref cRef="V32" type="volume"/>) <> folio("F.1.b")

      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh11", [{31, 2, 182}]), body: body))

      assert {:volume, 32} in parsed.events
    end

    test "a volume reference naming another witness is not a Degé volume" do
      # `RAS.60.a2` is a Royal Asiatic Society manuscript. Reading it as a volume number
      # would move the anchor into a volume that has nothing to do with this text.
      body = ~s(<ref cRef="RAS.60.a2" type="volume"/>) <> folio("F.1.b")

      {:ok, parsed} = Tei84000.parse(tei(bibls: bibl("toh310", [{72, 310, 313}]), body: body))

      refute Enum.any?(parsed.events, &match?({:volume, _}, &1))
    end
  end
end
