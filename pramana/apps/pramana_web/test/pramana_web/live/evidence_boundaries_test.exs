defmodule PramanaWeb.LiveEvidenceBoundariesTest do
  @moduledoc "Reader rendering must not turn a boundary-straddling quotation into a verified report."
  use PramanaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA

  @urn "pramana:cbeta.T:T0262_001@p0001a01"
  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt>
  <title level="m">Fixture</title></titleStmt></fileDesc></teiHeader>
  <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>如是我聞。</body></text></TEI>
  """

  test "the screen renders incomplete, not verified, for a quotation enclosing replay JSON", %{
    conn: conn
  } do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T")

    replay =
      "```pramana-replay\n" <>
        Jason.encode!(%{tool: "get_passage", arguments: %{urn: @urn}, assert: %{urn: @urn}}) <>
        "\n```"

    original = "「如是我聞。\n" <> replay <> "\n」 [#{@urn}]"
    {:ok, view, _} = live(conn, ~p"/check")
    view |> form("form", report: original) |> render_submit()

    assert has_element?(
             view,
             "#verification-result[data-status=incomplete]",
             "Verification is incomplete"
           )

    refute has_element?(
             view,
             "#verification-result[data-status=verified]",
             "All checkable quotations and asserted replay values verified"
           )
  end
end
