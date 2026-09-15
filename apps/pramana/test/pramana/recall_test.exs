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

  # Rows that no search can find, so every drawn case is a `:neither` and therefore appears
  # in `misses` — which is the only place `run/1` reports WHICH rows it drew.
  defp quotation!(text, length) do
    Repo.insert_all("quotations", [
      %{
        text: text,
        text_sha256: String.duplicate("b", 64),
        length: length,
        a_text_id: text_id("T0099"),
        a_work_id: "T0099",
        a_urn: "pramana:cbeta.T:T0099_001@p0001a01",
        # DISTINCT OFFSETS PER ROW. `quotations` is uniquely indexed on
        # (a_text_id, a_char_start, b_text_id, b_char_start), so twenty rows all starting at
        # 0 are one row and nineteen constraint violations.
        a_char_start: length,
        a_char_end: length + 10,
        b_text_id: text_id("T0100"),
        b_work_id: "T0100",
        b_urn: "pramana:cbeta.T:T0100_001@p0001a01",
        b_char_start: length,
        b_char_end: length + 10,
        meta: %{},
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

  test "REGRESSION: a sample is reproducible, and the seed must survive the pool" do
    # `setseed` seeds one Postgres SESSION. `Repo.query!` takes whatever connection the pool
    # hands it, so the seed landed in one session and the `ORDER BY random()` it was meant to
    # seed ran in another. Measured on 2026-08-29: **eight calls with one seed drew eight
    # different samples.** `--seed` did nothing, and every figure published under one —
    # `docs/PLAN.md` § F included — was an unseeded draw.
    #
    # THE TEST THIS REPLACED ASSERTED THE SAME PROPERTY AND PASSED THROUGHOUT, because it
    # drew `sample: 1` from a one-row fixture, where every possible sample is identical. A
    # reproducibility test needs a population big enough for an unseeded draw to differ.
    Repo.delete_all("quotations")
    for i <- 1..20, do: quotation!("ZZZ-not-in-any-work-#{i}", 100 + i)

    # `length` is a per-row id here, so this compares WHICH rows were drawn and in what
    # order. Twenty rows choose five ordered: an unseeded draw repeats by chance about
    # once in 1.9 million.
    drawn = fn -> Recall.run(sample: 5, seed: 0.5).misses |> Enum.map(& &1.length) end

    first = drawn.()
    assert length(first) == 5

    for _ <- 1..3, do: assert(drawn.() == first)
  end

  # WHAT THESE TWO TESTS DO NOT CATCH, stated because a test whose limits are unwritten gets
  # trusted for the thing it cannot do.
  #
  # They catch a seed that is IGNORED — dropped argument, removed `setseed`. They cannot
  # catch a seed sent to the WRONG CONNECTION, which is the defect that actually happened:
  # `Pramana.DataCase` uses Ecto's SQL sandbox, which checks out ONE connection and pins it
  # for the whole test, so `setseed` and its query always share a session here no matter how
  # the code is written. **Verified on 2026-08-29 by deleting the transaction from
  # `seeded/2`: all nine tests still passed.**
  #
  # Which generalises past this file: NO pool-dependent defect is visible to this suite. A
  # sandboxed test runs on one connection by construction, and a bug that only appears when
  # two calls land on two connections is invisible to every test in it. The only instrument
  # that sees it is a script against a real pool — see `docs/RULES.md` 67.

  test "a different seed draws a different sample, or the seed is being ignored" do
    # The mirror of the test above, and the one that catches a `seeded/2` that silently
    # swallows its argument: identical output under two different seeds passes every
    # reproducibility check ever written.
    Repo.delete_all("quotations")
    for i <- 1..20, do: quotation!("ZZZ-not-in-any-work-#{i}", 100 + i)

    a = Recall.run(sample: 5, seed: 0.1).misses |> Enum.map(& &1.length)
    b = Recall.run(sample: 5, seed: 0.9).misses |> Enum.map(& &1.length)

    refute a == b
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

    test "a hit carries what it landed on, because at 0.4% the misses say nothing" do
      # Two of 496 cross-lingual cases landed and the run reported only the 494 failures, so
      # the only positive evidence about what crosses the language barrier went on the floor.
      result = Recall.parallels(sample: 10, mode: :lexical)

      assert [hit] = result.hits
      assert hit.target_work == "T0201"
      assert hit.rank >= 1
      assert hit.query =~ "如是我聞"
      assert hit.matched_text =~ "如是我聞"

      # WORK-LEVEL RECALL IS NOT LINE-LEVEL. `exact_rank` is the whole reason a hit is worth
      # printing: it separates *the parallel's own line came back* from *some line of a work
      # with thousands of them did*, and without it the two read identically.
      assert hit.matched_urn == hit.target_urn
      assert hit.exact_rank == hit.rank
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

  describe "renderings/1 --to" do
    defp render!(anchor, work_id, text) do
      {:ok, _} =
        Pramana.Translations.store([
          %{
            anchor_urn: anchor,
            work_id: work_id,
            lang: "en",
            translator_id: "patton",
            tier: "t0",
            method: "human",
            text: text,
            redistributable: true,
            license_class: "cc0"
          }
        ])
    end

    setup do
      # Long enough to be a query — the probe drops renderings under 80 characters,
      # because a four-word sentence measures nothing.
      render!(
        "pramana:cbeta.T:T0099_001@p0001a01",
        "T0099",
        "So I have heard. At one time the Buddha was staying on Vulture Peak Mountain near Rājagṛha."
      )

      render!(
        "pramana:sc.ms:mn1@1.1",
        "mn1",
        "So I have heard. At one time the Buddha was staying near Ukkaṭṭhā in the Subhaga Forest."
      )

      :ok
    end

    # Rule 5: a filter that is accepted and does nothing produces results that look
    # filtered and are not. This one exists because the Chinese canon is 1.4% of the
    # rendering pool, so an unfiltered sample cannot score it — a filter that quietly
    # sampled everything would put a Pāli rate under a Chinese heading.
    test "restricts the sample to one target namespace" do
      chinese = Recall.renderings(sample: 50, mode: :lexical, to: "cbeta.T")
      pali = Recall.renderings(sample: 50, mode: :lexical, to: "sc.ms")
      both = Recall.renderings(sample: 50, mode: :lexical)

      assert Map.keys(chinese.by_language) == ["cbeta.T"]
      assert Map.keys(pali.by_language) == ["sc.ms"]
      assert Enum.sort(Map.keys(both.by_language)) == ["cbeta.T", "sc.ms"]
    end

    # Rules 22, 44 and 54, inside the instrument. `by_language` used to be a count of
    # hits with nothing to divide it by, so "cbeta.T => 2" could not be told from 2 of 2
    # or 2 of 40 — and 2 of 40 is the reading that would have mattered.
    test "every language carries its own denominator" do
      %{by_language: by_language} = Recall.renderings(sample: 50, mode: :lexical)

      for {_namespace, scored} <- by_language do
        assert %{decided: _, found: _, rate: _} = scored
        assert scored.decided <= scored.sampled
      end
    end
  end
end
