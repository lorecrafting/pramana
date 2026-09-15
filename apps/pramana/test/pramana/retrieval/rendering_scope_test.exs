defmodule Pramana.Retrieval.RenderingScopeTest do
  @moduledoc """
  One definition of what an experimental arm may see, and the proof that both stages read
  it.

  **The defect this guards against has already happened.** `--translators` and
  `--translation_coverage` restricted candidate generation and not ordering, so every arm
  of the 205-case model ladder was reranked against the whole English layer — including the
  renderings that defined the arm by their absence. The repair extracted the rules into
  `Pramana.Retrieval.RenderingScope`; **that repair is worth nothing if the next rule is
  added to one stage again**, which is precisely what happened the first time.

  So the list is derived from `rules/0` rather than written out here. A rule added there
  and wired nowhere fails this file; a rule wired to one stage fails it too.
  """
  use ExUnit.Case, async: true

  alias Pramana.Retrieval.RenderingScope
  alias Pramana.Retrieval.Semantic

  describe "every rule reaches both stages" do
    test "the candidate stage accepts each rule as a search option" do
      missing = RenderingScope.rules() -- Semantic.known_opts()

      assert missing == [],
             """
             `Pramana.Retrieval.RenderingScope` governs #{inspect(missing)}, which
             `Pramana.Retrieval.Semantic` does not declare — so passing it raises
             `unknown search option(s)` and the arm cannot be run at all.

             Add it to Semantic's `@known_opts` and apply it in `single_search/2`.
             """
    end

    test "the reranking stage emits a SQL condition for each rule" do
      # A value per rule that is legal and restrictive. `nil` is "no restriction" for all
      # three, so a rule left unwired would produce no condition and look identical to a
      # rule that was never set — which is the silent form of this defect.
      opts = [translators: ["patton"], translation_coverage: 0.5, translation_chunks: [1]]

      {conditions, params} = RenderingScope.sql_conditions("t", "c", opts, 3)

      assert length(conditions) == length(RenderingScope.rules()),
             """
             `sql_conditions/4` emitted #{length(conditions)} condition(s) for
             #{length(RenderingScope.rules())} rule(s), so at least one rule does not reach
             the reranker. A scope only one stage obeys is not a scope: the arm's
             candidates would be isolated and its ordering computed against everything.

             emitted: #{inspect(conditions)}
             """

      # Parameterised, never interpolated — and numbered from where the caller said.
      assert length(params) == length(conditions)
      assert Enum.all?(conditions, &String.starts_with?(&1, "AND "))
    end

    test "no rule is set by default, so production is unscoped" do
      {conditions, params} = RenderingScope.sql_conditions("t", "c", [], 3)

      assert conditions == []
      assert params == []
    end
  end

  describe "nil and [] are different, and the difference is load-bearing" do
    test "nil translators is every translator; [] is the no-English control" do
      # This distinction IS the no-English arm. `--translators none` used to mean "no
      # English vectors, and rerank against every rendering in the corpus", and was
      # reported as the control for having no English layer at all.
      assert RenderingScope.translators([]) == nil
      assert RenderingScope.translators(translators: []) == []
      assert RenderingScope.translators(translators: ["patton"]) == ["patton"]
    end

    test "full coverage is no restriction rather than a hash comparison against 100" do
      assert RenderingScope.coverage_keep(translation_coverage: 1.0) == nil
      assert RenderingScope.coverage_keep(translation_coverage: 0.25) == 25
      assert RenderingScope.coverage_keep(translation_coverage: 0.0) == 0
    end

    test "an empty chunk set is no restriction, because `translators: []` already says that" do
      assert RenderingScope.chunks(translation_chunks: []) == nil
      assert RenderingScope.chunks(translation_chunks: [7, 9]) == [7, 9]
    end
  end
end
