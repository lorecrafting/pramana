defmodule Pramana.Normalize.Tei84000.GlossaryTest do
  @moduledoc """
  Reading a translator's glossary.

  The load-bearing part is the attestation: most of the Sanskrit in these glossaries is a
  reconstruction of what stood in a lost Indic original, and 84000 says so on every term.
  Dropping that would turn a scholar's inference into a quotation.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Tei84000.Glossary

  defp tei(items) do
    """
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>
      <div type="translation"><p>Not the glossary.</p></div>
      <div type="glossary"><list type="glossary">#{items}</list></div>
    </body></text></TEI>
    """
  end

  defp gloss(id, body), do: ~s(<item><gloss type="term" xml:id="#{id}">#{body}</gloss></item>)

  defp term(lang, type, text) do
    lang_attr = if lang == "en", do: "", else: ~s( xml:lang="#{lang}")
    type_attr = if type, do: ~s( type="#{type}"), else: ""
    "<term#{type_attr}#{lang_attr}>#{text}</term>"
  end

  describe "a glossed term" do
    setup do
      xml =
        tei(
          gloss(
            "UT22084-051-001-6000",
            term("en", "translationMain", "pillar") <>
              term("en", "translationAlternative", "pillars") <>
              term("Sa-Ltn", "sourceUnspecified", "yūpa") <>
              term("Bo-Ltn", "attestedSource", "mchod sdong") <>
              term("bo", "attestedSource", "མཆོད་སྡོང་།") <>
              ~s(<note type="definition"><p>Ceremonial columns.</p></note>)
          )
        )

      {:ok, [entry]} = Glossary.parse(xml)
      {:ok, entry: entry}
    end

    test "carries the term in every language the edition gives", %{entry: entry} do
      assert entry.english == "pillar"
      assert entry.sanskrit == "yūpa"
      assert entry.tibetan == "མཆོད་སྡོང་།"
      assert entry.wylie == "mchod sdong"
    end

    test "says how each form is known", %{entry: entry} do
      # `yūpa` is what a scholar reconstructs behind the Tibetan, not what a Sanskrit
      # manuscript says; the Tibetan IS what the Degé prints. Same row, different status.
      assert entry.sanskrit_attestation == "unspecified"
      assert entry.tibetan_attestation == "source"
    end

    test "keeps the alternative rendering apart from the chosen one", %{entry: entry} do
      assert entry.english_alternatives == ["pillars"]
    end

    test "keeps the definition, which is the translator's reasoning", %{entry: entry} do
      assert entry.definition == "Ceremonial columns."
    end

    test "keeps 84000's own id, so the entry can be found in the published TEI", %{entry: entry} do
      assert entry.gloss_id == "UT22084-051-001-6000"
    end
  end

  describe "attestation" do
    test "each of 84000's kinds maps to one of ours" do
      for {published, ours} <- [
            {"attestedSource", "source"},
            {"attestedDictionary", "dictionary"},
            {"attestedOther", "other"},
            {"sourceUnspecified", "unspecified"}
          ] do
        {:ok, [entry]} = Glossary.parse(tei(gloss("g1", term("Sa-Ltn", published, "dharma"))))
        assert entry.sanskrit_attestation == ours
      end
    end

    test "a term with no type is unspecified rather than assumed attested" do
      {:ok, [entry]} = Glossary.parse(tei(gloss("g1", term("Sa-Ltn", nil, "dharma"))))

      assert entry.sanskrit_attestation == "unspecified"
    end
  end

  describe "what is not a glossary entry" do
    test "the translation itself is not read" do
      # The same file holds the translation, and `Pramana.Normalize.Tei84000` reads that.
      {:ok, entries} = Glossary.parse(tei(""))

      assert entries == []
    end

    test "a file with no glossary yields none" do
      xml = "<TEI xmlns=\"http://www.tei-c.org/ns/1.0\"><text><body><p>x</p></body></text></TEI>"

      assert Glossary.parse(xml) == {:ok, []}
    end

    test "an alternative identical to the main rendering is not an alternative" do
      # 84000 lists the same English twice when a term is glossed in more than one place.
      xml =
        tei(
          gloss(
            "g1",
            term("en", "translationMain", "higher knowledge") <>
              term("en", nil, "higher knowledge") <>
              term("Sa-Ltn", "sourceUnspecified", "abhijñā")
          )
        )

      {:ok, [entry]} = Glossary.parse(xml)

      assert entry.english == "higher knowledge"
      assert entry.english_alternatives == []
    end
  end
end
