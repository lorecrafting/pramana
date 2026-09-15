defmodule Pramana.Normalize.Catalogue84000Test do
  @moduledoc """
  Reading 84000's RDF catalogue.

  One record describes the same text four times — as an Indic work, a Tibetan
  translation, a Degé printing and an English translation — and each description holds a
  different title. Taking the right one from the right description is the whole job.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Catalogue84000, as: Catalogue

  defp rdf(body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:skos="http://www.w3.org/2004/02/skos/core#"
             xmlns:owl="http://www.w3.org/2002/07/owl#"
             xmlns:bdo="http://purl.bdrc.io/ontology/core/">#{body}</rdf:RDF>
    """
  end

  defp description(subject, body) do
    ~s(<rdf:Description rdf:about="http://purl.84000.co/resource/core/#{subject}">#{body}</rdf:Description>)
  end

  defp label(lang, text), do: ~s(<skos:prefLabel xml:lang="#{lang}">#{text}</skos:prefLabel>)

  defp full_record do
    rdf(
      description("WAITOH113", label("sa-x-iast", "Saddharmapuṇḍarīka") <> label("en", "Indic")) <>
        description(
          "WATTOH113",
          label("bo", "abstract bo") <>
            ~s(<owl:sameAs rdf:resource="http://purl.bdrc.io/resource/WA0RK0113"/>)
        ) <>
        description(
          "WEKDTOH113",
          label("bo", "དམ་པའི་ཆོས་པད་མ་དཀར་པོ།") <>
            ~s(<owl:sameAs rdf:resource="http://purl.bdrc.io/resource/MW22084_0113"/>)
        ) <>
        description(
          "WAETOH113",
          label("en", "The White Lotus of the Good Dharma") <>
            ~s(<bdo:creator><bdo:AgentAsCreator><bdo:agent>) <>
            ~s(<bdo:Person rdf:about="http://purl.84000.co/resource/core/person-1">) <>
            label("en", "Peter Alan Roberts") <>
            ~s(</bdo:Person></bdo:agent></bdo:AgentAsCreator></bdo:creator>)
        )
    )
  end

  describe "which description a title comes from" do
    test "the Tibetan is the Degé's, not the abstract work's" do
      # This corpus holds the Degé printing. Taking any `bo` label would attribute the
      # abstract work's title to the edition on the shelf.
      {:ok, record} = Catalogue.parse(full_record())

      assert record.titles["bo"] == "དམ་པའི་ཆོས་པད་མ་དཀར་པོ།"
    end

    test "the Sanskrit is the Indic work's" do
      {:ok, record} = Catalogue.parse(full_record())

      assert record.titles["sa"] == "Saddharmapuṇḍarīka"
    end

    test "the English is the translation's, not the Indic work's" do
      {:ok, record} = Catalogue.parse(full_record())

      assert record.titles["en"] == "The White Lotus of the Good Dharma"
    end

    test "a translator's name is a name, not a title" do
      # `skos:prefLabel` inside a `bdo:Person` is the person. Reading every English label
      # would put "Peter Alan Roberts" in the title field of a sūtra.
      {:ok, record} = Catalogue.parse(full_record())

      assert record.translators == ["Peter Alan Roberts"]
      refute record.titles["en"] =~ "Roberts"
    end
  end

  describe "identity" do
    test "the Tōhoku number comes from the record, not the filename" do
      {:ok, record} = Catalogue.parse(full_record())

      assert record.toh == "toh113"
    end

    test "a sub-numbered work keeps its part" do
      {:ok, record} = Catalogue.parse(rdf(description("WAITOH1-1", label("en", "Going Forth"))))

      assert record.toh == "toh1-1"
    end

    test "the BDRC id of the Degé printing is what a IIIF manifest is addressed by" do
      {:ok, record} = Catalogue.parse(full_record())

      assert record.bdrc["derge"] == "MW22084_0113"
      assert record.bdrc["tibetan"] == "WA0RK0113"
    end
  end

  describe "records that do not have everything" do
    test "an untranslated work still yields its titles, with no translators" do
      # 84000 has published 385 of ~1,169 Tōhoku numbers; the catalogue covers all of
      # them, and the ones with no translation are exactly the ones this is for.
      record =
        rdf(
          description("WAITOH200", label("sa-x-iast", "lokānuvartanasūtra")) <>
            description("WEKDTOH200", label("bo", "འཇིག་རྟེན།"))
        )

      {:ok, parsed} = Catalogue.parse(record)

      assert parsed.titles == %{"sa" => "lokānuvartanasūtra", "bo" => "འཇིག་རྟེན།"}
      assert parsed.translators == []
    end

    test "a record with no titles at all is empty rather than partial" do
      {:ok, record} = Catalogue.parse(rdf(description("WAITOH999", "")))

      assert record.titles == %{}
      assert record.toh == "toh999"
    end
  end
end
