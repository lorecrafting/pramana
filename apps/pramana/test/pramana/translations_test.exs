defmodule Pramana.TranslationsTest do
  @moduledoc """
  The translation pool and its selection policy.

  Two things are load-bearing here. **Multiplicity is never collapsed** — a caller that
  is shown one of four renderings must be told there were four (`docs/TRANSLATION.md`).
  And **a rendering is never a source**: invariant #7 in `CLAUDE.md` says a machine
  translation cannot be cited as scripture, and the tests below exercise that through the
  ordinary resolve path rather than a special one, because a rule enforced only on a
  path someone has to remember to take is not enforced.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Guard
  alias Pramana.Repo
  alias Pramana.Translations
  alias Pramana.URN

  @anchor "pramana:sc.ms:mn1@1.1"

  setup do
    Repo.insert!(%Pramana.Corpus.Source{
      id: "sc",
      name: "SuttaCentral",
      license_spdx: "CC-PDM-1.0",
      license_class: "public-domain",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Pramana.Corpus.Witness{id: "ms", name: "Mahāsaṅgīti"})
    work = Repo.insert!(%Work{id: "mn1", title: "Mūlapariyāya"})

    text =
      Repo.insert!(%Text{
        work_id: work.id,
        source_id: "sc",
        witness_id: "ms",
        urn_prefix: "pramana:sc.ms:mn1",
        body: "Evaṁ me sutaṁ—",
        body_sha256: "x",
        meta: %{}
      })

    Repo.insert!(%Segment{
      text_id: text.id,
      urn: @anchor,
      ordinal: 0,
      content: "Evaṁ me sutaṁ—",
      content_sha256: :crypto.hash(:sha256, "Evaṁ me sutaṁ—") |> Base.encode16(case: :lower),
      char_start: 0,
      char_end: 14,
      byte_start: 0,
      byte_end: 16,
      meta: %{}
    })

    :ok
  end

  defp put(attrs) do
    {:ok, _} =
      Translations.store([
        Map.merge(
          %{
            anchor_urn: @anchor,
            work_id: "mn1",
            lang: "en",
            tier: "t0",
            method: "human",
            text: "So I have heard.",
            redistributable: true,
            license_class: "cc0"
          },
          attrs
        )
      ])
  end

  describe "the pool" do
    test "holds several renderings of one anchor without picking a winner" do
      put(%{translator_id: "sujato", text: "So I have heard."})
      put(%{translator_id: "bodhi", text: "Thus have I heard."})

      assert Translations.pool(@anchor) |> Enum.map(& &1.translator_id) == ["bodhi", "sujato"]
    end

    test "a second run by the same translator replaces rather than duplicates" do
      put(%{translator_id: "sujato", text: "So I have heard."})
      put(%{translator_id: "sujato", text: "This is how I heard it."})

      assert [%{text: "This is how I heard it."}] = Translations.pool(@anchor)
    end

    test "keeps languages apart" do
      put(%{translator_id: "sujato", lang: "en"})
      put(%{translator_id: "sabbamitta", lang: "de", text: "So habe ich es gehört."})

      assert Translations.pool(@anchor, lang: "de") |> Enum.map(& &1.translator_id) ==
               ["sabbamitta"]
    end

    test "a pooled rendering carries the same hash as one resolved by URN" do
      put(%{translator_id: "sujato", text: "So I have heard."})

      [pooled] = Translations.pool(@anchor)
      {:ok, resolved} = Pramana.Corpus.resolve("#{@anchor}#tr:en/sujato")

      # Verifiability must not depend on which call the caller happened to make — and
      # until 2026-09-03 it depended on which NAME the caller reached for: this line read
      # `pooled.sha256 == resolved.content_sha256`, comparing across an inconsistency
      # rather than reporting it. `get_passage` reaches for `span.sha256` and crashed on
      # every rendering URN because of it.
      assert pooled.sha256 == resolved.sha256

      assert pooled.sha256 ==
               :crypto.hash(:sha256, "So I have heard.") |> Base.encode16(case: :lower)
    end

    test "computes the sha256 itself, so a stored hash always covers its text" do
      put(%{translator_id: "sujato", text: "So I have heard."})

      [rendering] = Repo.all(Pramana.Corpus.Translation)

      assert rendering.text_sha256 ==
               :crypto.hash(:sha256, "So I have heard.") |> Base.encode16(case: :lower)
    end
  end

  describe "a rendering anchored to a range that contains the span" do
    setup do
      # A second and third line of the same text, so there is something for a folio-wide
      # rendering to span. This is the Derge shape: the source is addressed by line and
      # the translation by folio.
      text = Repo.one!(Text)

      for {ordinal, locator, content} <- [{1, "1.2", "dutiyaṁ"}, {2, "1.3", "tatiyaṁ"}] do
        Repo.insert!(%Segment{
          text_id: text.id,
          urn: "pramana:sc.ms:mn1@#{locator}",
          ordinal: ordinal,
          content: content,
          content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
          char_start: 0,
          char_end: String.length(content),
          byte_start: 0,
          byte_end: byte_size(content),
          meta: %{}
        })
      end

      put(%{
        anchor_urn: "pramana:sc.ms:mn1@1.1-1.3",
        translator_id: "84000",
        text: "All three lines, rendered together.",
        meta: %{"ordinal_start" => 0, "ordinal_end" => 2}
      })

      :ok
    end

    test "is not returned by an exact lookup, which is what makes the fallback necessary" do
      assert Translations.pool("pramana:sc.ms:mn1@1.2") == []
    end

    test "is found by asking for a line inside it" do
      [rendering] = Translations.covering("pramana:sc.ms:mn1@1.2")

      assert rendering.translator_id == "84000"
      assert rendering.text == "All three lines, rendered together."
    end

    # THE SECOND PLACE THE SAME ASSUMPTION LIVED. `covering/2` matched
    # `translations.work_id` against `urn.work`, the work component of the ADDRESS — and
    # for CBETA that is the juan, `T0099_015`, where the work is `T0099`. Every
    # range-anchored English rendering of the Chinese canon was therefore unreachable from
    # the line it renders: 2,089 of the first 3,354, correctly stored and invisible.
    # Rules 41 and 68. Found by checking whether a model could reach what had just
    # shipped, which is rule 60's question asked of a thing that was already green.
    test "is found through a CBETA address, where the juan sits between work and locator" do
      Repo.insert!(%Pramana.Corpus.Source{
        id: "cbeta",
        name: "CBETA",
        license_spdx: "LicenseRef-CBETA-NC",
        license_class: "nc",
        commercial_use: false,
        redistributable: false
      })

      Repo.insert!(%Pramana.Corpus.Witness{id: "T", name: "Taishō"})
      Repo.insert!(%Work{id: "T0099", title: "雜阿含經"})

      chinese =
        Repo.insert!(%Text{
          work_id: "T0099",
          source_id: "cbeta",
          witness_id: "T",
          urn_prefix: "pramana:cbeta.T:T0099",
          body: "如是我聞一時佛住舍衛國",
          body_sha256: "x",
          meta: %{}
        })

      for {ordinal, locator, content} <- [{0, "p0001a01", "如是我聞一時"}, {1, "p0001a02", "佛住舍衛國"}] do
        Repo.insert!(%Segment{
          text_id: chinese.id,
          urn: "pramana:cbeta.T:T0099_001@#{locator}",
          ordinal: ordinal,
          content: content,
          content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
          char_start: 0,
          char_end: String.length(content),
          byte_start: 0,
          byte_end: byte_size(content),
          meta: %{}
        })
      end

      put(%{
        anchor_urn: "pramana:cbeta.T:T0099_001@p0001a01-p0001a02",
        work_id: "T0099",
        translator_id: "patton",
        text: "Thus I have heard. At one time the Buddha was staying in Sāvatthī.",
        meta: %{"ordinal_start" => 0, "ordinal_end" => 1}
      })

      [rendering] = Translations.covering("pramana:cbeta.T:T0099_001@p0001a02")

      assert rendering.translator_id == "patton"
      assert rendering.covers == :containing_range
    end

    test "says that it covers the span rather than matching it" do
      # A caller has to be able to tell a translation OF this line from one that includes
      # it, and the rendering's own anchor says how much wider it is.
      [rendering] = Translations.covering("pramana:sc.ms:mn1@1.2")

      assert rendering.covers == :containing_range
      assert rendering.anchor_urn == "pramana:sc.ms:mn1@1.1-1.3"
    end

    test "select/2 falls back to it only when nothing matches exactly" do
      put(%{translator_id: "sujato", text: "So I have heard."})

      exact = Translations.select(@anchor)
      inside = Translations.select("pramana:sc.ms:mn1@1.2")

      assert exact.rendering.translator_id == "sujato"
      refute Map.has_key?(exact.rendering, :covers)
      assert inside.rendering.covers == :containing_range
    end

    test "a line outside the range finds nothing" do
      Repo.insert!(%Segment{
        text_id: Repo.one!(Text).id,
        urn: "pramana:sc.ms:mn1@1.4",
        ordinal: 3,
        content: "catutthaṁ",
        content_sha256: "x",
        char_start: 0,
        char_end: 9,
        byte_start: 0,
        byte_end: 9,
        meta: %{}
      })

      assert Translations.covering("pramana:sc.ms:mn1@1.4") == []
    end

    test "a span the corpus does not contain finds nothing rather than raising" do
      assert Translations.covering("pramana:sc.ms:mn1@99.99") == []
    end

    test "the policy still applies to a covering rendering" do
      assert Translations.covering("pramana:sc.ms:mn1@1.2", translator: "someone-else") == []
    end
  end

  describe "selection policy" do
    test "prefers a human rendering over a generated one" do
      put(%{translator_id: "sujato", tier: "t0", method: "human"})

      put(%{
        translator_id: "model:claude-opus-5",
        tier: "t1",
        method: "llm",
        model_id: "claude-opus-5",
        text: "Thus I heard."
      })

      selection = Translations.select(@anchor)

      assert selection.rendering.translator_id == "sujato"
      # The caller is TOLD one was withheld. A selection that silently hides the pool is
      # how a reader concludes there is only one translation.
      assert selection.alternatives == 1
    end

    test "an explicit prefer order overrides the default" do
      put(%{translator_id: "sujato", tier: "t0"})

      put(%{
        translator_id: "model:claude-opus-5",
        tier: "t1",
        method: "llm",
        model_id: "claude-opus-5"
      })

      selection = Translations.select(@anchor, prefer: ["t1", "t0"])
      assert selection.rendering.translator_id == "model:claude-opus-5"
    end

    test "pinning a translator returns that translator or nothing, never a substitute" do
      put(%{translator_id: "sujato"})

      assert Translations.select(@anchor, translator: "sujato").rendering.translator_id ==
               "sujato"

      # The dangerous behaviour would be falling back to whoever is available under the
      # name the caller asked for.
      assert Translations.select(@anchor, translator: "bodhi").rendering == nil
    end

    test "compare mode returns the whole pool" do
      put(%{translator_id: "sujato"})
      put(%{translator_id: "bodhi", text: "Thus have I heard."})

      assert Translations.select(@anchor, mode: :compare).pool |> length() == 2
      assert Translations.select(@anchor).pool == []
    end

    test "min_review_state is a floor, so a stronger state still qualifies" do
      put(%{translator_id: "sujato", review_state: "approved"})
      put(%{translator_id: "draft", review_state: "raw", text: "rough"})

      ids =
        Translations.pool(@anchor, min_review_state: "human_reviewed")
        |> Enum.map(& &1.translator_id)

      assert ids == ["sujato"]
    end

    test "redistributable_only excludes a rendering we may hold but not republish" do
      put(%{translator_id: "sujato", redistributable: true})
      put(%{translator_id: "restricted", redistributable: false, text: "in copyright"})

      ids =
        Translations.pool(@anchor, redistributable_only: true) |> Enum.map(& &1.translator_id)

      assert ids == ["sujato"]
    end

    test "an unknown policy option raises rather than being ignored" do
      assert_raise ArgumentError, ~r/unknown translation policy option/, fn ->
        Translations.select(@anchor, translater: "sujato")
      end
    end

    test "an unknown tier raises" do
      assert_raise ArgumentError, ~r/unknown tier/, fn ->
        Translations.select(@anchor, tier: "t9")
      end
    end
  end

  describe "rendering URNs" do
    test "resolve through Corpus.resolve/1, like any other citation" do
      put(%{translator_id: "sujato", text: "So I have heard."})

      assert {:ok, span} = Pramana.Corpus.resolve("#{@anchor}#tr:en/sujato")
      assert span.content == "So I have heard."
      # The source anchor travels with the rendering, always.
      assert span.anchor_urn == @anchor
    end

    test "strip to the source anchor, which is the whole point of a fragment" do
      urn = URN.parse!("#{@anchor}#tr:en/sujato")

      assert URN.rendering?(urn)
      assert URN.to_string(URN.anchor(urn)) == @anchor
    end

    test "round-trip through to_string/1" do
      urn = "#{@anchor}#tr:en/model:claude-opus-5@prompt-v3"
      assert urn |> URN.parse!() |> URN.to_string() == urn
    end

    test "a rendering that does not exist is not found, not invented" do
      assert {:error, :not_found} = Pramana.Corpus.resolve("#{@anchor}#tr:en/nobody")
    end

    test "an unrecognised fragment is rejected rather than ignored" do
      assert {:error, :unknown_fragment} = URN.parse("#{@anchor}#notes:1")
    end
  end

  describe "invariant #7 — a machine translation is never citable as source" do
    test "the guard rejects a quote of a generated rendering" do
      put(%{
        translator_id: "model:claude-opus-5",
        tier: "t1",
        method: "llm",
        model_id: "claude-opus-5",
        text: "Thus I heard."
      })

      finding = Guard.check("#{@anchor}#tr:en/model:claude-opus-5", "Thus I heard.")

      # The words really are there — and it is still not citable.
      assert finding.verdict == :not_citable_as_source
      refute Guard.verify("#{@anchor}#tr:en/model:claude-opus-5", "Thus I heard.")
    end

    test "a human rendering verifies, and is still labelled a translation" do
      put(%{translator_id: "sujato", text: "So I have heard."})

      finding = Guard.check("#{@anchor}#tr:en/sujato", "So I have heard.")

      assert finding.verdict == :ok
      assert finding.layer == "translation"
      refute finding.provenance.citable_as_source
    end

    test "the source anchor itself is unaffected and remains citable" do
      put(%{translator_id: "sujato", text: "So I have heard."})

      finding = Guard.check(@anchor, "Evaṁ me sutaṁ—")

      assert finding.verdict == :ok
      assert finding.layer == "source"
    end

    test "check_output counts verified translation quotes separately from source ones" do
      put(%{translator_id: "sujato", text: "So I have heard."})

      report =
        Guard.check_output("""
        The sutta opens “Evaṁ me sutaṁ—” [#{@anchor}], rendered
        “So I have heard.” [#{@anchor}#tr:en/sujato].
        """)

      assert report.ok?
      assert report.verified_quotes == 2
      # Two verified quotes, but only one of them is of the text.
      assert report.translations == 1
    end
  end

  # 210,756 renderings were reachable only through an anchor a caller already had. Ask an
  # English question and the lexical retriever — which reads `segments` — answered with
  # Pāli passages that happened to share character n-grams: three confident results with
  # nothing to do with the question. On the public artefact, where the renderings are most
  # of what a reader can use, that was the whole surface.
  describe "searching the renderings" do
    setup do
      put(%{translator_id: "sujato", text: "Mendicants, the eye really is impermanent."})

      put(%{
        anchor_urn: "pramana:sc.ms:mn1@1.2",
        translator_id: "sujato",
        text: "Baka the Divinity is lost in ignorance."
      })

      :ok
    end

    test "finds a rendering by its own words" do
      assert {:ok, %{results: [hit], match: :all_terms}} =
               Translations.search("eye impermanent")

      assert hit.text =~ "eye really is impermanent"
      assert hit.anchor_urn == @anchor
    end

    # THE SHAPE IS THE INVARIANT. A fluent English sentence reads like an answer, so the
    # result leads with the line it renders and states outright that it is not citable.
    test "every hit is a rendering OF something, and says it is not the source" do
      {:ok, %{results: [hit]}} = Translations.search("eye impermanent")

      assert hit.anchor_urn == @anchor
      assert hit.rendering_urn == "#{@anchor}#tr:en/sujato"
      assert hit.provenance.citable_as_source == false
      assert hit.provenance.layer == "translation"
    end

    # The unit is one rendered LINE, so requiring every term in one row is far stricter
    # than it looks — these two words are in the corpus and never in the same sentence.
    # The fallback finds them and the mode says the terms were not found together.
    test "falls back to any term, and reports that it did" do
      assert {:ok, %{results: results, match: :any_term}} =
               Translations.search("impermanent Baka")

      assert length(results) == 2
    end

    test "says nothing rather than something for a word the corpus does not hold" do
      assert {:ok, %{results: [], match: :any_term}} = Translations.search("zzzznotaword")
    end

    test "punctuation is stripped, never passed to the parser as an operator" do
      # `&`, `|` and `!` are tsquery operators. Arriving from a caller they are a syntax
      # error at best, and someone else's query at worst.
      assert {:ok, %{results: [_ | _]}} = Translations.search("impermanent & eye | !x")
    end

    test "honours the licence filter, because this is what a public surface serves" do
      put(%{
        translator_id: "withheld",
        text: "Mendicants, the eye is unreliable.",
        redistributable: false
      })

      {:ok, %{results: all}} = Translations.search("eye", limit: 10)

      {:ok, %{results: public}} =
        Translations.search("eye", limit: 10, redistributable_only: true)

      assert length(all) > length(public)
      assert Enum.all?(public, & &1.provenance.redistributable)
    end

    test "raises on an unknown option rather than ignoring a filter" do
      assert_raise ArgumentError, ~r/unknown option/, fn ->
        Translations.search("eye", licence_only: true)
      end
    end
  end

  describe "coverage" do
    test "reports what fraction of a work each translator rendered" do
      put(%{translator_id: "sujato"})

      [entry] = Translations.coverage("mn1").translators
      assert entry.rendered == 1
      assert entry.coverage == 1.0
    end
  end

  describe "licence" do
    test "is carried per rendering, not inherited from the source" do
      # The real case this defends: bilara-data is CC0 throughout except Anandajoti's
      # Patna Dhammapada, which is CC BY-SA 3.0 and carries obligations CC0 does not.
      # Its root text is Prakrit and not in this corpus, so no ingested row exercises
      # the path — hence a test that does.
      put(%{
        translator_id: "anandajoti",
        license_class: "cc-by-sa",
        license_spdx: "CC-BY-SA-3.0",
        redistributable: true,
        attribution: "Patna Dhammapada, translated by anandajoti. CC BY-SA 3.0"
      })

      [rendering] = Translations.pool(@anchor)

      assert rendering.license_class == "cc-by-sa"
      assert rendering.provenance.license_spdx == "CC-BY-SA-3.0"
      assert rendering.attribution =~ "CC BY-SA 3.0"
    end

    test "unlicensed/0 surfaces anything we may not republish" do
      put(%{translator_id: "unknown-hand", license_class: "unknown", redistributable: false})

      assert [%{translator_id: "unknown-hand", renderings: 1}] = Translations.unlicensed()
    end
  end

  describe "stats" do
    test "count anchors carrying more than one rendering" do
      put(%{translator_id: "sujato"})
      put(%{translator_id: "bodhi", text: "Thus have I heard."})

      stats = Translations.stats()
      assert stats.renderings == 2
      assert stats.anchors_with_multiple == 1
    end
  end
end
