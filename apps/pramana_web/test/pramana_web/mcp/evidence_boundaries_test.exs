defmodule PramanaWeb.MCP.EvidenceBoundariesTest do
  @moduledoc "The public report tool must preserve replay boundaries and report its input refusal."
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.EvidenceInput
  alias Pramana.Normalize.CBETA
  alias PramanaWeb.MCP.Tools.VerifyReport

  @urn "pramana:cbeta.T:T0262_001@p0001a01"
  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt>
  <title level="m">Fixture</title></titleStmt></fileDesc></teiHeader>
  <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>如是我聞。</body></text></TEI>
  """

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T")
    :ok
  end

  defp json(report) do
    {:reply, response, %{}} = VerifyReport.execute(%{report: report}, %{})
    response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text") |> Jason.decode!()
  end

  test "a real asserted replay cannot manufacture a pass for a surrounding quotation" do
    replay =
      "```pramana-replay\n" <>
        Jason.encode!(%{tool: "get_passage", arguments: %{urn: @urn}, assert: %{urn: @urn}}) <>
        "\n```"

    original = "「如是我聞。\n" <> replay <> "\n」 [#{@urn}]"
    result = json(original)
    assert result["status"] == "incomplete"
    refute result["ok?"]
    assert result["counts"]["verified_replays"] == 1
    assert result["counts"]["verified_quotes"] == 0
    assert result["repair"]["text"] == original
    assert result["repair"]["edits"] == []
  end

  test "MCP uses the same input budget as the reader and returns no partial pass" do
    original = String.duplicate("x", EvidenceInput.max_bytes() + 1)
    result = json(original)
    refute result["ok?"]
    assert result["status"] == "incomplete"
    assert result["refusal"]["code"] == "input_too_large"
    assert result["repair"]["refusal"]["code"] == "input_too_large"
    assert result["repair"]["edits"] == []
  end
end
