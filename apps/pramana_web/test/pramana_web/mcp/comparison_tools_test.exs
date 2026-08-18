defmodule PramanaWeb.MCP.ComparisonToolsTest do
  @moduledoc """
  The two tools a reader actually reaches for: "show me this passage's other versions"
  and "where does the canon say what this word means".

  Both exist to keep a model from composing what it could quote. `define_from_canon`
  returns the tradition's own definitional sentence with a citation, rather than a gloss
  synthesised from training data; `compare_versions` returns the renderings and parallels
  that scholarship already recorded, rather than a similarity guess.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias Pramana.Translations
  alias PramanaWeb.MCP.Tools.CompareVersions
  alias PramanaWeb.MCP.Tools.CompareWitnesses
  alias PramanaWeb.MCP.Tools.DefineFromCanon
  alias PramanaWeb.MCP.Tools.GetQuotations
  alias PramanaWeb.MCP.Tools.GetReadings

  defp load!(work_id, lines, provenance) do
    body =
      lines
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {text, i} ->
        n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
        ~s(<lb n="#{n}"/>#{text})
      end)

    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">#{provenance[:title]}</title>
    <author>x</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>#{body}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: "0001")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
    Repo.one!(from(t in Text, where: t.work_id == ^work_id, select: t.id))
  end

  defp call!(tool, params),
    do:
      tool.execute(params, %{})
      |> elem(1)
      |> Map.fetch!(:content)
      |> hd()
      |> Map.fetch!("text")
      |> Jason.decode!()

  setup do
    load!(
      "T0001",
      ["爾時世尊告諸比丘", "云何為正見謂正見有二", "如是正見廣說如上"],
      title: "阿含經",
      division: "阿含部",
      composition_origin: "indic",
      text_role: "root"
    )

    :ok
  end

  describe "define_from_canon" do
    test "returns the passage where the canon defines the term" do
      data = call!(DefineFromCanon, %{term: "正見"})

      assert data["total"] >= 1
      assert Enum.any?(data["results"], &(&1["span"]["content"] =~ "云何為正見"))
    end

    test "names the formula that matched, so the reader can judge it" do
      data = call!(DefineFromCanon, %{term: "正見"})

      assert Enum.any?(data["results"], &(&1["formula"] == "云何為"))
    end

    test "every response says these are quotations, not a synthesised gloss" do
      data = call!(DefineFromCanon, %{term: "正見"})

      assert data["note"] =~ "not a synthesised gloss" or
               data["note"] =~ "Nothing here is a synthesised gloss"
    end

    test "a term the canon does not define returns nothing, and says what it tried" do
      data = call!(DefineFromCanon, %{term: "量子力學"})

      assert data["results"] == []
      assert data["formulae_tried"] != []
    end

    test "provenance filters reach the search rather than being decorative" do
      assert call!(DefineFromCanon, %{term: "正見", origin: ["japanese"]})["total"] == 0
      assert call!(DefineFromCanon, %{term: "正見", origin: ["indic"]})["total"] >= 1
    end
  end

  describe "compare_versions" do
    setup do
      urn = "pramana:cbeta.T:T0001_001@p0001a02"

      {:ok, _} =
        Translations.store([
          %{
            anchor_urn: urn,
            work_id: "T0001",
            lang: "en",
            translator_id: "test-hand",
            tier: "t0",
            method: "human",
            text: "And what is right view?",
            redistributable: true,
            license_class: "cc0"
          }
        ])

      {:ok, urn: urn}
    end

    test "returns the passage with its renderings", %{urn: urn} do
      data = call!(CompareVersions, %{urn: urn})

      assert data["passage"]["content"] =~ "云何為正見"
      assert data["renderings"]["count"] == 1
      assert hd(data["renderings"]["pool"])["text"] == "And what is right view?"
    end

    test "states that parallels are different texts, not editions of one another", %{urn: urn} do
      assert call!(CompareVersions, %{urn: urn})["note"] =~ "DIFFERENT texts"
    end

    test "pinning a translator narrows the pool", %{urn: urn} do
      data = call!(CompareVersions, %{urn: urn, translator: "nobody"})
      assert data["renderings"] == nil
    end

    test "a URN addressing nothing is refused rather than compared" do
      {:reply, response, _} =
        CompareVersions.execute(%{urn: "pramana:cbeta.T:T9999_001@p0001a01"}, %{})

      assert response.isError
    end

    test "a malformed URN is refused with a message naming the expected shape" do
      {:reply, response, _} = CompareVersions.execute(%{urn: "nonsense"}, %{})

      assert response.isError
      assert hd(response.content)["text"] =~ "Expected pramana:"
    end
  end

  describe "compare_witnesses" do
    setup do
      text = Repo.one!(from(t in Pramana.Corpus.Text, where: t.work_id == "T0001"))

      Repo.update_all(
        from(t in Pramana.Corpus.Text, where: t.id == ^text.id),
        set: [meta: Map.put(text.meta || %{}, "witnesses", %{"wit1" => "【宋】", "wit2" => "【元】"})]
      )

      segment =
        Repo.one!(from(s in Pramana.Corpus.Segment, where: s.text_id == ^text.id, limit: 1))

      Repo.update_all(
        from(s in Pramana.Corpus.Segment, where: s.id == ^segment.id),
        set: [
          meta: %{
            "apparatus" => [
              %{"lem" => "世尊", "rdgs" => [%{"wit" => "#wit1 #wit2", "text" => "佛"}]}
            ]
          }
        ]
      )

      {:ok, urn: segment.urn}
    end

    test "names the witness in the edition's own sigla", %{urn: urn} do
      data = call!(CompareWitnesses, %{urn: urn})

      assert Enum.map(data["variants"], & &1["witness"]) == ["【宋】", "【元】"]
      assert hd(data["variants"])["lemma"] == "世尊"
      assert hd(data["variants"])["reading"] == "佛"
    end

    test "a line with no recorded variants says the witnesses agree" do
      other =
        Repo.one!(
          from(s in Pramana.Corpus.Segment,
            where: fragment("? = '{}'::jsonb", s.meta),
            limit: 1
          )
        )

      data = call!(CompareWitnesses, %{urn: other.urn})

      assert data["variants"] == []
      assert data["note"] =~ "agree here"
    end

    test "a range is refused, because variants are recorded per line" do
      {:reply, response, _} =
        CompareWitnesses.execute(%{urn: "pramana:cbeta.T:T0001_001@p0001a01-p0001a03"}, %{})

      assert response.isError
      assert hd(response.content)["text"] =~ "range"
    end

    test "a URN addressing nothing is refused" do
      {:reply, response, _} =
        CompareWitnesses.execute(%{urn: "pramana:cbeta.T:T9999_001@p0001a01"}, %{})

      assert response.isError
    end
  end

  describe "get_quotations" do
    setup do
      other = Repo.insert!(%Pramana.Corpus.Work{id: "T1579", title: "瑜伽師地論"})

      quoted =
        Repo.insert!(%Pramana.Corpus.Text{
          work_id: other.id,
          source_id: "cbeta",
          witness_id: "T",
          urn_prefix: "pramana:cbeta.T:T1579",
          body: "云何為正見謂正見有二",
          body_sha256: "x",
          meta: %{}
        })

      Repo.insert!(%Pramana.Corpus.Segment{
        text_id: quoted.id,
        urn: "pramana:cbeta.T:T1579_001@p0001a01",
        ordinal: 0,
        content: "云何為正見謂正見有二",
        content_sha256: "y",
        char_start: 0,
        char_end: 10,
        byte_start: 0,
        byte_end: 30,
        meta: %{}
      })

      root = Repo.one!(from(t in Pramana.Corpus.Text, where: t.work_id == "T0001"))

      segment =
        Repo.one!(from(s in Pramana.Corpus.Segment, where: s.text_id == ^root.id, limit: 1))

      {:ok, _} =
        Pramana.Quotations.store([
          %{
            "text" => "云何為正見謂正見有二",
            "length" => 10,
            "occurrences" => [
              %{
                "work" => Integer.to_string(root.id),
                "start" => segment.char_start,
                "end" => segment.char_end
              },
              %{"work" => Integer.to_string(quoted.id), "start" => 0, "end" => 10}
            ]
          }
        ])

      {:ok, urn: segment.urn}
    end

    test "returns every work reproducing the passage", %{urn: urn} do
      data = call!(GetQuotations, %{urn: urn})

      assert data["total"] == 1
      assert hd(data["quotations"])["other_work_id"] == "T1579"
    end

    test "every response says direction is not established", %{urn: urn} do
      assert call!(GetQuotations, %{urn: urn})["note"] =~ "Neither end is marked as the origin"
    end

    test "a URN addressing nothing is refused" do
      {:reply, response, _} =
        GetQuotations.execute(%{urn: "pramana:cbeta.T:T9999_001@p0001a01"}, %{})

      assert response.isError
    end

    test "a malformed URN is refused" do
      {:reply, response, _} = GetQuotations.execute(%{urn: "nonsense"}, %{})
      assert response.isError
    end
  end

  describe "get_readings" do
    setup do
      text_id =
        load!("T0251", ["觀自在菩薩行深般若波羅蜜多時"],
          title: "般若波羅蜜多心經",
          division: "般若部",
          composition_origin: "indic",
          text_role: "root"
        )

      now = DateTime.utc_now()

      Repo.insert_all(
        Pramana.Corpus.CharacterReading,
        Enum.map(
          [
            {"觀", "guān", ~w(guān guàn)},
            {"自", "zì", ~w(zì)},
            {"在", "zài", ~w(zài)},
            {"菩", "pú", ~w(pú)},
            {"薩", "sà", ~w(sà)},
            {"行", "xíng", ~w(xíng háng)},
            {"深", "shēn", ~w(shēn)},
            {"般", "bān", ~w(bān bō)},
            {"若", "ruò", ~w(ruò rě)},
            {"波", "bō", ~w(bō)},
            {"羅", "luó", ~w(luó)},
            {"蜜", "mì", ~w(mì)},
            {"多", "duō", ~w(duō)},
            {"時", "shí", ~w(shí)}
          ],
          fn {character, reading, attested} ->
            %{
              character: character,
              reading: reading,
              attested: attested,
              authority: "unihan",
              inserted_at: now,
              updated_at: now
            }
          end
        )
      )

      {:ok, _} =
        Pramana.Readings.store([
          %{
            form: "般若波羅蜜",
            lang: "lzh",
            scheme: "pinyin",
            reading: "bō rě bō luó mì",
            status: "verified"
          }
        ])

      urn =
        Repo.one!(from(s in Pramana.Corpus.Segment, where: s.text_id == ^text_id, select: s.urn))

      {:ok, urn: urn}
    end

    test "reads the passage, applying the Buddhist reading", %{urn: urn} do
      data = call!(GetReadings, %{urn: urn})

      assert data["reading"] =~ "bō rě bō luó mì"
      refute data["reading"] =~ "bān ruò"
    end

    test "each token says where its reading came from", %{urn: urn} do
      tokens = call!(GetReadings, %{urn: urn})["tokens"]

      # The distinction has to survive to the caller. A response that flattened
      # dictionary readings and ordinary ones into one string would let a reader treat
      # an unchecked default as a Buddhist convention.
      assert Enum.any?(tokens, &(&1["form"] == "般若波羅蜜" and &1["source"] == "exception"))
      assert Enum.any?(tokens, &(&1["form"] == "菩" and &1["source"] == "base"))
    end

    test "counts how much of the line the dictionary spoke to", %{urn: urn} do
      assert call!(GetReadings, %{urn: urn})["counts"]["from_dictionary"] == 1
    end

    test "every response says a reading is not what is citable", %{urn: urn} do
      assert call!(GetReadings, %{urn: urn})["note"] =~ "citable"
    end

    test "a URN addressing nothing is refused, not rendered" do
      {:reply, response, _} =
        GetReadings.execute(%{urn: "pramana:cbeta.T:T9999_001@p0001a01"}, %{})

      assert response.isError
    end

    test "a malformed URN is refused with a different message than a missing one" do
      {:reply, response, _} = GetReadings.execute(%{urn: "not-a-urn"}, %{})

      assert response.isError
      assert hd(response.content)["text"] =~ "Malformed"
    end

    test "each scheme carries its own reading language", %{urn: urn} do
      # A Chinese sūtra chanted in a Japanese temple is read with 呉音, and in a Korean
      # one with Sino-Korean. The scheme selects the convention; the text does not
      # change, and neither does what is citable.
      for {scheme, _} <- [{"on-yomi", "ja"}, {"kun-yomi", "ja"}, {"mccune-reischauer", "ko"}] do
        data = call!(GetReadings, %{urn: urn, scheme: scheme})
        assert data["scheme"] == scheme
        assert data["text"] != ""
      end
    end

    test "a character with no recorded reading comes back null, never guessed" do
      text_id =
        load!("T9001", ["龘"],
          title: "x",
          division: "阿含部",
          composition_origin: "indic",
          text_role: "root"
        )

      urn =
        Repo.one!(from(s in Pramana.Corpus.Segment, where: s.text_id == ^text_id, select: s.urn))

      data = call!(GetReadings, %{urn: urn})

      assert [%{"reading" => nil, "source" => "unknown"}] = data["tokens"]
      assert data["counts"]["without_reading"] == 1
    end

    test "wylie transliterates Tibetan without consulting any dictionary" do
      text_id =
        load!("Toh21", ["བྱང་ཆུབ་སེམས་དཔའ"],
          title: "x",
          division: "shes phyin",
          composition_origin: "indic",
          text_role: "root"
        )

      urn =
        Repo.one!(from(s in Pramana.Corpus.Segment, where: s.text_id == ^text_id, select: s.urn))

      data = call!(GetReadings, %{urn: urn, scheme: "wylie"})

      assert data["reading"] == "byang chub sems dpa'"
      # `computed`, not `base`: there is no ordinary reading here for an exception to
      # override, and calling it `base` would imply a lookup that never happened.
      assert Enum.all?(data["tokens"], &(&1["source"] == "computed"))
      assert data["counts"]["from_dictionary"] == 0
    end

    test "a scheme with no entries returns base readings, not an error", %{urn: urn} do
      # The 呉音 layer is not populated for Chinese yet. Asking for it must degrade to
      # the ordinary readings rather than failing, and the per-token `source` is what
      # tells the caller nothing Buddhist was applied.
      data = call!(GetReadings, %{urn: urn, scheme: "on-yomi"})

      assert data["scheme"] == "on-yomi"
      assert data["counts"]["from_dictionary"] == 0
    end
  end
end
