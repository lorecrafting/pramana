defmodule Pramana.RecallTest do
  @moduledoc """
  Retrieval measured against ground truth the corpus already contains.

  The probe reported **0.0% twice** before it was right, which is exactly what a broken probe
  looks like from outside — and 0.0% is a number somebody could have published. Both mistakes
  are pinned here as tests, because the failure mode of this module is a plausible figure
  rather than an exception.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias Pramana.Recall
  alias Pramana.Repo

  # The same passage, punctuated as CBETA punctuates it, in two works — which is what a
  # verbatim quotation records.
  defp load!(work_id, number) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title>
    <author>唐 某撰</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>
    <lb n="0001a01"/>（三四七）如是我聞：一時，佛
    <lb n="0001a02"/>住王舍城耆闍崛山中。
    </body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: number)
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: %{})
  end

  setup do
    load!("T0099", "0099")
    load!("T0100", "0100")

    Repo.insert_all("quotations", [
      %{
        # Spans a line break, as a real quotation does.
        text: "（三四七）如是我聞：一時，佛\n住王舍城耆闍崛山中。",
        text_sha256: String.duplicate("a", 64),
        length: 25,
        a_text_id: text_id("T0099"),
        a_work_id: "T0099",
        a_urn: "pramana:cbeta.T:T0099_001@p0001a01-p0001a02",
        a_char_start: 0,
        a_char_end: 25,
        b_text_id: text_id("T0100"),
        b_work_id: "T0100",
        b_urn: "pramana:cbeta.T:T0100_001@p0001a01-p0001a02",
        b_char_start: 0,
        b_char_end: 25,
        meta: %{},
        inserted_at: NaiveDateTime.utc_now(:second),
        updated_at: NaiveDateTime.utc_now(:second)
      }
    ])

    :ok
  end

  defp load_into!(source, work_id, number) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title>
    <author>唐 某撰</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>
    <lb n="0001a01"/>（三四七）如是我聞：一時，佛
    </body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: number)
    {:ok, _} = Loader.load(ir, source: source, witness: "T", provenance: %{})
  end

  defp parallel!(source_work, target_work) do
    # LOOKED UP, not constructed. The loader builds a URN prefix from the source and canon,
    # so a hand-written `pramana:cbeta.T:…` is wrong for a work loaded under `sc` — it
    # resolves to nothing, the case comes back `:undecided`, and the probe reports zero for
    # a reason that has nothing to do with retrieval. Which is this module's whole failure
    # mode, reproduced in its own fixture.
    urn = fn w ->
      import Ecto.Query

      Repo.one!(
        from s in "segments",
          join: t in "texts",
          on: t.id == s.text_id,
          where: t.work_id == ^w,
          select: s.urn,
          limit: 1
      )
    end

    Repo.insert_all("text_parallels", [
      %{
        source_uid: source_work,
        target_uid: target_work,
        relation: "full",
        partial: false,
        source_urn: urn.(source_work),
        target_urn: urn.(target_work),
        source_work_id: source_work,
        target_work_id: target_work,
        inserted_at: NaiveDateTime.utc_now(:second),
        updated_at: NaiveDateTime.utc_now(:second)
      }
    ])
  end

  defp text_id(work_id) do
    import Ecto.Query
    Repo.one!(from t in "texts", where: t.work_id == ^work_id, select: t.id)
  end

  test "finds both works that contain a verbatim quotation" do
    assert %{decided: 1, both: 1, one: 0, neither: 0, recall: 1.0} = Recall.run(sample: 10)
  end

  test "REGRESSION: it searches a single line, because a segment is the unit indexed" do
    # A quotation spans lines and the index matches within a segment, so the concatenated
    # passage can never be found inside one. Searching the whole quotation reported every
    # case as `neither` — 0.0% recall, and nothing raised.
    assert %{both: 1} = Recall.run(sample: 10)
  end

  test "REGRESSION: it does NOT strip punctuation, which is the reverse of elsewhere" do
    # The stored segments carry CBETA's editorial punctuation. A stripped query matches none
    # of them — the second way this probe reported 0.0%. Stripping is right when comparing
    # two passages and wrong when querying the index, because the index holds what the editor
    # printed.
    #
    # The fixture's punctuation is load-bearing: without `（三四七）` and `：`, a stripped
    # query would match and this test would pass while the code was wrong.
    assert %{recall: 1.0} = Recall.run(sample: 10)
  end

  test "a sample is reproducible, or it is an anecdote" do
    # `order by random()` gives a different answer every run, so no figure could be compared
    # with the one before it — the failure `docs/PROXIES.md` exists to record.
    first = Recall.run(sample: 1, seed: 0.5)
    second = Recall.run(sample: 1, seed: 0.5)

    assert Enum.map(first.misses, & &1.a_work) == Enum.map(second.misses, & &1.a_work)
    assert first.sampled == second.sampled
  end

  describe "parallels/1 — the axis that has never moved" do
    setup do
      # The same passage in two SOURCES. `topical/chinese` is 0% of twelve gold cases;
      # SuttaCentral's curated parallels are 10,493 Pāli↔Chinese judgements made by scholars,
      # which is the same free ground truth pointed at the weak axis.
      load_into!("sc", "SC001", "0801")
      load_into!("cbeta", "T0201", "0201")
      load_into!("cbeta", "T0202", "0202")

      parallel!("SC001", "T0201")
      parallel!("T0201", "T0202")

      :ok
    end

    test "reports the cross-lingual rate and the control separately" do
      result = Recall.parallels(sample: 10, mode: :lexical)

      assert result.verdict == :measured
      assert result.control.found > 0
      assert result.cross_lingual.found > 0
      assert result.cross_lingual.rate == 1.0
    end

    test "VOID, not zero, when the control cannot find its own pairs" do
      # This module reported a false 0.0% twice. A cross-lingual zero with no working control
      # is indistinguishable from a broken query path, and "retrieval cannot do this" and "we
      # cannot measure this" are different conclusions to hand somebody.
      Repo.delete_all("text_parallels")
      parallel!("SC001", "T0201")

      result = Recall.parallels(sample: 10, mode: :lexical)

      assert result.verdict == :void
      assert result.control.decided == 0
    end
  end

  test "a full result set is undecided, never a miss" do
    # A phrase in three hundred places cannot have both ends inside a cap of one, and
    # counting that as a failure measures `limit` rather than the retriever.
    assert %{undecided: 1, decided: 0, recall: nil} = Recall.run(sample: 10, limit: 1)
  end
end
