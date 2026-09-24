defmodule Pramana.EvalsTest do
  @moduledoc """
  The harness that produces a published number.

  A scorer is a piece of code whose bugs flatter you, so the tests here are mostly about
  the ways a benchmark can lie: counting a broken question as a failure, scoring a case
  type that never ran, averaging unlike things into one figure, or passing because the
  thing under test always says yes.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Evals
  alias Pramana.Evals.Case, as: GoldCase
  alias Pramana.Evals.Score
  alias Pramana.Repo

  @urn "pramana:cbeta.T:T0001_001@p0001a01"
  @content "爾時世尊告諸比丘"

  setup do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Witness{id: "T", name: "Taishō"})

    Repo.insert!(%Work{
      id: "T0001",
      title: "阿含經",
      composition_origin: "indic",
      text_role: "root"
    })

    text =
      Repo.insert!(%Text{
        work_id: "T0001",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T0001",
        body: @content,
        body_sha256: "x",
        meta: %{}
      })

    Repo.insert!(%Segment{
      text_id: text.id,
      urn: @urn,
      ordinal: 0,
      content: @content,
      content_sha256: :crypto.hash(:sha256, @content) |> Base.encode16(case: :lower),
      char_start: 0,
      char_end: String.length(@content),
      byte_start: 0,
      byte_end: byte_size(@content),
      meta: %{}
    })

    :ok
  end

  defp seed_segment!(urn, content, ordinal) do
    text_id = Repo.one!(from(t in Text, where: t.work_id == "T0001", select: t.id))

    Repo.insert!(%Segment{
      text_id: text_id,
      urn: urn,
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

  defp gold(attrs) do
    line = attrs |> Map.new() |> Jason.encode!()
    GoldCase.parse!(line, "test.jsonl", 1)
  end

  describe "progress reporting" do
    # The full set takes hours and printed nothing until it finished, so "how far along is
    # it" had no answer — and a run that had DIED looked exactly like one still working.
    # Both happened in one day.
    test "the callback fires once per case, with the running count and the total" do
      cases =
        for i <- 1..3 do
          gold(%{id: "p#{i}", type: "quote_verify", quote: @content, expect_urns: [@urn]})
        end

      pid = self()

      Evals.run(cases, on_progress: fn done, total, ms -> send(pid, {:tick, done, total, ms}) end)

      assert_received {:tick, 1, 3, _}
      assert_received {:tick, 2, 3, _}
      assert_received {:tick, 3, 3, _}
    end

    test "a run with no callback still works" do
      kase = gold(%{id: "p", type: "quote_verify", quote: @content, expect_urns: [@urn]})

      assert Evals.run([kase]).overall.hits == 1
    end
  end

  describe "the tradition filter narrows the set" do
    test "it selects only that tradition's cases" do
      cases = [
        gold(%{id: "a", type: "topical", query: "x", tradition: "pali", expect_contains: ["x"]}),
        gold(%{
          id: "b",
          type: "topical",
          query: "y",
          tradition: "tibetan",
          expect_contains: ["y"]
        })
      ]

      card = Evals.run(cases, tradition: "pali")

      assert card.total == 1
      assert Map.keys(Score.to_map(card)["cases"]) == ["a"]
    end

    # A filter selecting nothing must not produce a rate. `tally/1` returns nil rather
    # than 0.0 for exactly this reason — a rate over zero cases is the absence of a
    # measurement, and 0.0% would be a claim.
    test "selecting nothing yields no rate rather than 0.0%" do
      cases = [
        gold(%{id: "a", type: "topical", query: "x", tradition: "pali", expect_contains: ["x"]})
      ]

      card = Evals.run(cases, tradition: "tibetan")

      assert card.total == 0
      assert card.by_type == %{}
    end
  end

  describe "a case that throws" do
    # A single lexical query that blew the 120s connection pool timeout took a 4h25m
    # scoring run with it, twice, and lost every case already scored. The crash is
    # injected through the public surface — an over-limit search, which `Hybrid` raises
    # on — rather than by mocking, so the test exercises the real path. `search_override`
    # only reaches cases that actually search, so the `quote_verify` case beside it is
    # unaffected and shows the run carried on.
    @crash [search_override: [limit: 1_000_000]]

    defp searching_case(id) do
      gold(%{id: id, type: "retrieval", query: @content, expect_urns: [@urn]})
    end

    test "is recorded and survived, and the cases after it still run" do
      good = gold(%{id: "after", type: "quote_verify", quote: @content, expect_urns: [@urn]})

      scorecard = Evals.run([searching_case("boom"), good], @crash)

      assert scorecard.overall.errors == 1
      # The whole point: the run finished and the case behind the crash was scored.
      assert scorecard.overall.hits == 1
      assert [%{case: %{id: "boom"}, outcome: {:error, detail}}] = scorecard.errors
      assert detail.kind == "ArgumentError"
      assert detail.message =~ "exceeds the maximum"
    end

    test "is not a miss and not stale — it is excluded from the rate" do
      good = gold(%{id: "ok", type: "quote_verify", quote: @content, expect_urns: [@urn]})

      scorecard = Evals.run([searching_case("boom"), good], @crash)

      # A timeout is not the retriever failing to find the passage. Counting it as one
      # publishes a recall regression that did not happen.
      assert scorecard.overall.misses == 0
      # Nor is it the gold set going out of date; that is someone else's fault entirely.
      assert scorecard.overall.stale == 0
      assert scorecard.overall.scored == 1
      assert scorecard.overall.rate == 100.0
    end

    test "says so in the report and in the machine-readable map" do
      scorecard = Evals.run([searching_case("boom")], @crash)

      report = Score.render(scorecard)
      assert report =~ "ERRORS"
      assert report =~ "boom"
      # A rate over zero scored cases is the absence of a measurement, not a zero.
      assert scorecard.overall.rate == nil

      # Without this, a JSON artefact from an errored run looks like a clean one whose
      # rates happen to be over fewer cases than `total`.
      assert Score.to_map(scorecard)["errors"] == 1
    end
  end

  describe "stale cases" do
    test "a case whose expected URN no longer resolves is stale, not a failure" do
      kase =
        gold(%{
          id: "s-1",
          type: "quote_verify",
          quote: "x",
          expect_urns: ["pramana:cbeta.T:T9999_001@p0001a01"]
        })

      scorecard = Evals.run([kase])

      assert scorecard.overall.stale == 1
      assert scorecard.overall.scored == 0
      # The distinction that matters: an out-of-date gold set must not read as a broken
      # retriever.
      assert scorecard.overall.misses == 0
    end

    test "a case whose quoted text has changed is stale" do
      kase =
        gold(%{
          id: "s-2",
          type: "quote_verify",
          quote: "words that are not there",
          expect_urns: [@urn]
        })

      assert Evals.run([kase]).overall.stale == 1
    end

    test "stale cases are excluded from the rate rather than counted against it" do
      good = gold(%{id: "g", type: "quote_verify", quote: @content, expect_urns: [@urn]})

      broken =
        gold(%{
          id: "b",
          type: "quote_verify",
          quote: "x",
          expect_urns: ["pramana:cbeta.T:T9999_001@p0001a01"]
        })

      scorecard = Evals.run([good, broken])

      assert scorecard.overall.rate == 100.0
      assert scorecard.overall.stale == 1
    end
  end

  describe "the citation guard cases" do
    test "a quotation that is really there passes" do
      kase = gold(%{id: "q-1", type: "quote_verify", quote: @content, expect_urns: [@urn]})

      assert Evals.run([kase]).overall.hits == 1
    end

    test "a quotation altered by one character must be REJECTED to score a hit" do
      # Without this direction the suite measures nothing: a guard that returned :ok
      # unconditionally would score 100% on quote_verify alone.
      altered = String.replace(@content, "世尊", "空尊")
      kase = gold(%{id: "q-2", type: "quote_reject", urn: @urn, quote: altered, expect_urns: []})

      assert Evals.run([kase]).overall.hits == 1
    end

    test "a fabricated URN must be rejected" do
      kase =
        gold(%{
          id: "q-3",
          type: "quote_reject",
          urn: "pramana:cbeta.T:T9999_001@p0001a01",
          quote: @content,
          expect_urns: []
        })

      assert Evals.run([kase]).overall.hits == 1
    end
  end

  describe "provenance cases" do
    test "a work labelled as the catalogue labels it passes" do
      kase =
        gold(%{
          id: "p-1",
          type: "provenance",
          expect_urns: [@urn],
          expect_provenance: %{"composition_origin" => "indic", "text_role" => "root"}
        })

      assert Evals.run([kase]).overall.hits == 1
    end

    test "a mislabelled work fails, and the report says what it expected" do
      kase =
        gold(%{
          id: "p-2",
          type: "provenance",
          expect_urns: [@urn],
          expect_provenance: %{"composition_origin" => "japanese"}
        })

      scorecard = Evals.run([kase])

      assert scorecard.overall.misses == 1
      [%{outcome: {:miss, detail}}] = scorecard.failures
      assert detail.actual == %{composition_origin: "indic"}
    end
  end

  describe "the scorecard" do
    test "reports per type rather than one averaged figure" do
      cases = [
        gold(%{id: "a", type: "quote_verify", quote: @content, expect_urns: [@urn]}),
        gold(%{
          id: "b",
          type: "provenance",
          expect_urns: [@urn],
          expect_provenance: %{"composition_origin" => "japanese"}
        })
      ]

      scorecard = Evals.run(cases)

      # Averaging a guard pass rate with a provenance accuracy produces a number that
      # sounds like an accuracy and means nothing — which is the claim this project
      # exists to answer.
      assert scorecard.by_type[:quote_verify].rate == 100.0
      assert scorecard.by_type[:provenance].rate == 0.0
    end

    test "a rate over zero scored cases is nil, not zero percent" do
      assert Score.summarize([], 0).overall.rate == nil
    end

    test "breaks out adversarial cases" do
      cases = [
        gold(%{id: "a", type: "quote_verify", quote: @content, expect_urns: [@urn]}),
        gold(%{
          id: "b",
          type: "quote_reject",
          urn: @urn,
          quote: "不在這裡",
          expect_urns: [],
          adversarial: true
        })
      ]

      scorecard = Evals.run(cases)

      assert scorecard.adversarial.scored == 1
      assert scorecard.adversarial.rate == 100.0
    end

    test "to_map is what a gate reads, computed from the same run as the report" do
      kase = gold(%{id: "a", type: "quote_verify", quote: @content, expect_urns: [@urn]})
      map = kase |> List.wrap() |> Evals.run() |> Score.to_map()

      assert map["overall"]["rate"] == 100.0
      assert map["by_type"]["quote_verify"]["scored"] == 1
    end

    test "renders without raising, including with failures and stale cases" do
      cases = [
        gold(%{id: "a", type: "quote_verify", quote: @content, expect_urns: [@urn]}),
        gold(%{
          id: "b",
          type: "quote_verify",
          quote: "x",
          expect_urns: ["pramana:cbeta.T:T9999_001@p0001a01"]
        }),
        gold(%{
          id: "c",
          type: "provenance",
          expect_urns: [@urn],
          expect_provenance: %{"composition_origin" => "japanese"}
        })
      ]

      report = cases |> Evals.run() |> Score.render()

      assert report =~ "STALE"
      assert report =~ "FAILURES"
    end
  end

  describe "retrieval cases" do
    # Scored through the LEXICAL path, with no model loaded: these tests pin the
    # scoring logic that turns hits into the published number, not the quality of any
    # particular retriever.
    test "a query that returns the expected passage is a hit, with its rank" do
      kase =
        gold(%{
          id: "r-1",
          type: "retrieval",
          query: @content,
          expect_urns: [@urn],
          k: 10,
          search_opts: %{"lexical_only" => true}
        })

      scorecard = Evals.run([kase])

      assert scorecard.overall.hits == 1
      assert scorecard.by_type[:retrieval].mean_rank == 1.0
    end

    test "a query that returns nothing relevant is a miss" do
      kase =
        gold(%{
          id: "r-2",
          type: "retrieval",
          query: "完全無關的查詢字串",
          expect_urns: [@urn],
          k: 10,
          search_opts: %{"lexical_only" => true}
        })

      assert Evals.run([kase]).overall.misses == 1
    end

    test "a hit beyond k is a miss, and says so rather than silently passing" do
      kase =
        gold(%{
          id: "r-3",
          type: "retrieval",
          query: @content,
          expect_urns: [@urn],
          k: 0,
          search_opts: %{"lexical_only" => true}
        })

      scorecard = Evals.run([kase])
      assert scorecard.overall.misses == 1
      [%{outcome: {:miss, detail}}] = scorecard.failures
      assert detail.beyond_k == 0
    end

    test "any of several expected anchors counts, which is how formulaic text is scored" do
      kase =
        gold(%{
          id: "r-4",
          type: "retrieval",
          query: @content,
          expect_urns: ["pramana:cbeta.T:T0001_001@p9999a99", @urn],
          k: 10,
          search_opts: %{"lexical_only" => true}
        })

      assert Evals.run([kase]).overall.hits == 1
    end

    test "only the named type runs when :only is given" do
      cases = [
        gold(%{id: "a", type: "quote_verify", quote: @content, expect_urns: [@urn]}),
        gold(%{
          id: "b",
          type: "retrieval",
          query: @content,
          expect_urns: [@urn],
          search_opts: %{"lexical_only" => true}
        })
      ]

      scorecard = Evals.run(cases, only: :quote_verify)

      assert scorecard.total == 1
      assert Map.keys(scorecard.by_type) == [:quote_verify]
    end
  end

  describe "absence cases" do
    test "returning nothing where nothing is held is a hit" do
      kase =
        gold(%{
          id: "abs-t1",
          type: "absence",
          query: @content,
          expect_empty: true,
          search_opts: %{"origin" => ["japanese"], "lexical_only" => true},
          adversarial: true
        })

      # No Japanese-composed work exists here, so a filter that works returns nothing.
      assert Evals.run([kase]).overall.hits == 1
    end

    test "returning a forbidden work is a miss even when results look plausible" do
      kase =
        gold(%{
          id: "abs-t2",
          type: "absence",
          query: @content,
          forbid_works: ["pramana:cbeta.T:T0001"],
          search_opts: %{"lexical_only" => true}
        })

      scorecard = Evals.run([kase])

      assert scorecard.overall.misses == 1
      [%{outcome: {:miss, detail}}] = scorecard.failures
      assert detail.returned_forbidden != []
    end

    test "an absence case is never stale, because it expects nothing to resolve" do
      kase = gold(%{id: "abs-t3", type: "absence", query: "x", expect_empty: false})

      assert Evals.run([kase]).overall.stale == 0
    end
  end

  describe "topical cases" do
    test "a passage containing the term is a hit, whatever its URN" do
      # Topical ground truth is a TERM, not an anchor: "where does the canon discuss X"
      # has hundreds of correct answers, and naming one would be arbitrary.
      kase =
        gold(%{
          id: "t-1",
          type: "topical",
          query: @content,
          expect_contains: ["世尊"],
          k: 10,
          search_opts: %{"lexical_only" => true}
        })

      assert Evals.run([kase]).overall.hits == 1
    end

    test "a passage that does not mention the term is a miss" do
      # The term must EXIST in the corpus, or the case is stale rather than failed — so
      # a second passage carries it, and the query steers retrieval to the first.
      seed_segment!("pramana:cbeta.T:T0001_001@p0001a02", "涅槃寂靜甚深微妙", 1)

      kase =
        gold(%{
          id: "t-2",
          type: "topical",
          query: @content,
          expect_contains: ["涅槃"],
          k: 1,
          search_opts: %{"lexical_only" => true}
        })

      assert Evals.run([kase]).overall.misses == 1
    end

    test "a term absent from the corpus is stale, not a retrieval failure" do
      # The question is unanswerable by this bake; blaming the retriever would hide an
      # ingest change behind a number that went down.
      kase =
        gold(%{
          id: "t-3",
          type: "topical",
          query: "anything",
          expect_contains: ["量子力學"],
          search_opts: %{"lexical_only" => true}
        })

      scorecard = Evals.run([kase])

      assert scorecard.overall.stale == 1
      assert scorecard.overall.misses == 0
    end

    test "the scorecard crosses type with tradition, where the interesting cells live" do
      cases = [
        gold(%{
          id: "t-4",
          type: "topical",
          query: @content,
          expect_contains: ["世尊"],
          tradition: "chinese-native",
          search_opts: %{"lexical_only" => true}
        }),
        gold(%{
          id: "t-5",
          type: "topical",
          query: "a question in English about a Chinese passage",
          expect_contains: ["世尊"],
          tradition: "chinese",
          search_opts: %{"lexical_only" => true}
        })
      ]

      scorecard = Evals.run(cases)
      cross = scorecard.by_type_tradition

      # The cross-tab must survive into both the human report and the machine map, or a
      # published number and a gated number could disagree.
      report = Score.render(scorecard)
      assert report =~ "BY CASE TYPE x TRADITION"
      assert report =~ "topical / chinese-native"

      assert Score.to_map(scorecard)["by_type_tradition"]["topical/chinese-native"]["rate"] ==
               100.0

      # Both margins would average these together and hide the difference — which is
      # exactly how a 100%/0% split stayed invisible until the cross-tab existed.
      assert cross[{:topical, "chinese-native"}].rate == 100.0
      assert cross[{:topical, "chinese"}].scored == 1
    end
  end

  describe "answered from any tradition" do
    test "a topic counts as answered when EITHER canon's case hits" do
      # The second case must genuinely MISS, not be stale, so its term has to exist
      # somewhere in the corpus while not being what the query retrieves.
      seed_segment!("pramana:cbeta.T:T0001_001@p0001a09", "涅槃寂靜", 9)

      cases = [
        gold(%{
          id: "any-1",
          type: "topical",
          query: @content,
          expect_contains: ["世尊"],
          tradition: "chinese-native",
          topic: "four-noble-truths",
          search_opts: %{"lexical_only" => true}
        }),
        gold(%{
          id: "any-2",
          type: "topical",
          query: @content,
          expect_contains: ["涅槃"],
          tradition: "pali",
          topic: "four-noble-truths",
          k: 1,
          search_opts: %{"lexical_only" => true}
        })
      ]

      scorecard = Evals.run(cases)

      # One case hit and one missed, so per-tradition reachability is 50% — but the
      # reader asking about the four noble truths WAS answered, and that is a different
      # question. Reporting only the first understated the system badly (#43).
      assert scorecard.by_topic.answered == 1
      assert scorecard.by_topic.topics == 1
      assert scorecard.by_topic.rate == 100.0
      assert scorecard.overall.hits == 1
      assert scorecard.overall.misses == 1
    end

    test "a topic nobody answered is named, not just counted" do
      kase =
        gold(%{
          id: "any-3",
          type: "topical",
          query: @content,
          expect_contains: ["世尊"],
          topic: "unanswerable",
          k: 0,
          search_opts: %{"lexical_only" => true}
        })

      scorecard = Evals.run([kase])

      assert scorecard.by_topic.answered == 0
      assert scorecard.by_topic.unanswered == ["unanswerable"]
    end

    test "cases with no topic are excluded, so a control group cannot inflate it" do
      # The Chinese-native group is asked in Chinese and scores 100% for reasons that
      # have nothing to do with cross-lingual retrieval. Folding it in would flatter the
      # figure.
      kase =
        gold(%{
          id: "any-4",
          type: "topical",
          query: @content,
          expect_contains: ["世尊"],
          tradition: "chinese-native",
          search_opts: %{"lexical_only" => true}
        })

      assert Evals.run([kase]).by_topic.topics == 0
    end
  end
end
