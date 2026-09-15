defmodule Pramana.Segment.TaishoCorpusTest do
  @moduledoc """
  Segmentation checks against the real T0262. Tagged `:corpus`; excluded (visibly)
  when `raw/` is absent.

  The offset test here is the one that matters most in the whole project: it proves
  every citable span can be sliced back out of the stored body exactly. Everything
  downstream — the citation guard, retrieval, the reader — assumes it.
  """
  use ExUnit.Case, async: true

  @moduletag :corpus

  alias Pramana.Normalize.CBETA
  alias Pramana.Normalize.IR
  alias Pramana.Segment.Taisho
  alias Pramana.URN

  setup_all do
    root = Application.get_env(:pramana, :project_root) || File.cwd!()
    xml = root |> Path.join("raw/cbeta/T/T09/T09n0262.xml") |> File.read!()
    {:ok, ir} = CBETA.normalize(xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
    {:ok, segments} = Taisho.segments(ir, source: "cbeta", witness: "T")
    {:ok, ir: ir, segments: segments, body: IR.body(ir)}
  end

  test "one segment per non-empty line", ctx do
    assert length(ctx.segments) == IR.content_line_count(ctx.ir)
    assert length(ctx.segments) > 5000
  end

  test "every segment's BYTE offsets slice its exact content out of the body", ctx do
    # binary_part/3 is O(1); this is the path the citation guard uses on every answer.
    bad =
      Enum.reject(ctx.segments, fn seg ->
        binary_part(ctx.body, seg.byte_start, seg.byte_end - seg.byte_start) == seg.content
      end)

    assert bad == [], "#{length(bad)} segments have byte offsets that do not resolve"
  end

  test "character offsets agree with byte offsets on a sample", ctx do
    # Character offsets are what clients use. Checking all 5000+ by String.slice/3 is
    # O(n) each and takes ~18s, so verify a spread rather than the whole corpus; the
    # byte-offset test above is the exhaustive one.
    sample = Enum.take_every(ctx.segments, 25)

    bad =
      Enum.reject(sample, fn seg ->
        String.slice(ctx.body, seg.char_start, seg.char_end - seg.char_start) == seg.content
      end)

    assert bad == []
    assert length(sample) > 100
  end

  test "every content hash matches its content", ctx do
    bad =
      Enum.reject(ctx.segments, fn seg ->
        :crypto.hash(:sha256, seg.content) |> Base.encode16(case: :lower) == seg.content_sha256
      end)

    assert bad == []
  end

  test "every URN is unique and parses", ctx do
    urns = Enum.map(ctx.segments, & &1.urn)
    assert length(urns) == length(Enum.uniq(urns))

    bad = Enum.reject(urns, &match?({:ok, _}, URN.parse(&1)))
    assert bad == []
  end

  test "every URN carries a juan, since the Taishō numbers fascicles", ctx do
    without = Enum.filter(ctx.segments, &is_nil(&1.juan))
    assert without == [], "#{length(without)} segments lack a juan"
    assert Enum.map(ctx.segments, & &1.juan) |> Enum.uniq() |> Enum.sort() == Enum.to_list(1..7)
  end

  test "a known passage resolves to the expected URN", ctx do
    seg = Enum.find(ctx.segments, &String.contains?(&1.content, "如是我聞"))

    assert seg.urn =~ ~r/\Apramana:cbeta\.T:T0262_001@p\d{4}[abc]\d{2}\z/
    assert seg.juan == 1
  end

  test "the variant apparatus survives into segment metadata", ctx do
    with_apparatus = Enum.filter(ctx.segments, &Map.has_key?(&1.meta, "apparatus"))
    assert length(with_apparatus) > 700

    seg = Enum.find(ctx.segments, &(&1.urn =~ "p0001b20"))
    assert [%{"lem" => "龜", "rdgs" => [%{"text" => "丘"} | _]}] = seg.meta["apparatus"]
  end
end
