defmodule Mix.Tasks.Pramana.Sc.TranslationsTest do
  @moduledoc """
  Which publication governs a file is a **licensing** decision, so it is tested like one.

  Getting it wrong is not a crash. It stores `redistributable: false` on text that is
  public domain, which reads as caution and is indistinguishable from a correct answer
  until someone counts — and it cost 66,199 rows of Bhikkhu Brahmāli's CC0 Vinaya
  translation exactly that.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Pramana.Sc.Translations

  defp pub(number, text_uid, dir, licence \\ "CC0") do
    %{
      "publication_number" => number,
      "text_uid" => text_uid,
      "author_uid" => "brahmali",
      "source_url" => dir && "https://github.com/suttacentral/bilara-data/tree/published/#{dir}",
      "license" => %{"license_abbreviation" => licence}
    }
  end

  defp vinaya, do: pub("scpub8", "pli-tv-vi", "translation/en/brahmali/vinaya")
  defp monks, do: pub("scpub78", "pli-tv-bu-pm", "translation/en/brahmali/vinaya/pli-tv-bu-pm")

  describe "publication_for/3" do
    # THE BUG. `pli-tv-vi` is the whole Vinaya Piṭaka; its works are `pli-tv-bu-vb-pj1`
    # and friends, which do not start with it. Matching on the uid found nothing, so the
    # licence was inferred and the text was withheld — while the publication's own
    # `source_url` said, exactly, which directory it publishes.
    test "matches a collection whose uid is not a prefix of its works" do
      assert {%{"publication_number" => "scpub8"}, :matched} =
               Translations.publication_for(
                 [vinaya()],
                 "pli-tv-bu-vb-pj1",
                 "translation/en/brahmali/vinaya/pli-tv-bu-vb/pli-tv-bu-vb-pj1_translation-en-brahmali.json"
               )
    end

    test "the innermost publication wins where publications nest" do
      assert {%{"publication_number" => "scpub78"}, :matched} =
               Translations.publication_for(
                 [vinaya(), monks()],
                 "pli-tv-bu-pm",
                 "translation/en/brahmali/vinaya/pli-tv-bu-pm/x_translation-en-brahmali.json"
               )
    end

    test "a sibling directory is not a match" do
      # `.../vinaya` must not swallow `.../vinaya-notes`, which comparing the bare string
      # as a prefix would.
      assert {_, :inferred} =
               Translations.publication_for(
                 [vinaya()],
                 "other",
                 "translation/en/brahmali/vinaya-notes/x_translation-en-brahmali.json"
               )
    end

    test "falls back to the uid when a publication states no directory" do
      assert {_, :matched} =
               Translations.publication_for(
                 [pub("scpub3", "mn", nil)],
                 "mn1",
                 "translation/en/sujato/sutta/mn/mn1_translation-en-sujato.json"
               )
    end

    # Sujato's Jātaka is in the repository and absent from `_publication.json`. An
    # agreeing licence across his other publications is good enough to hold and search
    # under, and not good enough to republish on.
    test "infers only when every candidate agrees" do
      agreeing = [
        pub("a", "mn", "translation/en/sujato/sutta/mn"),
        pub("b", "sn", "translation/en/sujato/sutta/sn")
      ]

      assert {_, :inferred} =
               Translations.publication_for(agreeing, "ja1", "translation/en/sujato/kn/ja1.json")

      disagreeing = [
        pub("a", "mn", "translation/en/sujato/sutta/mn", "CC0"),
        pub("b", "sn", "translation/en/sujato/sutta/sn", "CC BY-SA 3.0")
      ]

      assert {nil, :none} =
               Translations.publication_for(
                 disagreeing,
                 "ja1",
                 "translation/en/sujato/kn/ja1.json"
               )
    end

    test "is none when the translator has no publications at all" do
      assert {nil, :none} = Translations.publication_for([], "mn1", "translation/en/x/mn1.json")
    end
  end
end
