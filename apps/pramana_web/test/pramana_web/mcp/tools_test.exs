defmodule PramanaWeb.MCP.ToolsTest do
  @moduledoc """
  The MCP tools are a thin transport over `Pramana.Corpus` and `Pramana.Guard`. These
  tests check the contract that matters at the boundary: responses are structured,
  provenance always travels with the text, and a bad citation is refused rather than
  answered.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias PramanaWeb.MCP.Tools.GetGlosses
  alias PramanaWeb.MCP.Tools.GetPassage
  alias PramanaWeb.MCP.Tools.GetWorksByPerson
  alias PramanaWeb.MCP.Tools.Search
  alias PramanaWeb.MCP.Tools.SearchTranslations
  alias PramanaWeb.MCP.Tools.VerifyCitation

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title>
    <author>姚秦 鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001c17"/>鳩摩羅什奉　詔譯
  </body></text></TEI>
  """

  @urn "pramana:cbeta.T:T0262_001@p0001c17"

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

  # The response struct uses atom fields (:content, :isError), but the content items
  # inside it use STRING keys, matching the MCP wire format.
  defp payload(response), do: response |> text_content() |> Jason.decode!()

  defp text_content(response) do
    response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text")
  end

  describe "get_passage" do
    test "returns structured data, not prose" do
      {:reply, response, _frame} = GetPassage.execute(%{urn: @urn}, %{})
      data = payload(response)

      assert data["text"] == "鳩摩羅什奉　詔譯"
      assert data["urn"] == @urn
      assert is_map(data["offsets"])
      assert is_map(data["provenance"])
    end

    test "carries a reader deep-link that never poses as the citation" do
      {:reply, response, _frame} = GetPassage.execute(%{urn: @urn}, %{})
      reader = payload(response)["reader"]

      assert reader["url"] == "https://cbetaonline.dila.edu.tw/en/T0262_001"
      # `anchor` is whatever coordinate that edition uses; `anchor_label` names which,
      # because CBETA's linehead and SuttaCentral's segment id are different grammars
      # arriving in the same field.
      assert reader["anchor"] == "T09n0262_p0001c17"
      assert reader["anchor_label"] == "CBETA linehead"

      # The one unverifiable thing this project emits must say so at the boundary, not
      # only in its own module doc.
      assert reader["verified"] == false
      assert reader["granularity"] == "juan"
    end

    test "every response carries a sha256 the caller can verify independently" do
      {:reply, response, _frame} = GetPassage.execute(%{urn: @urn}, %{})
      data = payload(response)

      expected = :crypto.hash(:sha256, data["text"]) |> Base.encode16(case: :lower)
      assert data["sha256"] == expected
    end

    test "provenance travels with the text — invariant #1" do
      {:reply, response, _frame} = GetPassage.execute(%{urn: @urn}, %{})
      prov = payload(response)["provenance"]

      assert prov["composition_origin"] == "indic"
      assert prov["text_role"] == "translation"
      assert prov["witness"] == "T"
      assert prov["license_class"] == "nc"
      assert prov["addressing"] == "canonical"
      assert prov["page"] == "0001"
      assert prov["line"] == 17
    end

    test "refuses a well-formed URN that addresses nothing" do
      {:reply, response, _frame} =
        GetPassage.execute(%{urn: "pramana:cbeta.T:T0262_003@p9999a99"}, %{})

      assert response.isError
      assert text_content(response) =~ "do not cite it"
    end

    test "refuses a malformed URN" do
      {:reply, response, _frame} = GetPassage.execute(%{urn: "not-a-urn"}, %{})
      assert response.isError
    end
  end

  describe "search" do
    test "returns hits GROUPED by origin and role, never a flat list" do
      {:reply, response, _frame} = Search.execute(%{query: "鳩摩羅什"}, %{})
      data = payload(response)

      assert data["mode"] == "hybrid"
      assert data["total"] == 1
      # The grouping is the enforcement mechanism for invariant #4, so it is asserted
      # as a SHAPE. A flat list here would be a regression even if the content is right.
      assert [group] = data["groups"]
      assert group["composition_origin"] == "indic"
      assert group["text_role"] == "translation"
      assert group["count"] == 1
    end

    test "every hit carries a URN and sha256 so it can be verified" do
      {:reply, response, _frame} = Search.execute(%{query: "鳩摩羅什"}, %{})
      hit = payload(response)["groups"] |> hd() |> Map.fetch!("results") |> hd()

      assert hit["urn"] == @urn
      assert hit["sha256"] == :crypto.hash(:sha256, hit["text"]) |> Base.encode16(case: :lower)
      assert hit["provenance"]["composition_origin"] == "indic"
    end

    test "defaults to hybrid and reports which retrievers contributed" do
      {:reply, response, _frame} = Search.execute(%{query: "鳩摩羅什"}, %{})
      data = payload(response)

      assert data["mode"] == "hybrid"
      # No embedding serving is running in tests, so hybrid degrades to lexical — and
      # says so rather than presenting half the evidence as if it were all of it.
      assert data["retrievers"] == ["lexical"]
      assert is_map(data["embedding_coverage"])
    end

    test "an explicit lexical mode still works" do
      {:reply, response, _frame} = Search.execute(%{query: "鳩摩羅什奉詔譯經", mode: "ngram"}, %{})
      assert payload(response)["mode"] == "ngram"
    end

    test "hybrid does not leak its own mode into the lexical retriever" do
      # `mode: :hybrid` means nothing to the lexical stage; passing it through crashed
      # the tool with a raw CaseClauseError.
      {:reply, response, _frame} = Search.execute(%{query: "鳩摩羅什", mode: "hybrid"}, %{})
      refute response.isError
    end

    test "EVERY declared filter actually filters" do
      # A declared-but-unwired parameter is invisible to the unknown-option validator:
      # it is not an unknown key, it is a known key nobody reads. `division` shipped
      # that way and silently returned works from other divisions.
      {:reply, all, _} = Search.execute(%{query: "鳩摩羅什"}, %{})
      assert payload(all)["total"] == 1

      for {param, miss} <- [
            {:origin, "japanese"},
            {:role, "apocryphon"},
            {:division, "疑似部"},
            {:work_id, "T9999"},
            {:juan, 99}
          ] do
        args = Map.merge(%{query: "鳩摩羅什"}, %{param => miss})
        {:reply, response, _} = Search.execute(args, %{})

        assert payload(response)["total"] == 0,
               "#{param} did not filter — it is declared but not wired through"
      end
    end

    test "provenance filters are honoured" do
      {:reply, hit, _} = Search.execute(%{query: "鳩摩羅什", origin: "indic"}, %{})
      assert payload(hit)["total"] == 1

      {:reply, miss, _} = Search.execute(%{query: "鳩摩羅什", origin: "japanese"}, %{})
      assert payload(miss)["total"] == 0
    end

    test "an unknown mode falls back to the default rather than erroring" do
      {:reply, response, _frame} = Search.execute(%{query: "鳩摩羅什", mode: "nonsense"}, %{})
      assert payload(response)["mode"] == "hybrid"
    end

    test "rejects an empty query" do
      {:reply, response, _frame} = Search.execute(%{query: "   "}, %{})
      assert response.isError
    end
  end

  describe "verify_citation" do
    test "confirms a genuine quotation" do
      {:reply, response, _frame} =
        VerifyCitation.execute(%{urn: @urn, quoted_text: "鳩摩羅什奉"}, %{})

      data = payload(response)
      assert data["verdict"] == "ok"
      assert data["verified"] == true
    end

    test "catches a single silently altered character, and shows the real text" do
      # 譯 -> 說. This is the damaging case: it reads correctly to anyone not checking.
      {:reply, response, _frame} =
        VerifyCitation.execute(%{urn: @urn, quoted_text: "鳩摩羅什奉　詔說"}, %{})

      data = payload(response)
      assert data["verdict"] == "quote_mismatch"
      assert data["verified"] == false
      assert data["actual"] == "鳩摩羅什奉　詔譯"
      assert data["explanation"] =~ "does not appear"
    end

    test "reports a fabricated URN rather than returning a plausible answer" do
      {:reply, response, _frame} =
        VerifyCitation.execute(
          %{urn: "pramana:cbeta.T:T0262_003@p0012b07", quoted_text: "一切眾生皆有佛性"},
          %{}
        )

      data = payload(response)
      assert data["verdict"] == "not_found"
      assert data["verified"] == false
    end
  end

  # Two capabilities shipped and were reachable only from the reader and the domain, on a
  # project whose stated purpose is that ANY LLM can do citation-grounded scholarship over
  # it. The MCP surface is the product; a feature it cannot reach is a feature the product
  # does not have.
  describe "search_translations" do
    setup do
      Pramana.Translations.store([
        %{
          anchor_urn: @urn,
          work_id: "T0262",
          lang: "en",
          translator_id: "kumarajiva-en",
          tier: "t0",
          method: "human",
          text: "Translated by Kumārajīva on imperial command.",
          redistributable: true,
          license_class: "cc0"
        }
      ])

      :ok
    end

    test "answers an English phrase with the SOURCE line, not the rendering" do
      {:reply, response, _} =
        SearchTranslations.execute(%{query: "imperial command"}, %{})

      data = payload(response)
      hit = hd(data["results"])

      # The anchor is what a citation may point at.
      assert hit["anchor_urn"] == @urn
      assert hit["rendering_urn"] =~ "#tr:en/"
      assert hit["provenance"]["citable_as_source"] == false
    end

    test "the note tells a model what it may cite, in every match mode" do
      {:reply, response, _} = SearchTranslations.execute(%{query: "imperial command"}, %{})

      assert payload(response)["match"] == "all_terms"
      assert payload(response)["note"] =~ "cite `anchor_urn`, never the translated text"
    end

    test "says when it fell back to matching some of the words" do
      {:reply, response, _} =
        SearchTranslations.execute(%{query: "imperial zzzznotaword"}, %{})

      data = payload(response)
      assert data["match"] == "any_term"
      assert data["note"] =~ "SOME of them"
    end
  end

  describe "get_glosses" do
    test "an empty result says which kind of absence it is" do
      {:reply, response, _} = GetGlosses.execute(%{urn: @urn}, %{})
      data = payload(response)

      assert data["glosses"] == []
      # "No commentary quotes this line" and "no commentary explains it" are different
      # facts, and only the first is what an empty list means.
      assert data["note"] =~ "not that none explains it"
      assert data["method"] == "lemma_match"
    end
  end

  # Rule 60: a capability the MCP surface cannot reach has not shipped. Authority linking
  # landed in the database and nowhere else until this tool existed.
  describe "get_works_by_person" do
    test "says clearly when no work carries that id", %{} do
      {:reply, response, _} = GetWorksByPerson.execute(%{authority_id: "A999999"}, %{})
      data = payload(response)

      assert data["count"] == 0
      # "This translator is absent" and "no work resolved to them" are different facts.
      assert data["note"] =~ "refusal rather than a gap"
    end

    test "reports the total, not the page size" do
      {:reply, response, _} = GetWorksByPerson.execute(%{authority_id: "A999999", limit: 1}, %{})
      data = payload(response)

      # A limit that looks like a total is the denominator failure this project is most
      # prone to; `count` and `returned` are separate for that reason.
      assert Map.has_key?(data, "count")
      assert Map.has_key?(data, "returned")
    end
  end
end
