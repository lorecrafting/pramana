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
  alias Pramana.Release
  alias Pramana.Translations
  alias PramanaWeb.MCP.ReplayExecutor
  alias PramanaWeb.MCP.Tools.VerifyReport

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt><title level="m">妙法蓮華經</title>
  <author>姚秦 鳩摩羅什譯</author></titleStmt></fileDesc></teiHeader>
  <text><body><milestone n="1" unit="juan"/>
  <lb n="0001c17"/>鳩摩羅什奉　詔譯
  <lb n="0001c18"/>王舍城耆闍崛山中
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
    assert payload["status"] == "no_checkable_evidence"
    refute payload["ok?"]
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

  test "a failed citation says HOW it failed, not only that it did" do
    # The words are real and one line further on. An author told "one citation failed" goes
    # looking for a fabrication; told `wrong_address`, they fix a reference.
    payload = json(~s|It reads "王舍城耆闍崛山中" [#{@urn}].|)

    refute payload["citations"]["ok?"]
    assert [finding] = payload["citations"]["findings"]
    assert finding["reason"] == "wrong_address"
    assert payload["note"] =~ "wrong_address"
  end

  test "punctuation an editor added is diagnosed as the editor's, not the text's" do
    payload = json(~s|It reads "鳩摩羅什奉　詔譯，" [#{@urn}].|)

    assert [finding] = payload["citations"]["findings"]
    assert finding["reason"] == "editorial_punctuation"
  end

  test "a replay record is re-executed through the real tools" do
    report = """
    The corpus holds one work.

    ```pramana-replay
    {"tool": "get_outline", "arguments": {"work_id": "T0262"}}
    ```
    """

    assert [replay] = json(report)["replays"]
    assert replay["status"] == "executed"
    assert json(report)["status"] == "incomplete"
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

  test "an unresolved scholarly citation prevents a valid quotation from making the report green" do
    payload = json(~s("鳩摩羅什奉　詔譯" [#{@urn}]. Also T. 262, 99a1.))
    assert payload["citations"]["verified_quotes"] == 1
    assert payload["status"] == "incomplete"
    assert payload["counts"]["unresolved_foreign"] == 1
    refute payload["ok?"]
    assert payload["note"] =~ "could not be resolved"
  end

  test "an existing bare URN is not a verified quotation or a complete report" do
    payload = json("See #{@urn}.")
    assert payload["status"] == "incomplete"
    assert payload["counts"]["existence_only"] == 1
    refute payload["ok?"]
  end

  test "a real asserted get_passage replay is not also counted as a bare citation" do
    report =
      "```pramana-replay\n" <>
        Jason.encode!(%{tool: "get_passage", arguments: %{urn: @urn}, assert: %{urn: @urn}}) <>
        "\n```"

    payload = json(report)
    assert payload["status"] == "verified"
    assert payload["ok?"]
    assert payload["citations"]["checked"] == 0
    assert payload["counts"]["verified_replays"] == 1
    assert payload["resolved_text"] == report
  end

  test "invalid assertion types return a structured incomplete result, not an exception" do
    payload =
      json("""
      ```pramana-replay
      {"tool":"search","arguments":{},"assert":42}
      ```
      """)

    assert payload["status"] == "incomplete"
    assert [%{"reason" => "invalid_assertions"}] = payload["malformed"]
    refute payload["ok?"]
  end

  test "a real emitted receipt cannot falsely refute a same-source, changed-rendering report" do
    {:ok, bake} = Pramana.Bake.record(%{"mode" => "report_release_test"})

    rendering = %{
      anchor_urn: @urn,
      work_id: "T0262",
      lang: "en",
      translator_id: "fixture",
      tier: "t0",
      method: "human",
      text: "compassion",
      redistributable: true,
      license_class: "cc0"
    }

    {:ok, _} = Translations.store([rendering])
    {:ok, first} = Release.stamp()
    executor = ReplayExecutor.executor()
    {:ok, original} = executor.("search_translations", %{"query" => "compassion"})
    assert [_] = original["results"]
    assert original["bake_id"] == bake.id
    assert original["release_id"] == first.release_id

    report = receipt_report(original, %{"results" => original["results"]})
    assert json(report)["status"] == "verified"

    # Change the existing row, not just a count. The emitted receipt, not an invented id,
    # binds the earlier answer; #17 supplies the new content identity after this edit.
    during_execution =
      Pramana.Report.verify(report,
        executor: fn tool, arguments ->
          {:ok, _} = Translations.store([%{rendering | text: "equanimity"}])
          {:ok, _} = Release.stamp()
          executor.(tool, arguments)
        end
      )

    assert during_execution.status == :incomplete
    assert [%{status: :unverifiable, detail: detail}] = during_execution.replays
    assert detail =~ "replay response"
    assert during_execution.checked_identity.release_id == first.release_id
    second = Release.current()
    assert first.source_bake_id == second.source_bake_id
    assert first.translations_count == second.translations_count
    refute first.release_id == second.release_id
    {:ok, changed} = executor.("search_translations", %{"query" => "compassion"})
    assert changed["results"] == []

    payload = json(report)
    assert payload["status"] == "incomplete"
    assert payload["counts"]["replay_failures"] == 0
    assert [%{"status" => "unverifiable", "identity_field" => "release_id"}] = payload["replays"]

    assert payload["checked_identity"] == %{
             "bake_id" => bake.id,
             "release_id" => second.release_id
           }

    assert payload["note"] =~ "neither confirmed nor refuted"
    refute payload["ok?"]
    assert Repo.get!(Pramana.Corpus.Release, first.id) == first
    assert Repo.aggregate(Pramana.Corpus.Release, :count) == 2
  end

  test "a lost selection is unavailable, not repaired by the read-only checker" do
    {:ok, _} = Release.stamp()
    {:ok, original} = ReplayExecutor.executor().("get_passage", %{"urn" => @urn})
    report = receipt_report(original, %{"urn" => @urn})
    Repo.delete_all(Pramana.Release.Selection)
    payload = json(report)
    assert payload["status"] == "incomplete"
    assert [%{"status" => "unverifiable"}] = payload["replays"]
    assert payload["release_id"] == nil
    assert Release.current_id() == nil
    assert Repo.aggregate(Pramana.Corpus.Release, :count) == 1
  end

  test "legacy MCP reports explicitly disclose the missing release identity" do
    payload =
      json(
        "```pramana-replay\n" <>
          Jason.encode!(%{tool: "get_passage", arguments: %{urn: @urn}, assert: %{urn: @urn}}) <>
          "\n```"
      )

    assert payload["status"] == "verified"
    assert [%{"identity_scope" => "unrecorded"}] = payload["replays"]
    assert payload["note"] =~ "no retrieval release identity"
  end

  defp receipt_report(receipt, assertions) do
    record =
      receipt["replay"]
      |> Map.merge(Map.take(receipt, ["bake_id", "release_id"]))
      |> Map.put("assert", assertions)

    "```pramana-replay\n" <> Jason.encode!(record) <> "\n```"
  end
end
