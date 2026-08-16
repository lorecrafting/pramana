defmodule Pramana.EvalsTest do
  @moduledoc """
  The harness that produces a published number.

  A scorer is a piece of code whose bugs flatter you, so the tests here are mostly about
  the ways a benchmark can lie: counting a broken question as a failure, scoring a case
  type that never ran, averaging unlike things into one figure, or passing because the
  thing under test always says yes.
  """
  use Pramana.DataCase, async: false

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

  defp gold(attrs) do
    line = attrs |> Map.new() |> Jason.encode!()
    GoldCase.parse!(line, "test.jsonl", 1)
  end

  describe "loading" do
    test "a case records where it came from, so a published number is traceable" do
      kase =
        gold(%{
          id: "x-1",
          type: "quote_verify",
          quote: @content,
          expect_urns: [@urn],
          source: "the passage itself"
        })

      assert kase.origin == {"test.jsonl", 1}
      assert kase.source == "the passage itself"
    end

    test "an unknown case type raises rather than being skipped" do
      assert_raise ArgumentError, ~r/unknown case type/, fn ->
        gold(%{id: "x", type: "vibes", quote: "a"})
      end
    end

    test "an unknown provenance key raises, and gold data can never mint an atom" do
      assert_raise ArgumentError, ~r/unknown provenance key/, fn ->
        gold(%{
          id: "x",
          type: "provenance",
          expect_urns: [@urn],
          expect_provenance: %{"nope" => 1}
        })
      end
    end

    test "an unknown search option raises" do
      assert_raise ArgumentError, ~r/unknown search option/, fn ->
        gold(%{id: "x", type: "retrieval", query: "q", search_opts: %{"orgin" => "indic"}})
      end
    end

    test "case types parse from a cold start, with no atom pre-existing" do
      # `String.to_existing_atom/1` has broken this codebase three times: it raises
      # unless the atom happens to be loaded, so the same input works after one code
      # path and fails after another.
      for type <- GoldCase.types() do
        assert GoldCase.type_atom(type) == String.to_atom(type)
      end
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

  describe "covers?/2" do
    test "a chunk's range URN covers a segment inside it" do
      assert Evals.covers?("pramana:sc.ms:mn1@1.1-1.9", "pramana:sc.ms:mn1@1.4")
    end

    test "an exact anchor covers itself" do
      assert Evals.covers?(@urn, @urn)
    end

    test "a different work never covers, however similar the locator" do
      refute Evals.covers?("pramana:sc.ms:mn2@1.1-1.9", "pramana:sc.ms:mn1@1.4")
    end

    test "a different source never covers" do
      refute Evals.covers?("pramana:cbeta.T:mn1@1.4", "pramana:sc.ms:mn1@1.4")
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

  describe "load/1" do
    @tag :tmp_dir
    test "reads every jsonl file in a directory", %{tmp_dir: dir} do
      File.write!(
        Path.join(dir, "a.jsonl"),
        Jason.encode!(%{id: "a", type: "quote_verify", quote: @content, expect_urns: [@urn]}) <>
          "\n"
      )

      assert {:ok, [kase]} = Evals.load(dir)
      assert kase.id == "a"
    end

    @tag :tmp_dir
    test "an empty directory is an error, not an empty pass", %{tmp_dir: dir} do
      # A scorecard over zero cases would report 100% of nothing.
      assert {:error, {:no_gold_set, _}} = Evals.load(dir)
    end
  end
end
