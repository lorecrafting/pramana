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

      # Verifiability must not depend on which call the caller happened to make.
      assert pooled.sha256 == resolved.content_sha256

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
