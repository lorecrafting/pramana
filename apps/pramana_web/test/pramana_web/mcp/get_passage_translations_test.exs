defmodule PramanaWeb.MCP.GetPassageTranslationsTest do
  @moduledoc """
  How a translation reaches a model, and how it must not.

  The failure this guards against is at the presentation layer, where the citation guard
  cannot see it: if Sujato's English arrives in the field where the Pāli belongs, a model
  will quote it as the Pāli, correctly attributed to a URN that addresses the Pāli. The
  guard would then verify a quotation of the source against the source — and the English
  sentence would be presented as scripture with a clean bill of health.

  So `text` is always the source, and translations arrive under their own key.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Translations
  alias PramanaWeb.MCP.Tools.GetPassage

  @anchor "pramana:sc.ms:mn1@1.1"
  @pali "Evaṁ me sutaṁ—"

  setup do
    Repo.insert!(%Source{
      id: "sc",
      name: "SuttaCentral",
      license_spdx: "CC-PDM-1.0",
      license_class: "public-domain",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Witness{id: "ms", name: "Mahāsaṅgīti"})
    Repo.insert!(%Work{id: "mn1", title: "Mūlapariyāya"})

    text =
      Repo.insert!(%Text{
        work_id: "mn1",
        source_id: "sc",
        witness_id: "ms",
        urn_prefix: "pramana:sc.ms:mn1",
        body: @pali,
        body_sha256: "x",
        meta: %{}
      })

    Repo.insert!(%Segment{
      text_id: text.id,
      urn: @anchor,
      ordinal: 0,
      content: @pali,
      content_sha256: :crypto.hash(:sha256, @pali) |> Base.encode16(case: :lower),
      char_start: 0,
      char_end: String.length(@pali),
      byte_start: 0,
      byte_end: byte_size(@pali),
      meta: %{}
    })

    {:ok, _} =
      Translations.store([
        %{
          anchor_urn: @anchor,
          work_id: "mn1",
          lang: "en",
          translator_id: "sujato",
          tier: "t0",
          method: "human",
          text: "So I have heard.",
          redistributable: true,
          license_class: "cc0"
        },
        %{
          anchor_urn: @anchor,
          work_id: "mn1",
          lang: "en",
          translator_id: "model:claude-opus-5",
          tier: "t1",
          method: "llm",
          model_id: "claude-opus-5",
          text: "Thus have I heard.",
          redistributable: false,
          license_class: "unknown"
        }
      ])

    :ok
  end

  defp call!(params),
    do:
      GetPassage.execute(params, %{})
      |> elem(1)
      |> Map.fetch!(:content)
      |> hd()
      |> Map.fetch!("text")
      |> Jason.decode!()

  describe "a rendering URN reaches this tool, and is not a passage" do
    @generated "#{@anchor}#tr:en/model:claude-opus-5"

    # `Corpus.resolve/1` routes a URN carrying `#tr:` to the translation layer, so this
    # tool really can be handed one. It crashed on every rendering URN with
    # `KeyError: key :sha256` until 2026-09-03 — a rendering span has no offsets into a
    # witness and named its hash `content_sha256` where the corpus names it `sha256`.
    # Found by performing `docs/CHECKS.md` §2's invariant #8 audit by hand.
    test "answers rather than raising, and leads with what it is" do
      payload = call!(%{urn: @generated})

      assert payload["layer"] == "translation"
      assert payload["citable_as_source"] == false
      assert payload["anchor_urn"] == @anchor
      assert payload["text"] == "Thus have I heard."
      assert payload["provenance"]["method"] == "llm"
    end

    # No offsets rather than fabricated ones: a rendering indexes no edition, and a
    # made-up range is exactly the false precision the citation guard exists to prevent.
    test "carries a sha256 and invents no offsets" do
      payload = call!(%{urn: @generated})

      assert is_binary(payload["sha256"])
      refute Map.has_key?(payload, "offsets")
      assert payload["note"] =~ "never citable as source"
    end
  end

  test "no translation is attached unless one was asked for" do
    data = call!(%{urn: @anchor})

    assert data["text"] == @pali
    assert data["translations"] == nil
  end

  test "text remains the source even when a translation is attached" do
    data = call!(%{urn: @anchor, translation: "en"})

    assert data["text"] == @pali
    assert data["translations"]["rendering"]["text"] == "So I have heard."
  end

  test "prefers the human rendering and says how many were withheld" do
    data = call!(%{urn: @anchor, translation: "en"})["translations"]

    assert data["rendering"]["translator_id"] == "sujato"
    assert data["alternatives"] == 1
  end

  test "compare returns every rendering, which is the honest view of a contested passage" do
    data = call!(%{urn: @anchor, translation: "en", compare_translations: true})["translations"]

    assert length(data["pool"]) == 2
  end

  test "pinning a translator returns that one" do
    data =
      call!(%{urn: @anchor, translation: "en", translator: "model:claude-opus-5"})["translations"]

    assert data["rendering"]["translator_id"] == "model:claude-opus-5"
    assert data["rendering"]["provenance"]["method"] == "llm"
  end

  test "every attached translation says it is not citable as source" do
    data = call!(%{urn: @anchor, translation: "en"})["translations"]

    assert data["citable_as_source"] == false
    assert data["rendering"]["provenance"]["citable_as_source"] == false
  end

  test "a language with no renderings yields nothing rather than a fallback" do
    data = call!(%{urn: @anchor, translation: "de"})["translations"]

    assert data["rendering"] == nil
    assert data["alternatives"] == 0
  end

  test "context windows carry translations on every span, not just the focus" do
    data = call!(%{urn: @anchor, translation: "en", context_after: 1})

    assert data["focus"]["translations"]["rendering"]["text"] == "So I have heard."
    assert data["focus"]["text"] == @pali
  end
end
