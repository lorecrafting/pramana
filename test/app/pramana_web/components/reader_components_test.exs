defmodule PramanaWeb.ReaderComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PramanaWeb.ReaderComponents

  describe "provenance_line/1" do
    test "renders provenance axes, title, author, and edition reference" do
      html =
        render_component(&ReaderComponents.provenance_line/1,
          provenance: %{
            composition_origin: "indic",
            text_role: "root",
            work_id: "T0262",
            title: "妙法蓮華經",
            attributed_author: "鳩摩羅什",
            attribution_confidence: "probable",
            division: "法華部",
            witness_name: "Taishō",
            volume: 9,
            page: "0001",
            register: "c",
            line: 17
          }
        )

      assert html =~ "Indic-composed root scripture"
      assert html =~ "T0262"
      assert html =~ "妙法蓮華經"
      assert html =~ "鳩摩羅什"
      assert html =~ "(probable)"
      assert html =~ "法華部"
      assert html =~ "Taishō · vol. 9 · p. 0001c17"
    end

    test "omits attribution confidence when certain or nil" do
      html_certain =
        render_component(&ReaderComponents.provenance_line/1,
          provenance: %{
            composition_origin: "indic",
            text_role: "root",
            attributed_author: "鳩摩羅什",
            attribution_confidence: "certain"
          }
        )

      refute html_certain =~ "(certain)"

      html_nil =
        render_component(&ReaderComponents.provenance_line/1,
          provenance: %{
            composition_origin: "indic",
            text_role: "root",
            attributed_author: "鳩摩羅什",
            attribution_confidence: nil
          }
        )

      refute html_nil =~ "("
    end

    test "renders addressing caveats for derived and edition_page" do
      html_derived =
        render_component(&ReaderComponents.provenance_line/1,
          provenance: %{
            composition_origin: "indic",
            text_role: "root",
            addressing: "derived"
          }
        )

      assert html_derived =~ "derived anchor — no printed page to check against"

      html_edition =
        render_component(&ReaderComponents.provenance_line/1,
          provenance: %{
            composition_origin: "indic",
            text_role: "root",
            addressing: "edition_page"
          }
        )

      assert html_edition =~ "anchored to the printed page, not to a critical edition"

      html_canonical =
        render_component(&ReaderComponents.provenance_line/1,
          provenance: %{
            composition_origin: "indic",
            text_role: "root",
            addressing: "canonical"
          }
        )

      refute html_canonical =~ "anchor"
      refute html_canonical =~ "printed page"
    end

    test "accepts a custom class" do
      html =
        render_component(&ReaderComponents.provenance_line/1,
          provenance: %{composition_origin: "indic", text_role: "root"},
          class: "custom-class-test"
        )

      assert html =~ "custom-class-test"
    end
  end

  describe "citation/1" do
    test "renders URN and sha256 prefix with volume badge when volume is present" do
      html =
        render_component(&ReaderComponents.citation/1,
          span: %{
            urn: "pramana:cbeta.T:T0262_001@p0001c17",
            sha256: "abcdef1234567890abcdef",
            provenance: %{volume: 9}
          }
        )

      assert html =~ "pramana:cbeta.T:T0262_001@p0001c17"
      assert html =~ "sha256:abcdef123456…"
      assert html =~ "vol. 9"
    end

    test "omits volume badge when provenance has no volume" do
      html =
        render_component(&ReaderComponents.citation/1,
          span: %{
            urn: "pramana:suttacentral.pli:sn6.4@sn6.4:1.1",
            sha256: "1234567890abcdef123456",
            provenance: %{}
          }
        )

      assert html =~ "pramana:suttacentral.pli:sn6.4@sn6.4:1.1"
      refute html =~ "vol."
    end
  end

  describe "coverage_note/1" do
    test "renders caveat, coverage note, and confidence note when below strong" do
      html =
        render_component(&ReaderComponents.coverage_note/1,
          caveat: "Corpus caveat message",
          coverage: %{note: "Index coverage note"},
          confidence: %{band: "moderate", note: "Moderate match", top_similarity: 0.68},
          retrievers: ["lexical", "semantic"]
        )

      assert html =~ "Corpus caveat message"
      assert html =~ "Index coverage note"
      assert html =~ "Moderate match"
      assert html =~ "0.68"
      assert html =~ "lexical + semantic"
      refute html =~ "Meaning-based matches were not considered"
    end

    test "omits confidence note when band is strong" do
      html =
        render_component(&ReaderComponents.coverage_note/1,
          caveat: "Caveat",
          confidence: %{band: "strong", note: "Strong match", top_similarity: 0.99}
        )

      refute html =~ "Strong match"
    end

    test "explains absence of semantic search when semantic is not in retrievers" do
      html =
        render_component(&ReaderComponents.coverage_note/1,
          retrievers: ["lexical"]
        )

      assert html =~ "Meaning-based matches were not considered"
    end

    test "renders nothing when all attributes are nil" do
      html = render_component(&ReaderComponents.coverage_note/1, [])
      assert String.trim(html) == ""
    end
  end

  describe "passage_line/1" do
    test "renders body text, locator, and focus styling" do
      span = %{
        content: "如是我聞一時佛住",
        urn: "pramana:cbeta.T:T0262_001@p0001c17",
        provenance: %{juan: 1, page: "0001", register: "c", line: 17},
        meta: %{}
      }

      html = render_component(&ReaderComponents.passage_line/1, span: span, focus: true)

      assert html =~ "如是我聞一時佛住"
      assert html =~ "j1 0001c17"
      assert html =~ ~s(data-focus="true")
    end

    test "renders locator without juan when juan is nil" do
      span = %{
        content: "Some line",
        urn: "pramana:cbeta.T:T0262_001@p0001c17",
        provenance: %{page: "0001", register: "c", line: 17},
        meta: %{}
      }

      html = render_component(&ReaderComponents.passage_line/1, span: span, focus: false)

      assert html =~ "0001c17"
      refute html =~ "j"
      assert html =~ ~s(data-focus="false")
    end

    test "falls back to URN locator when page is absent" do
      span_with_locator = %{
        content: "Text",
        urn: "pramana:suttacentral.pli:sn6.4@sn6.4:1.1",
        provenance: %{},
        meta: %{}
      }

      html1 = render_component(&ReaderComponents.passage_line/1, span: span_with_locator)
      assert html1 =~ "sn6.4:1.1"

      span_no_locator = %{
        content: "Text",
        urn: "pramana:cbeta.T:T0262",
        provenance: %{},
        meta: %{}
      }

      html2 = render_component(&ReaderComponents.passage_line/1, span: span_no_locator)
      assert html2 =~ "—"
    end

    test "renders reasons for empty lines based on metadata" do
      # Gaiji
      gaiji_span = %{
        content: "",
        urn: "pramana:cbeta.T:T0262_001@p0001c17",
        provenance: %{},
        meta: %{"gaiji" => [%{"ref" => "CB0001"}]}
      }

      html = render_component(&ReaderComponents.passage_line/1, span: gaiji_span)
      assert html =~ "a rare character, below"

      # Notes
      notes_span = %{
        content: "",
        urn: "pramana:cbeta.T:T0262_001@p0001c17",
        provenance: %{},
        meta: %{"notes" => ["interlinear note"]}
      }

      html = render_component(&ReaderComponents.passage_line/1, span: notes_span)
      assert html =~ "an interlinear note, below"

      # Apparatus
      app_span = %{
        content: "",
        urn: "pramana:cbeta.T:T0262_001@p0001c17",
        provenance: %{},
        meta: %{"apparatus" => [%{"lem" => "A"}]}
      }

      html = render_component(&ReaderComponents.passage_line/1, span: app_span)
      assert html =~ "a variant reading, below"

      # Default empty
      empty_span = %{
        content: "",
        urn: "pramana:cbeta.T:T0262_001@p0001c17",
        provenance: %{},
        meta: %{}
      }

      html = render_component(&ReaderComponents.passage_line/1, span: empty_span)
      assert html =~ "printed, but carrying no body text"

      # Nil meta
      nil_meta_span = %{
        content: "",
        urn: "pramana:cbeta.T:T0262_001@p0001c17",
        provenance: %{},
        meta: nil
      }

      html = render_component(&ReaderComponents.passage_line/1, span: nil_meta_span)
      assert html =~ "printed, but carrying no body text"

      # Span without provenance map, falling back to locator/1 -> urn_locator/1
      no_prov_span = %{
        content: "No prov",
        urn: "pramana:suttacentral.pli:sn6.4@sn6.4:1.1",
        meta: %{}
      }

      html_no_prov = render_component(&ReaderComponents.passage_line/1, span: no_prov_span)
      assert html_no_prov =~ "sn6.4:1.1"

      # Span without urn binary, falling back to urn_locator(_) -> "—"
      no_urn_span = %{
        content: "No URN",
        meta: %{}
      }

      html_no_urn = render_component(&ReaderComponents.passage_line/1, span: no_urn_span)
      assert html_no_urn =~ "—"

      # Page with nil line testing pad_line(nil)
      nil_line_span = %{
        content: "Nil line",
        urn: "pramana:cbeta.T:T0262_001@p0001c",
        provenance: %{page: "0001", register: "c", line: nil},
        meta: %{}
      }

      html_nil_line = render_component(&ReaderComponents.passage_line/1, span: nil_line_span)
      assert html_nil_line =~ "0001c"
    end

    test "renders line metadata for notes, gaiji variants, and apparatus readings" do
      meta = %{
        "notes" => ["註解一", "註解二"],
        "gaiji" => [
          %{"ref" => "CB00001", "mapping" => %{"unicode" => "䦚"}},
          %{"ref" => "CB00002", "mapping" => %{"composition" => "[門@口]"}},
          %{"ref" => "CB00003"}
        ],
        "apparatus" => [
          %{
            "lem" => "聞",
            "rdgs" => [
              %{"text" => "問"},
              %{"omitted" => true},
              %{"other" => "val"}
            ]
          }
        ]
      }

      span = %{
        content: "如是我聞",
        urn: "pramana:cbeta.T:T0262_001@p0001c17",
        provenance: %{},
        meta: meta
      }

      html = render_component(&ReaderComponents.passage_line/1, span: span)

      # Notes
      assert html =~ "註解一"
      assert html =~ "註解二"

      # Gaiji
      assert html =~ "䦚 (CB00001)"
      assert html =~ "[門@口] (CB00002) — no Unicode character exists for this glyph"
      assert html =~ "CB00003 — unmapped"

      # Apparatus
      assert html =~ "聞"
      assert html =~ "] 問"
      assert html =~ "] (omitted)"
    end
  end
end
