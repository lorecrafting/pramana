defmodule Pramana.CoherenceTest do
  @moduledoc """
  The third data check: do independently derived facts about one work agree?

  What is tested here is mostly the **judgement policy**, not the SQL. A coherence check that
  fires on noise gets ignored, and a check that passes for want of data reports success it
  never earned — both failure modes have precedent in this project, so `:undecided` is
  asserted as carefully as `:failed`.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Coherence
  alias Pramana.Corpus.AuthorityPerson
  alias Pramana.Corpus.AuthorityPlace
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Work
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo

  defp person!(attrs) do
    %AuthorityPerson{}
    |> Ecto.Changeset.change(Map.put_new(attrs, :source, "dila-authority"))
    |> Repo.insert!()
  end

  defp place!(attrs) do
    %AuthorityPlace{}
    |> Ecto.Changeset.change(Map.put_new(attrs, :source, "dila-authority"))
    |> Repo.insert!()
  end

  defp work!(id, number, provenance) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title>
    <author>#{provenance[:attributed_author]}</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>文字</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: id, canon: "T", volume: 1, number: number)
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
    id
  end

  describe "dynasty_lifespan/0" do
    test "a lifespan inside its dynasty agrees" do
      for n <- 1..25 do
        person!(%{
          id: "T#{n}",
          name: "甲#{n}",
          dynasty: "唐",
          birth_earliest: ~D[0700-01-01],
          death_latest: ~D[0760-01-01]
        })
      end

      assert %{status: :ok, agreed: 25, total: 25} = Coherence.dynasty_lifespan()
    end

    test "a life spanning a dynastic boundary is NOT a disagreement" do
      # People live across the join. Without the tolerance this check would report a failure
      # every time somebody was born under one house and died under the next, which is not a
      # defect in anything.
      for n <- 1..25 do
        person!(%{
          id: "B#{n}",
          name: "乙#{n}",
          dynasty: "唐",
          birth_earliest: ~D[0610-01-01],
          death_latest: ~D[0670-01-01]
        })
      end

      assert %{status: :ok} = Coherence.dynasty_lifespan()
    end

    test "a systematically wrong date fails, and names examples" do
      for n <- 1..25 do
        person!(%{
          id: "C#{n}",
          name: "丙#{n}",
          dynasty: "唐",
          birth_earliest: ~D[1800-01-01],
          death_latest: ~D[1850-01-01]
        })
      end

      assert %{status: :failed, agreed: 0, detail: detail} = Coherence.dynasty_lifespan()
      assert length(detail) == 5
      assert hd(detail) =~ "唐"
    end

    test "a dynasty the table does not name is skipped, never guessed at" do
      # Inventing a span would manufacture disagreement out of nothing.
      for n <- 1..25 do
        person!(%{id: "D#{n}", name: "丁#{n}", dynasty: "高麗", birth_earliest: ~D[1000-01-01]})
      end

      assert %{status: :undecided, total: 0} = Coherence.dynasty_lifespan()
    end
  end

  describe "birthplace_origin/0" do
    setup do
      place!(%{id: "PL_CN", name: "錢塘", district: "中國-浙江省-杭州市"})
      place!(%{id: "PL_JP", name: "京都", district: "日本-京都府"})
      :ok
    end

    test "a small population is reported and NOT judged" do
      person!(%{id: "P1", name: "甲", place_id: "PL_CN"})
      work!("T0001", "0001", attributed_author: "明 甲撰", composition_origin: "japanese")
      Repo.update_all(Work, set: [authority_id: "P1"])

      result = Coherence.birthplace_origin()

      # Two rows is not evidence either way. Before the § A4 fix this same check saw 45
      # Japanese-origin works, 44 by China-born authors, and failed loudly.
      assert result.status == :undecided
      assert Enum.any?(result.detail, &(&1 =~ "too few to judge"))
    end

    test "a systematic mismatch above the minimum population fails" do
      person!(%{id: "P2", name: "乙", place_id: "PL_CN"})

      for n <- 1..25 do
        work!(
          "T#{String.pad_leading(to_string(n), 4, "0")}",
          String.pad_leading(to_string(n), 4, "0"),
          attributed_author: "明 乙撰",
          composition_origin: "japanese"
        )
      end

      Repo.update_all(Work, set: [authority_id: "P2"])

      assert %{status: :failed, agreed: 0, total: 25} = Coherence.birthplace_origin()
    end

    test "translations are excluded — an indic work says nothing about its translator" do
      person!(%{id: "P3", name: "丙", place_id: "PL_CN"})

      for n <- 1..25 do
        work!(
          "T#{String.pad_leading(to_string(n), 4, "0")}",
          String.pad_leading(to_string(n), 4, "0"),
          attributed_author: "唐 丙譯",
          composition_origin: "indic"
        )
      end

      Repo.update_all(Work, set: [authority_id: "P3"])

      # A Chinese monk rendering an Indian sūtra produces an `indic` work. That is the
      # multi-axis provenance working, not a disagreement.
      assert %{status: :undecided, total: 0} = Coherence.birthplace_origin()
    end
  end

  describe "byline_division/0" do
    test "agrees when Taishō division origin matches author byline provenance" do
      # Byline "唐 某撰" has composition_origin: "chinese"
      for n <- 1..25 do
        work!(
          "T#{String.pad_leading(to_string(n), 4, "0")}",
          String.pad_leading(to_string(n), 4, "0"),
          attributed_author: "唐 某撰",
          composition_origin: "chinese"
        )
      end

      assert %{status: :ok, agreed: 25, total: 25} = Coherence.byline_division()
    end

    test "fails when bylines systematically disagree with division table" do
      # Byline "唐 某撰" (chinese) but table says "japanese"
      for n <- 1..25 do
        work!(
          "T#{String.pad_leading(to_string(n), 4, "0")}",
          String.pad_leading(to_string(n), 4, "0"),
          attributed_author: "唐 某撰",
          composition_origin: "japanese"
        )
      end

      assert %{status: :failed, agreed: 0, total: 25, detail: detail} =
               Coherence.byline_division()

      assert length(detail) <= 5
      assert hd(detail) =~ "table says japanese, byline chinese"
    end

    test "too few works is undecided" do
      work!("T0001", "0001", attributed_author: "唐 某撰", composition_origin: "chinese")

      assert %{status: :undecided, agreed: 1, total: 1} = Coherence.byline_division()
    end
  end

  describe "commentary_after_root/0" do
    test "agrees when commentary postdates or is contemporary with root" do
      now = DateTime.utc_now()

      for n <- 1..25 do
        c_id = "T#{String.pad_leading(to_string(100 + n), 4, "0")}"
        r_id = "T#{String.pad_leading(to_string(n), 4, "0")}"

        work!(c_id, "#{100 + n}", attributed_author: "唐 僧撰", composition_origin: "chinese")
        work!(r_id, "#{n}", attributed_author: "後漢 僧譯", composition_origin: "indic")

        Repo.update_all(from(w in Work, where: w.id == ^c_id),
          set: [date_end: 800, date_basis: "catalogue"]
        )

        Repo.update_all(from(w in Work, where: w.id == ^r_id),
          set: [date_start: 200, date_basis: "catalogue"]
        )

        c_text = Repo.one!(from t in "texts", where: t.work_id == ^c_id, select: t.id)
        r_text = Repo.one!(from t in "texts", where: t.work_id == ^r_id, select: t.id)

        Repo.insert_all("commentary_alignments", [
          %{
            lemma: "如是我聞一時佛住",
            lemma_sha256: "sha#{n}",
            length: 8,
            commentary_text_id: c_text,
            commentary_work_id: c_id,
            commentary_urn: "pramana:cbeta.T:#{c_id}@p0001a01",
            commentary_char_start: 0,
            commentary_char_end: 8,
            root_text_id: r_text,
            root_work_id: r_id,
            root_urn: "pramana:cbeta.T:#{r_id}@p0001a01",
            root_char_start: 0,
            root_char_end: 8,
            method: "lemma_match",
            confidence: "certain",
            meta: %{},
            inserted_at: now,
            updated_at: now
          }
        ])
      end

      assert %{status: :ok, agreed: 25, total: 25} = Coherence.commentary_after_root()
    end

    test "fails when commentary predates root work" do
      now = DateTime.utc_now()

      for n <- 1..25 do
        c_id = "T#{String.pad_leading(to_string(100 + n), 4, "0")}"
        r_id = "T#{String.pad_leading(to_string(n), 4, "0")}"

        work!(c_id, "#{100 + n}", attributed_author: "漢 僧撰", composition_origin: "chinese")
        work!(r_id, "#{n}", attributed_author: "唐 僧譯", composition_origin: "indic")

        Repo.update_all(from(w in Work, where: w.id == ^c_id),
          set: [date_end: 200, date_basis: "catalogue"]
        )

        Repo.update_all(from(w in Work, where: w.id == ^r_id),
          set: [date_start: 800, date_basis: "catalogue"]
        )

        c_text = Repo.one!(from t in "texts", where: t.work_id == ^c_id, select: t.id)
        r_text = Repo.one!(from t in "texts", where: t.work_id == ^r_id, select: t.id)

        Repo.insert_all("commentary_alignments", [
          %{
            lemma: "如是我聞一時佛住",
            lemma_sha256: "sha#{n}",
            length: 8,
            commentary_text_id: c_text,
            commentary_work_id: c_id,
            commentary_urn: "pramana:cbeta.T:#{c_id}@p0001a01",
            commentary_char_start: 0,
            commentary_char_end: 8,
            root_text_id: r_text,
            root_work_id: r_id,
            root_urn: "pramana:cbeta.T:#{r_id}@p0001a01",
            root_char_start: 0,
            root_char_end: 8,
            method: "lemma_match",
            confidence: "certain",
            meta: %{},
            inserted_at: now,
            updated_at: now
          }
        ])
      end

      assert %{status: :failed, agreed: 0, total: 25, detail: detail} =
               Coherence.commentary_after_root()

      assert length(detail) <= 5
      assert hd(detail) =~ "explains"
    end
  end

  describe "verdict policy" do
    test "an empty corpus is undecided on every check, never OK" do
      for result <- Coherence.run() do
        assert result.status == :undecided, "#{result.id} claimed a verdict with no data"
        assert result.rate == nil
      end
    end

    test "every check states its question and its floor" do
      for result <- Coherence.run() do
        assert is_binary(result.question) and result.question =~ "?"
        assert is_float(result.floor) and result.floor > 0.0
      end
    end
  end
end
