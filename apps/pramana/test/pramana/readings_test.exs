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

  describe "render" do
    setup do
      # A base dictionary: Unihan's commonest reading per character. 佛 is fú here
      # because that is genuinely what kMandarin says, and the whole layer exists to
      # override it.
      characters = [
        {"佛", "fú", ~w(fú fó)},
        {"般", "bān", ~w(bān bō pán)},
        {"若", "ruò", ~w(ruò rě rè)},
        {"波", "bō", ~w(bō)},
        {"羅", "luó", ~w(luó)},
        {"蜜", "mì", ~w(mì)},
        {"告", "gào", ~w(gào)},
        {"舍", "shě", ~w(shě shè)},
        {"利", "lì", ~w(lì)},
        {"弗", "fú", ~w(fú)}
      ]

      now = DateTime.utc_now()

      Repo.insert_all(
        Pramana.Corpus.CharacterReading,
        Enum.map(characters, fn {character, reading, attested} ->
          %{
            character: character,
            reading: reading,
            attested: attested,
            authority: "unihan",
            inserted_at: now,
            updated_at: now
          }
        end)
      )

      :ok
    end

    test "an exception overrides the ordinary reading" do
      {:ok, _} = Readings.store([exception("佛", "fó")])

      assert [%{form: "佛", reading: "fó", source: :exception}] = Readings.render("佛")
    end

    test "the ordinary reading applies where there is no exception" do
      assert [%{form: "告", reading: "gào", source: :base}] = Readings.render("告")
    end

    test "longest match wins, so a compound is not split" do
      {:ok, _} = Readings.store([exception("般若", "bō rě"), exception("般若波羅蜜", "bō rě bō luó mì")])

      # 般若波羅蜜 must come back as ONE token. Matching 般若 first would leave 波羅蜜
      # dangling and read a single term as two.
      assert [%{form: "般若波羅蜜", reading: "bō rě bō luó mì"}] = Readings.render("般若波羅蜜")
    end

    test "an exception is found mid-string, not only at the start" do
      {:ok, _} = Readings.store([exception("舍利弗", "shè lì fú"), exception("佛", "fó")])

      forms = Readings.render("佛告舍利弗") |> Enum.map(& &1.form)
      assert forms == ["佛", "告", "舍利弗"]
    end

    test "a character with no reading at all is marked unknown, never guessed" do
      assert [%{form: "龘", reading: nil, source: :unknown}] = Readings.render("龘")
    end

    test "a row that records wrongness without a reading does NOT fall back" do
      # The whole point of such a row is that the ordinary reading is wrong. Falling
      # through to the base would apply exactly the reading the row rejects, which is
      # worse than saying nothing.
      {:ok, _} = Readings.store([%{form: "佛", lang: "lzh", scheme: "pinyin", reading: nil}])

      assert [%{form: "佛", reading: "fú", source: :base}] = Readings.render("佛")
    end
  end

  describe "attestation" do
    setup do
      now = DateTime.utc_now()

      Repo.insert_all(Pramana.Corpus.CharacterReading, [
        %{
          character: "葉",
          reading: "yè",
          attested: ~w(yè shè),
          authority: "unihan",
          inserted_at: now,
          updated_at: now
        },
        %{
          character: "迦",
          reading: "jiā",
          attested: ~w(jiā),
          authority: "unihan",
          inserted_at: now,
          updated_at: now
        }
      ])

      :ok
    end

    test "accepts a reading assembled from readings somebody has recorded" do
      # 迦葉 is jiāshè and not jiāyè, and the evidence is that Unihan lists shè for 葉.
      # Selecting among attested readings is not the same act as inventing one.
      assert :ok = Readings.check("迦葉", "jiā shè")
    end

    test "rejects a syllable no source records for that character" do
      assert {:error, [{"葉", "zzz"}]} = Readings.check("迦葉", "jiā zzz")
    end

    test "rejects a reading with the wrong number of syllables" do
      assert {:error, _} = Readings.check("迦葉", "jiā")
    end

    test "attested/1 exposes what the character is ever read as" do
      assert Readings.attested("葉") == ~w(yè shè)
      assert Readings.attested("龘") == []
    end
  end

  defp exception(form, reading) do
    %{form: form, lang: "lzh", scheme: "pinyin", reading: reading, status: "verified"}
  end

  describe "import_dictionary" do
    setup do
      dir = Path.join(System.tmp_dir!(), "readings-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    defp write!(dir, name, lines),
      do: File.write!(Path.join(dir, name), Enum.join(lines, "\n") <> "\n")

    test "loads characters and exceptions from TSV", %{dir: dir} do
      write!(dir, "character_readings.tsv", ["# character\treading\tattested", "佛\tfú\tfú|fó"])

      write!(dir, "exceptions.tsv", [
        "# form\treading\tnaive\tauthority\tnote",
        "佛\tfó\tfú\tcurated\tBuddha"
      ])

      {:ok, result} = Readings.import_dictionary(dir: dir)

      assert result.characters == 1
      assert result.exceptions == 1
      assert Readings.attested("佛") == ~w(fú fó)
      assert [%{reading: "fó", source: :exception}] = Readings.render("佛")
    end

    test "a curated row beats a derived row for the same form", %{dir: dir} do
      write!(dir, "character_readings.tsv", ["佛\tfú\tfú|fó"])

      # Postgres refuses an ON CONFLICT statement proposing the same key twice, so
      # last-wins cannot be left to the database. Curated rows are written last.
      write!(dir, "exceptions.tsv", [
        "佛\twrong\tfú\tcc-cedict\tderived",
        "佛\tfó\t\tcurated\thand-checked"
      ])

      {:ok, _} = Readings.import_dictionary(dir: dir)

      assert Readings.exception("佛").reading == "fó"
      assert Readings.exception("佛").status == "verified"
    end

    test "derived rows are unverified, because nobody has read them", %{dir: dir} do
      write!(dir, "character_readings.tsv", ["般\tbān\tbān|bō"])
      write!(dir, "exceptions.tsv", ["般若\tbō rě\tbān ruò\tcc-cedict\twisdom"])

      {:ok, _} = Readings.import_dictionary(dir: dir)

      assert Readings.exception("般若").status == "unverified"
      assert Readings.exception("般若").authority == "cc-cedict"
    end

    test "re-importing replaces rather than skipping", %{dir: dir} do
      write!(dir, "character_readings.tsv", ["佛\tfú\tfú|fó"])
      write!(dir, "exceptions.tsv", ["佛\tfó\tfú\tcurated\tv1"])
      {:ok, _} = Readings.import_dictionary(dir: dir)

      # A rebuilt dictionary has to actually reach the database. `on_conflict: :nothing`
      # would make the import silently a no-op, which is how a licence correction once
      # failed to land.
      write!(dir, "exceptions.tsv", ["佛\tfó\tfú\tcurated\tv2"])
      {:ok, _} = Readings.import_dictionary(dir: dir)

      assert Readings.exception("佛").note == "v2"
    end
  end

  describe "score_test_set" do
    setup do
      dir = Path.join(System.tmp_dir!(), "score-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      now = DateTime.utc_now()

      Repo.insert_all(Pramana.Corpus.CharacterReading, [
        %{
          character: "般",
          reading: "bān",
          attested: ~w(bān bō),
          authority: "unihan",
          inserted_at: now,
          updated_at: now
        },
        %{
          character: "若",
          reading: "ruò",
          attested: ~w(ruò rě),
          authority: "unihan",
          inserted_at: now,
          updated_at: now
        },
        %{
          character: "菩",
          reading: "pú",
          attested: ~w(pú),
          authority: "unihan",
          inserted_at: now,
          updated_at: now
        },
        %{
          character: "薩",
          reading: "sà",
          attested: ~w(sà),
          authority: "unihan",
          inserted_at: now,
          updated_at: now
        }
      ])

      {:ok, _} = Readings.store([exception("般若", "bō rě")])
      {:ok, dir: dir}
    end

    test "scores both methods, so the comparison stays a measurement", %{dir: dir} do
      File.write!(
        Path.join(dir, "buddhist_test_set.tsv"),
        "# form\texpected\tnaive\tcorpus\n" <>
          "般若\tbō rě\tbān ruò\t100\n" <>
          "菩薩\tpú sà\tpú sà\t50\n"
      )

      result = Readings.score_test_set(dir: dir)

      assert result.correct == 2
      # The per-character method gets the control right and the exception wrong.
      assert result.naive_correct == 1
      assert result.fixed == 1
      assert result.broken == 0
      assert result.occurrences == 150
    end

    test "counts a control the dictionary damages as broken", %{dir: dir} do
      # The regression that matters most: a dictionary that fixes hard cases by
      # breaking easy ones is not an improvement, and the score has to say so.
      {:ok, _} = Readings.store([exception("菩薩", "wrong wrong")])

      File.write!(
        Path.join(dir, "buddhist_test_set.tsv"),
        "菩薩\tpú sà\tpú sà\t50\n"
      )

      result = Readings.score_test_set(dir: dir)

      assert result.broken == 1
      assert result.correct == 0
    end
  end
end
