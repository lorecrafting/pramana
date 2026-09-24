defmodule PramanaWeb.MCP.ProvenanceShapeTest do
  @moduledoc """
  `CLAUDE.md` invariant #4, enforced structurally.

  The rule is that a Japanese sectarian commentary must never be presentable as an
  Indian sūtra. `docs/ARCHITECTURE.md` argues the enforcement that matters is the
  **response shape**, not a prompt: a model cannot flatten results into one
  undifferentiated pile if the response was never flat. A prompt is a request; a shape
  is a property.

  So these tests assert the SHAPE — that buckets exist, are keyed by the provenance
  axes, are labelled in plain language, and keep their contents separate — rather than
  checking that particular texts came back. A shape test survives corpus changes; a
  content test does not.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias PramanaWeb.MCP.Tools.GetOutline
  alias PramanaWeb.MCP.Tools.Search

  defp load!(work_id, volume, number, line, provenance) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt>
      <title level="m">#{provenance[:title]}</title>
      <author>#{provenance[:attributed_author]}</author>
    </titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>
    <cb:mulu level="1" type="品">序品</cb:mulu>
    <lb n="0001a01"/>#{line}
    </body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: volume, number: number)
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
  end

  setup do
    # The case the invariant exists for: the same doctrinal phrase in an Indic sūtra in
    # Chinese translation, a Chinese exegete's commentary on it, and a Japanese
    # sectarian commentary. All three are Classical Chinese; only provenance separates
    # them.
    load!("T0262", 9, "0262", "一切眾生悉有佛性",
      title: "妙法蓮華經",
      attributed_author: "姚秦 鳩摩羅什譯",
      composition_origin: "indic",
      text_role: "root",
      division: "法華部",
      division_en: "Lotus"
    )

    load!("T1718", 34, "1718", "一切眾生悉有佛性者釋曰",
      title: "妙法蓮華經文句",
      attributed_author: "隋 智顗說",
      composition_origin: "chinese",
      text_role: "commentary",
      division: "經疏部",
      division_en: "Sūtra commentary"
    )

    load!("T2203", 56, "2203", "一切眾生悉有佛性和尚釋",
      title: "法華義疏",
      attributed_author: "日本 聖德太子",
      composition_origin: "japanese",
      text_role: "commentary",
      division: "諸宗部",
      division_en: "Sectarian works"
    )

    :ok
  end

  defp payload(response),
    do: response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text") |> Jason.decode!()

  defp search!(params), do: elem(Search.execute(params, %{}), 1) |> payload()

  describe "search response shape" do
    test "results arrive in buckets, never as a flat list" do
      data = search!(%{query: "一切眾生悉有佛性", limit: 20})

      assert is_list(data["groups"])
      # A flat `results` key at the top level would let a caller ignore the grouping.
      refute Map.has_key?(data, "results")
    end

    test "every bucket is keyed by BOTH provenance axes and carries a count" do
      for group <- search!(%{query: "一切眾生悉有佛性", limit: 20})["groups"] do
        assert is_binary(group["composition_origin"])
        assert is_binary(group["text_role"])
        assert is_integer(group["count"])
        assert group["count"] == length(group["results"])
      end
    end

    test "every bucket says in plain language what it is" do
      labels =
        search!(%{query: "一切眾生悉有佛性", limit: 20})["groups"]
        |> Enum.map(& &1["label"])

      # The axis values alone are only unmissable to someone who already knows the
      # vocabulary — and that is not the reader who mis-attributes.
      assert "Indic-composed root scripture" in labels
      assert "Japanese-composed commentary" in labels
      assert "Chinese-composed commentary" in labels
    end

    test "the three traditions land in three separate buckets" do
      groups = search!(%{query: "一切眾生悉有佛性", limit: 20})["groups"]

      origins = groups |> Enum.map(& &1["composition_origin"]) |> Enum.sort()
      assert origins == ~w(chinese indic japanese)
    end

    test "a bucket never contains a work from another origin" do
      for group <- search!(%{query: "一切眾生悉有佛性", limit: 20})["groups"],
          hit <- group["results"] do
        assert hit["provenance"]["composition_origin"] == group["composition_origin"]
        assert hit["provenance"]["text_role"] == group["text_role"]
      end
    end

    test "bucket order is deterministic and does not imply precedence" do
      # Alphabetical would always put "chinese" ahead of "indic", quietly suggesting a
      # ranking the corpus does not have. Largest first, ties broken deterministically.
      groups = search!(%{query: "一切眾生悉有佛性", limit: 20})["groups"]
      counts = Enum.map(groups, & &1["count"])

      assert counts == Enum.sort(counts, :desc)
      assert groups == search!(%{query: "一切眾生悉有佛性", limit: 20})["groups"]
    end

    test "every hit carries the provenance needed to verify it independently" do
      for group <- search!(%{query: "一切眾生悉有佛性", limit: 20})["groups"],
          hit <- group["results"] do
        assert hit["urn"]
        assert hit["sha256"]

        for axis <- ~w(composition_origin text_role division witness source addressing) do
          assert Map.has_key?(hit["provenance"], axis)
        end
      end
    end

    test "an unattributed work is bucketed as unattributed, not silently merged" do
      load!("T2865", 85, "2865", "一切眾生悉有佛性古逸", title: "敦煌本", attributed_author: nil)

      labels =
        search!(%{query: "一切眾生悉有佛性", limit: 20})["groups"] |> Enum.map(& &1["label"])

      assert "origin unattributed, role uncatalogued" in labels
    end
  end

  describe "provenance filters" do
    test "each one restricts the buckets to what was asked for" do
      for {opts, expected} <- [
            {%{origin: "japanese"}, ~w(japanese)},
            {%{origin: "indic"}, ~w(indic)},
            {%{role: "commentary"}, ~w(chinese japanese)},
            {%{role: "root"}, ~w(indic)},
            {%{exclude_origin: "japanese"}, ~w(chinese indic)}
          ] do
        params = Map.merge(%{query: "一切眾生悉有佛性", limit: 20}, opts)

        origins =
          search!(params)["groups"] |> Enum.map(& &1["composition_origin"]) |> Enum.sort()

        assert origins == expected, "#{inspect(opts)} produced #{inspect(origins)}"
      end
    end

    test "excluding later commentary leaves only the scripture" do
      # The question this whole design exists to answer: what does the sūtra itself say,
      # as opposed to what later traditions say about it.
      data = search!(%{query: "一切眾生悉有佛性", limit: 20, origin: "indic", role: "root"})

      assert [group] = data["groups"]
      assert group["label"] == "Indic-composed root scripture"
    end
  end

  describe "get_outline provenance" do
    test "an outline says what kind of text it describes" do
      # An outline is often the first thing fetched about a work, so it is where a
      # reader decides what the text is.
      data = elem(GetOutline.execute(%{work_id: "T2203"}, %{}), 1) |> payload()

      assert data["composition_origin"] == "japanese"
      assert data["text_role"] == "commentary"
      assert data["provenance_label"] == "Japanese-composed commentary"
      assert data["attributed_author"] == "日本 聖德太子"
      assert data["witness"] == "T"
    end

    test "a Japanese commentary's outline is distinguishable from a translation's" do
      japanese = elem(GetOutline.execute(%{work_id: "T2203"}, %{}), 1) |> payload()
      indic = elem(GetOutline.execute(%{work_id: "T0262"}, %{}), 1) |> payload()

      refute japanese["provenance_label"] == indic["provenance_label"]
    end
  end

  describe "search modes" do
    test "every documented mode reaches the MCP search boundary" do
      # Ordinary MCP dispatch; ColdStartTest owns the independent VM/load-order contract.
      for m <- ~w(phrase ngram terms auto hybrid) do
        assert {:reply, _, _} = Search.execute(%{query: "佛性", limit: 1, mode: m}, %{}),
               "mode #{m} failed"
      end
    end
  end
end
