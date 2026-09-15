defmodule PramanaWeb.MCP.GetGlossesTest do
  @moduledoc """
  Which commentaries explain **this line**, by deterministic 科文 lemma match.

  Nothing had exercised `Commentary.glosses_on/2` through the tool before this file, so the
  contract a model depends on was untested: that the commentary's own URN leads, that the
  match method and confidence travel with every gloss, and that a line nothing explains
  returns an empty list rather than a nearby guess.

  The last one is the point of the whole feature. A lemma anchors where its window occurs
  **exactly once** in the root; where it does not anchor, the answer is silence, and silence
  here means *we looked and found no gloss*, never *here is the closest thing*.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.CommentaryAlignment
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias PramanaWeb.MCP.Tools.GetGlosses

  import Ecto.Query

  defp load!(work_id, number, line, provenance) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">#{provenance[:title]}</title>
    <author>#{provenance[:attributed_author]}</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>#{line}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: number)
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)

    Repo.one!(from(t in Text, where: t.work_id == ^work_id, select: t.id))
  end

  @root_urn "pramana:cbeta.T:T0262_001@p0001a01"
  @commentary_urn "pramana:cbeta.T:T1718_001@p0001a01"

  setup do
    root_id =
      load!("T0262", "0262", "如是我聞一時佛住",
        title: "妙法蓮華經",
        attributed_author: "姚秦 鳩摩羅什譯",
        composition_origin: "indic",
        text_role: "root"
      )

    commentary_id =
      load!("T1718", "1718", "如是我聞一時佛住者信成就也",
        title: "法華文句",
        attributed_author: "隋 智顗說",
        composition_origin: "chinese",
        text_role: "commentary"
      )

    %CommentaryAlignment{}
    |> Ecto.Changeset.change(%{
      # EIGHT characters, because `lemma_is_long_enough` requires it: the alignment rule
      # anchors on an 8-character window, and a shorter lemma is not evidence of anything.
      lemma: "如是我聞一時佛住",
      lemma_sha256: :crypto.hash(:sha256, "如是我聞一時佛住") |> Base.encode16(case: :lower),
      length: 8,
      commentary_text_id: commentary_id,
      commentary_work_id: "T1718",
      commentary_urn: @commentary_urn,
      commentary_char_start: 0,
      commentary_char_end: 8,
      root_text_id: root_id,
      root_work_id: "T0262",
      root_urn: @root_urn,
      root_char_start: 0,
      root_char_end: 8,
      method: "lemma_match",
      confidence: "probable"
    })
    |> Repo.insert!()

    :ok
  end

  defp json(params) do
    {:reply, response, %{}} = GetGlosses.execute(params, %{})

    response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text") |> Jason.decode!()
  end

  # Twenty of 109 and twenty of twenty are the same list. 27 root lines in the corpus
  # carry more than the default limit, one of them 109, and a caller handed the first
  # twenty had no way to learn that. Rules 22, 44, 54.
  # Invariant #1: no unattributed text leaves the API. A lemma is a verbatim quotation of
  # the root line, and it shipped without its sha256 or offsets until 2026-09-03 — the
  # domain carried them and this tool re-shapes the map, so a field added there reached
  # nobody. `Architecture.BoundariesTest` now fails on a tool that returns text with no
  # sha256 beside it.
  test "a lemma travels with what verifies it" do
    [gloss] = json(%{urn: @root_urn})["glosses"]

    assert gloss["lemma_sha256"] ==
             Base.encode16(:crypto.hash(:sha256, gloss["lemma"]), case: :lower)

    assert gloss["root_offsets"]["char_start"] |> is_integer()
    assert gloss["root_offsets"]["char_end"] > gloss["root_offsets"]["char_start"]
    assert gloss["commentary_offsets"]["char_end"] > gloss["commentary_offsets"]["char_start"]
  end

  test "reports how many glosses exist, not only how many it returned" do
    payload = json(%{urn: @root_urn})

    assert payload["returned"] == length(payload["glosses"])
    assert payload["total"] == payload["returned"]
    refute payload["truncated"]
  end

  test "says so when it truncates" do
    second_gloss_on_the_same_line()

    payload = json(%{urn: @root_urn, limit: 1})

    assert payload["returned"] == 1
    assert payload["total"] == 2
    assert payload["truncated"]
    # Longest lemma first, so truncation keeps the most substantial gloss.
    assert hd(payload["glosses"])["length"] == 9
  end

  # A second commentary explaining the same root line — the ordinary case for a much-read
  # sūtra, and the one the default limit of 20 hides at 109.
  defp second_gloss_on_the_same_line do
    [root_id, commentary_id] =
      Enum.map(["T0262", "T1718"], fn work ->
        Repo.one!(from(t in Text, where: t.work_id == ^work, select: t.id))
      end)

    lemma = "如是我聞一時佛住王"

    %CommentaryAlignment{}
    |> Ecto.Changeset.change(%{
      lemma: lemma,
      lemma_sha256: Base.encode16(:crypto.hash(:sha256, lemma), case: :lower),
      length: 9,
      commentary_text_id: commentary_id,
      commentary_work_id: "T1718",
      commentary_urn: @commentary_urn,
      commentary_char_start: 20,
      commentary_char_end: 29,
      root_text_id: root_id,
      root_work_id: "T0262",
      root_urn: @root_urn,
      root_char_start: 0,
      root_char_end: 9,
      method: "lemma_match",
      confidence: "probable"
    })
    |> Repo.insert!()
  end

  test "returns the commentaries that gloss this line" do
    payload = json(%{urn: @root_urn})

    assert payload["root_urn"] == @root_urn
    assert payload["commentaries"] == ["T1718"]
    assert [gloss] = payload["glosses"]

    # The commentary's OWN address leads: a caller needs to know where the explanation
    # lives before it needs the characters that matched.
    assert gloss["commentary_urn"] == @commentary_urn
    assert gloss["title"] == "法華文句"
    assert gloss["attributed_author"] == "隋 智顗說"
    assert gloss["composition_origin"] == "chinese"
    assert gloss["lemma"] == "如是我聞一時佛住"
    assert gloss["length"] == 8
  end

  test "the match method and its confidence travel with every gloss" do
    [gloss] = json(%{urn: @root_urn})["glosses"]

    # Invariant #5: a deterministic match says so, and still never claims certainty.
    assert gloss["method"] == "lemma_match"
    assert gloss["confidence"] == "probable"
    assert json(%{urn: @root_urn})["method"] == "lemma_match"
  end

  test "a line nothing explains returns an empty list, not a nearby guess" do
    payload = json(%{urn: "pramana:cbeta.T:T0262_001@p9999z99"})

    assert payload["glosses"] == []
    assert payload["commentaries"] == []
    # The note must still explain what a caller is looking at, because an empty list is
    # the answer that is easiest to misread.
    assert payload["note"]
  end

  test "limit caps the glosses returned" do
    assert %{"glosses" => glosses} = json(%{urn: @root_urn, limit: 1})
    assert length(glosses) == 1
  end

  test "the response is replayable against a named corpus" do
    payload = json(%{urn: @root_urn})

    assert Map.has_key?(payload, "bake_id")
    assert payload["replay"]["tool"] == "get_glosses"
    assert payload["replay"]["arguments"]["urn"] == @root_urn
  end
end
