defmodule Pramana.ReadingsTest do
  @moduledoc """
  The reading-exception layer.

  The property under test is refusal: a general pinyin library will confidently mis-read
  Buddhist vocabulary, and the fix is not a better guess but a table of the cases where
  the ordinary answer is known to be wrong — including rows that say *wrong* without
  saying *right*.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.GlossaryTerm
  alias Pramana.Corpus.Source
  alias Pramana.Readings
  alias Pramana.Repo

  setup do
    Repo.insert!(%Source{
      id: "local-huang-nianzu-jie",
      name: "Huang Nianzu",
      license_spdx: "LicenseRef-Local-Restricted",
      license_class: "restricted",
      commercial_use: false,
      redistributable: false
    })

    :ok
  end

  defp term(attrs) do
    Repo.insert!(
      struct(
        %GlossaryTerm{
          source_id: "local-huang-nianzu-jie",
          canonical_english: "x",
          reading_status: "not_applicable",
          rejected_forms: []
        },
        attrs
      )
    )
  end

  describe "seeding from the glossary" do
    test "reads a Korean name as Korean, not as pinyin" do
      # The case the glossary was written to prevent: 元曉 is Wŏnhyo. Recording the
      # Mandarin reading here under a Korean scheme would be the original error, laundered
      # into structured data.
      term(%{
        term: "元曉",
        pinyin: nil,
        canonical_english: "Master Wŏnhyo (元曉)",
        language_origin: "korean"
      })

      {:ok, _} = Readings.seed_from_glossary()

      exception = Readings.exception("元曉", lang: "ko", scheme: "mccune-reischauer")
      assert exception.reading == "Wŏnhyo"
      assert exception.status == "verified"
    end

    test "reads a Japanese name as Japanese" do
      term(%{
        term: "道隱",
        pinyin: nil,
        canonical_english: "Master Dōin (道隱)",
        language_origin: "japanese"
      })

      {:ok, _} = Readings.seed_from_glossary()

      assert Readings.exception("道隱", lang: "ja", scheme: "on-yomi").reading == "Dōin"
    end

    # The glossary's convention inverted: a PRESENT pinyin means the real reading could
    # not be established and pinyin was retained as a placeholder.
    test "a retained pinyin is recorded as unverified, never as the reading" do
      term(%{
        term: "日溪",
        pinyin: "Rìxī",
        canonical_english: "Master Rixi (日溪)",
        language_origin: "japanese",
        reading_status: "unverified",
        notes: "Japanese, but reading unverified."
      })

      {:ok, _} = Readings.seed_from_glossary()

      exception = Readings.exception("日溪", lang: "ja", scheme: "on-yomi")

      assert exception.reading == nil
      assert exception.status == "unverified"
      # The pinyin is not thrown away — it is labelled.
      assert exception.note =~ "Rìxī"
      assert exception.note =~ "NOT the reading in this scheme"
    end

    test "an ambiguous English gloss is left unverified rather than parsed" do
      # Two names and two forms. Guessing which belongs to which is guessing.
      term(%{
        term: "望西 / 望西樓了惠",
        pinyin: nil,
        canonical_english: "Master Bōsai (望西) / Ryōe of Bōsai-rō (望西樓了惠)",
        language_origin: "japanese"
      })

      {:ok, _} = Readings.seed_from_glossary()

      assert Readings.exception("望西 / 望西樓了惠", lang: "ja", scheme: "on-yomi").status ==
               "unverified"
    end

    test "skips Chinese-origin terms, whose pinyin is simply the ordinary reading" do
      term(%{term: "念佛", pinyin: "niànfó", language_origin: "chinese"})

      {:ok, result} = Readings.seed_from_glossary()

      assert result.seeded == 0
    end

    test "is idempotent — reseeding replaces rather than duplicates" do
      term(%{
        term: "澄憲",
        pinyin: nil,
        canonical_english: "Master Chōken (澄憲)",
        language_origin: "japanese"
      })

      {:ok, _} = Readings.seed_from_glossary()
      {:ok, _} = Readings.seed_from_glossary()

      assert Readings.stats().exceptions == 1
    end
  end

  describe "lookup" do
    test "returns nil for a form with no exception, which is the usual answer" do
      assert Readings.exception("無", lang: "lzh", scheme: "pinyin") == nil
    end

    test "finds every exception in a string, longest form first" do
      {:ok, _} =
        Readings.store([
          %{form: "般若", lang: "lzh", scheme: "pinyin", reading: "bōrě", status: "verified"},
          %{
            form: "般若波羅蜜",
            lang: "lzh",
            scheme: "pinyin",
            reading: "bōrě bōluómì",
            status: "verified"
          }
        ])

      forms =
        Readings.exceptions_in("行深般若波羅蜜多時", lang: "lzh", scheme: "pinyin")
        |> Enum.map(& &1.form)

      # The compound must win, or applying the short form first splits a unit that has
      # its own conventional reading.
      assert forms == ["般若波羅蜜", "般若"]
    end
  end

  describe "the database refuses an incoherent row" do
    test "a verified exception must actually state a reading" do
      # Postgrex.Error rather than Ecto.ConstraintError because this writes through
      # `insert_all`, which has no changeset to attach a constraint to. The database is
      # the last line either way, which is exactly where this check belongs.
      assert_raise Postgrex.Error, ~r/verified_reading_has_a_reading/, fn ->
        Readings.store([
          %{form: "南無", lang: "lzh", scheme: "pinyin", reading: nil, status: "verified"}
        ])
      end
    end

    test "but an unverified one need not — that is the point" do
      {:ok, 1} =
        Readings.store([
          %{form: "南無", lang: "lzh", scheme: "pinyin", reading: nil, status: "unverified"}
        ])

      assert Readings.stats().without_reading == 1
    end
  end
end
