defmodule PramanaWeb.MCP.VerifyReportTest do
  @moduledoc """
  The whole-report check, end to end through the real executor.

  `Pramana.ReportTest` covers the verification logic with an injected executor. What is
  tested here is what a model actually receives — and above all that the **note leads with
  what was not established**, because a report can be free of failures and still entirely
  unverified.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias PramanaWeb.MCP.ReplayExecutor
  alias PramanaWeb.MCP.Tools.VerifyReport

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt><title level="m">妙法蓮華經</title>
  <author>姚秦 鳩摩羅什譯</author></titleStmt></fileDesc></teiHeader>
  <text><body><milestone n="1" unit="juan"/>
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

  defp json(report) do
    {:reply, response, %{}} = VerifyReport.execute(%{report: report}, %{})

    response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text") |> Jason.decode!()
  end

  test "an empty document is NOT a pass, and the note says so first" do
    payload = json("Some prose with no evidence in it.")

    assert payload["note"] =~ "not a pass"
    assert payload["note"] =~ "unsourced document"
  end

  test "a real quotation byte-compares" do
    payload = json(~s|The text reads "鳩摩羅什奉　詔譯" [#{@urn}].|)

    assert payload["citations"]["ok?"]
    assert payload["citations"]["verified_quotes"] == 1
  end

  test "a fabricated URN is caught" do
    payload = json("See pramana:cbeta.T:T9999_001@p0001a01 for the passage.")

    refute payload["citations"]["ok?"]
    refute payload["ok?"]
  end

  test "a replay record is re-executed through the real tools" do
    report = """
    The corpus holds one work.

    ```pramana-replay
    {"tool": "get_outline", "arguments": {"work_id": "T0262"}}
    ```
    """

    assert [replay] = json(report)["replays"]
    assert replay["status"] == "verified"
    assert replay["tool"] == "get_outline"
  end

  test "a replay naming a tool the executor will not run is an error" do
    # The executor holds an explicit whitelist rather than reading the server registry: a
    # report is untrusted input, and its records name tools chosen by whoever wrote it.
    report = """
    ```pramana-replay
    {"tool": "drop_everything", "arguments": {}}
    ```
    """

    assert [%{"status" => "error"}] = json(report)["replays"]
    refute json(report)["ok?"]
  end

  test "verify_report cannot name itself" do
    # A report that asks to verify a report is a loop, and a loop over untrusted input is a
    # denial of service.
    refute "verify_report" in ReplayExecutor.tools()
  end

  test "the runnable tools are advertised, so a report author knows what is checkable" do
    tools = json("prose")["runnable_tools"]

    assert "survey_corpus" in tools
    assert "search" in tools
  end
end
