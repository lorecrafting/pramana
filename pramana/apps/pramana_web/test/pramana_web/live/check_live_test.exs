defmodule PramanaWeb.CheckLiveTest do
  @moduledoc """
  The screen exists so a person can disbelieve a document, so the tests are about the
  distinctions a verdict list can flatten:

  - a **failed** citation and an **unverifiable** replay must not look the same. The corpus
    changed in the second case and the claim is not refuted; collapsing them is how a
    checker teaches people to ignore it.
  - a citation with no quotation attached was checked for EXISTENCE only, and the summary
    must say so rather than counting it as verified.
  - evidence that could not be parsed must prevent a pass rather than being dropped.
  """
  use PramanaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title>
    <author>姚秦 鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001c17"/>如是我聞一時佛住
  </body></text></TEI>
  """

  @urn "pramana:cbeta.T:T0262_001@p0001c17"

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "root"}
      )

    # A recorded bake, because the verdict this screen exists to keep separate only
    # arises when there IS a current bake to differ from: `Report.verify/2` compares a
    # replay's `bake_id` against `Bake.current_id()`, and with none recorded every replay
    # is simply executed. Without this the `unverifiable` test passes for the wrong
    # reason — it renders `verified` and the assertion is what catches it.
    {:ok, bake} = Pramana.Bake.record(%{"mode" => "check_live_test"})

    %{bake: bake}
  end

  test "renders the form before anything is checked", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/check")

    assert html =~ "Check a report"
    assert html =~ "Paste a report"
  end

  # A quotation needs no markup, but a retrieval claim needs a fenced block nobody would
  # guess. Without the format on the page, the one thing this screen does that nothing else
  # does is unreachable without reading the source — rule 60, one level in.
  test "shows the replay format, because nobody would guess it", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/check")

    assert html =~ "What can I paste?"
    assert html =~ "pramana-replay"
    assert html =~ "survey_corpus"
  end

  test "a true quotation is byte-compared and the report holds", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/check")

    html =
      view
      |> form("form", report: "The sūtra opens 「如是我聞一時佛住」 (#{@urn}).")
      |> render_submit()

    assert html =~ "All checkable quotations and asserted replay values verified"
    assert html =~ "byte-compared against the text"
  end

  test "an altered quotation fails and both readings are shown", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/check")

    html =
      view
      |> form("form", report: "The sūtra opens 「如是我聞一時佛說」 (#{@urn}).")
      |> render_submit()

    assert html =~ "At least one citation or asserted replay value did not hold"
    assert html =~ "the corpus has"
  end

  # A citation with nothing to compare against was checked for existence and no more.
  # Counting it as a verified quote is the overstatement this summary exists to prevent.
  test "a citation with no quotation says it was checked for existence only", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/check")

    html =
      view
      |> form("form", report: "The opening is discussed at #{@urn} and elsewhere.")
      |> render_submit()

    assert html =~ "checked only for EXISTENCE"
  end

  # THE DISTINCTION THE MODULE EXISTS FOR. A replay recorded against another bake cannot be
  # re-run; the report is not shown to be wrong. It must not be rendered as a failure, and
  # it must not pass either.
  test "a replay from another bake is unverifiable, and is not called a failure", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/check")

    report = """
    It occurs everywhere.

    ```pramana-replay
    {"tool": "survey_corpus", "arguments": {"query": "如是我聞"},
     "bake_id": "0000000000000000", "assert": {"total": 1}}
    ```
    """

    html = view |> form("form", report: report) |> render_submit()

    assert html =~ "unverifiable"
    assert html =~ "cannot be re-run here"
    refute html =~ "All checkable quotations and asserted replay values verified"
  end

  test "a replay block nobody can parse prevents a pass rather than being dropped", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/check")

    report = """
    A claim.

    ```pramana-replay
    {this is not json
    ```
    """

    html = view |> form("form", report: report) |> render_submit()

    assert html =~ "Evidence that could not be read"
    assert html =~ "invalid_json"
    refute html =~ "All checkable quotations and asserted replay values verified"
  end

  test "figures with no citation are listed as a prompt, not as a verdict", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/check")

    html =
      view
      |> form("form", report: "The phrase appears 36,775 times across 1,904 works.")
      |> render_submit()

    assert html =~ "Figures with nothing behind them"
    assert html =~ "never a verdict"
  end

  # Refused whole rather than truncated: a silently shortened report would be reported as
  # verified on the half that was read.
  test "an oversized report is refused rather than partly checked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/check")

    html =
      view
      |> form("form", report: String.duplicate("a", 200_001))
      |> render_submit()

    assert html =~ "Nothing was checked"
    refute html =~ "Citations"
  end

  # L3. A checker tells you what is wrong; this tells you what can be done about it, and
  # the state vocabulary is what stops that becoming a more confident version of the same
  # document.
  test "a fabricated quotation is offered a repair that strips the citation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/check")

    html =
      view
      |> form("form", report: "The text says 「這是完全捏造的」 (#{@urn}).")
      |> render_submit()

    assert html =~ "What could be repaired"
    assert html =~ "no_sources"
  end

  test "a citation in the Taishō's own print form is recognised and resolved", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/check")

    html = view |> form("form", report: "As T. 262, 1c17 has it.") |> render_submit()

    assert html =~ "Citations in another scheme"
    assert html =~ "taisho"
  end

  test "the screen is reachable from the nav, which is the whole point of building it", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(href="/check")
  end

  test "the reader exposes the same no-evidence status as the API", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/check")
    view |> form("form", report: "A confident assertion.") |> render_submit()

    assert has_element?(
             view,
             ~s(#verification-result[data-status="no_checkable_evidence"]),
             "not a pass"
           )

    refute has_element?(view, ~s(#verification-result[data-status="verified"]))
  end

  test "unresolved foreign evidence is incomplete, not a green report", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/check")
    report = ~s("如是我聞一時佛住" [#{@urn}]. T. 262, 99a1.)
    view |> form("form", report: report) |> render_submit()
    assert has_element?(view, ~s(#verification-result[data-status="incomplete"]), "incomplete")
    refute has_element?(view, ~s(#verification-result[data-status="verified"]))
  end
end
