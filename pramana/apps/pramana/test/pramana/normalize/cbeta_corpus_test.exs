defmodule Pramana.Normalize.CBETACorpusTest do
  @moduledoc """
  Integration test against the real acquired T0262.

  Skipped when `raw/` is absent, since the corpus is gitignored — we publish the
  pipeline, not the corpus. Run `mix pramana.acquire --source cbeta` first.

  These are conservation checks: the counts must reconcile exactly against the source
  file. Silent loss during normalization is the highest-consequence bug class in this
  project, and it is invisible without assertions like these.
  """
  use ExUnit.Case, async: true

  @moduletag :corpus

  alias Pramana.Normalize.CBETA
  alias Pramana.Normalize.IR
  alias Pramana.URN.Taisho

  @path "raw/cbeta/T/T09/T09n0262.xml"

  setup_all do
    root = Pramana.Paths.data_root()
    xml = root |> Path.join(@path) |> File.read!()
    {:ok, ir} = CBETA.normalize(xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
    {:ok, xml: xml, ir: ir}
  end

  defp count(xml, regex), do: Regex.scan(regex, xml) |> length()

  # Only <lb/> inside <body> starts a line; the <back> apparatus reproduces body text,
  # <lb/> and all, inside its lemmas.
  defp body_lb_count(xml) do
    [_, body] = String.split(xml, "<body>", parts: 2)
    [body, _] = String.split(body, "</body>", parts: 2)
    count(body, ~r/<lb /)
  end

  test "every body line is preserved", %{xml: xml, ir: ir} do
    assert length(ir.lines) == body_lb_count(xml)
  end

  test "line anchors are unique — URN identity depends on it", ctx do
    anchors = Enum.map(ctx.ir.lines, & &1.anchor)
    assert length(anchors) == length(Enum.uniq(anchors))
    assert Enum.all?(anchors, &(&1 != nil))
  end

  test "every anchor parses under the Taishō locator grammar", ctx do
    bad =
      Enum.reject(ctx.ir.lines, fn line ->
        match?({:ok, _}, Taisho.parse_locator("p" <> line.anchor))
      end)

    assert bad == [], "unparseable anchors: #{inspect(Enum.map(bad, & &1.anchor))}"
  end

  test "no apparatus entry is dropped", ctx do
    assert IR.apparatus_count(ctx.ir) == count(ctx.xml, ~r/<app[ >]/)
  end

  test "header metadata is extracted, including the license notice", ctx do
    ir = ctx.ir
    assert ir.title == "妙法蓮華經"
    assert ir.author == "姚秦 鳩摩羅什譯"
    assert ir.juan_count == 7
    # CBETA is non-commercial and requires the header stay intact, so we keep it.
    assert ir.license_notice =~ "non-commercial"
  end

  test "body text contains no apparatus or navigation leakage", ctx do
    body = IR.body(ctx.ir)
    refute String.contains?(body, "校注")
    refute String.contains?(body, "No. 262 [Nos.")
    assert String.contains?(body, "如是我聞")
  end

  test "the line-spanning lemma is split across its two real lines", ctx do
    by_anchor = Map.new(ctx.ir.lines, &{&1.anchor, &1})
    assert by_anchor["0001c16"].text =~ "後秦龜茲國三藏法師"
    assert by_anchor["0001c17"].text == "鳩摩羅什奉　詔譯"
  end

  test "the 龜/丘 variant lands on the line that actually reads 龜", ctx do
    line = Enum.find(ctx.ir.lines, &(&1.anchor == "0001b20"))
    assert String.contains?(line.text, "龜")
    assert Enum.any?(line.apparatus, &match?(%{lem: "龜", rdgs: [%{text: "丘"} | _]}, &1))
  end
end
