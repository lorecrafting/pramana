defmodule Pramana.RelationsTest do
  @moduledoc """
  Which text a commentary explains.

  Two properties carry the weight. **Method and confidence are part of the claim** — a
  catalogue assertion and an LLM inference must stay distinguishable all the way into an
  answer (`CLAUDE.md` invariant #5). And **relations chain**, so a modern explanation can
  be walked back to root scripture showing the intermediate layers rather than collapsing
  them into a direct claim it never made.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Work
  alias Pramana.Relations
  alias Pramana.Repo

  defp work!(id, attrs) do
    Repo.insert!(
      struct(
        %Work{
          id: id,
          title: id,
          composition_origin: "chinese",
          text_role: "commentary"
        },
        attrs
      )
    )
  end

  setup do
    work!("T0262", %{title: "妙法蓮華經", text_role: "root", composition_origin: "indic"})
    work!("T1718", %{title: "法華文句", date_start: 587})
    work!("T1719", %{title: "法華文句記", text_role: "subcommentary", date_start: 765})
    :ok
  end

  describe "assert/1" do
    test "records a relation with its method and confidence" do
      assert {:ok, r} =
               Relations.assert(%{
                 source_work_id: "T1718",
                 target_work_id: "T0262",
                 relation: "comments_on",
                 method: "catalogue",
                 confidence: "certain"
               })

      assert r.method == "catalogue"
      assert r.confidence == "certain"
      assert r.scope == "whole_work"
    end

    test "is idempotent per (source, target, relation, method)" do
      attrs = %{
        source_work_id: "T1718",
        target_work_id: "T0262",
        relation: "comments_on",
        method: "catalogue"
      }

      {:ok, _} = Relations.assert(attrs)
      {:ok, _} = Relations.assert(attrs)

      assert length(Relations.commentaries_on("T0262")) == 1
    end

    test "keeps the same relation asserted by two methods, because corroboration is information" do
      base = %{source_work_id: "T1718", target_work_id: "T0262", relation: "comments_on"}

      {:ok, _} = Relations.assert(Map.put(base, :method, "catalogue"))
      {:ok, _} = Relations.assert(Map.put(base, :method, "title_match"))

      methods = Relations.commentaries_on("T0262") |> Enum.map(& &1.method) |> Enum.sort()
      assert methods == ["catalogue", "title_match"]
    end

    test "refuses an unknown relation, method or confidence rather than storing it" do
      base = %{source_work_id: "T1718", target_work_id: "T0262"}

      assert {:error, {:unknown_relation, _}} =
               Relations.assert(Map.merge(base, %{relation: "vibes", method: "catalogue"}))

      assert {:error, {:unknown_method, _}} =
               Relations.assert(Map.merge(base, %{relation: "comments_on", method: "guessing"}))

      assert {:error, {:unknown_confidence, _}} =
               Relations.assert(
                 Map.merge(base, %{
                   relation: "comments_on",
                   method: "catalogue",
                   confidence: "sure"
                 })
               )
    end

    test "a target outside the corpus is kept as a reference, not dropped" do
      # A manifest may assert that a commentary explains a work not yet ingested.
      # Discarding the assertion until then would lose real information.
      assert {:ok, r} =
               Relations.assert(%{
                 source_work_id: "T1718",
                 target_work_ref: "xia-lianju-conflation",
                 relation: "comments_on",
                 method: "manifest"
               })

      assert r.target_work_id == nil
      assert r.target_work_ref == "xia-lianju-conflation"
    end
  end

  describe "commentaries_on/2" do
    setup do
      {:ok, _} =
        Relations.assert(%{
          source_work_id: "T1718",
          target_work_id: "T0262",
          relation: "comments_on",
          method: "catalogue",
          confidence: "certain"
        })

      :ok
    end

    test "returns what explains a work, with the assertion's provenance" do
      assert [c] = Relations.commentaries_on("T0262")

      assert c.work_id == "T1718"
      assert c.relation == "comments_on"
      assert c.method == "catalogue"
      assert c.confidence == "certain"
    end

    test "does not return the work itself" do
      refute Enum.any?(Relations.commentaries_on("T0262"), &(&1.work_id == "T0262"))
    end

    test "a root text with nothing pointing at it returns empty" do
      assert Relations.commentaries_on("T1719") == []
    end
  end

  describe "resolve_root/1 — chains" do
    setup do
      # subcommentary → commentary → sūtra
      {:ok, _} =
        Relations.assert(%{
          source_work_id: "T1719",
          target_work_id: "T1718",
          relation: "subcommentary_of",
          method: "catalogue"
        })

      {:ok, _} =
        Relations.assert(%{
          source_work_id: "T1718",
          target_work_id: "T0262",
          relation: "comments_on",
          method: "catalogue"
        })

      :ok
    end

    test "returns the whole path, not just the destination" do
      # The intermediate layer is the point: T1719 explains T1718, which explains T0262.
      # Collapsing that would assert T1719 comments on the sūtra, which it does not.
      assert [first, second] = Relations.resolve_root("T1719")

      assert first.work_id == "T1718"
      assert second.work_id == "T0262"
    end

    test "a root text has an empty chain" do
      assert Relations.resolve_root("T0262") == []
    end

    test "terminates on a cycle instead of looping forever" do
      # Real catalogue data can assert that two works each explain the other.
      {:ok, _} =
        Relations.assert(%{
          source_work_id: "T0262",
          target_work_id: "T1719",
          relation: "comments_on",
          method: "llm"
        })

      chain = Relations.resolve_root("T1719")

      assert length(chain) <= 3
      ids = Enum.map(chain, & &1.work_id)
      assert ids == Enum.uniq(ids)
    end

    test "does not follow `quotes`, which is not a chain step" do
      # Quoting a sūtra does not make a work a commentary on it; following it would
      # report a root the text never claimed to explain.
      work!("T9999", %{title: "引用集"})

      {:ok, _} =
        Relations.assert(%{
          source_work_id: "T9999",
          target_work_id: "T0262",
          relation: "quotes",
          method: "lemma_match"
        })

      assert Relations.resolve_root("T9999") == []
    end
  end

  describe "explanatory?/1" do
    test "distinguishes a work that explains something from scripture" do
      {:ok, _} =
        Relations.assert(%{
          source_work_id: "T1718",
          target_work_id: "T0262",
          relation: "comments_on",
          method: "catalogue"
        })

      assert Relations.explanatory?("T1718")
      refute Relations.explanatory?("T0262")
    end
  end
end
