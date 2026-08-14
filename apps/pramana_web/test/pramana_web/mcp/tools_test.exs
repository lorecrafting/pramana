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
  alias PramanaWeb.MCP.Tools.GetPassage
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
end
