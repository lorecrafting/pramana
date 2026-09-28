defmodule Mix.Tasks.Pramana.Evals.DeriveTest do
  @moduledoc """
  The generator that builds the gold set.

  A defect here is worse than one in the system under test, because it corrupts the
  instrument that would have caught it.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Pramana.Evals.Derive

  describe "alter_one_character/1" do
    test "actually changes the character" do
      original = "才旅遊滋味足未曰旅遊味"
      altered = Derive.alter_one_character(original)

      assert altered != original
      assert String.length(altered) == String.length(original)
    end

    test "a passage whose midpoint is already the substitute is still altered" do
      # The bug this guards. `substitute/1` mapped every Han character to 空, so a passage
      # with 空 at its midpoint was "altered" into itself. The guard then verified the
      # quote — correctly, it really was in the passage — and the harness scored the guard
      # as having FAILED. Invisible at 41 cases, surfaced at 301.
      original = "才，旅遊滋味足未？」空曰：「旅遊滋味則已"
      assert String.at(original, div(String.length(original), 2)) == "空"

      altered = Derive.alter_one_character(original)

      refute altered == original
    end

    test "refuses rather than returning an unaltered string" do
      # nil is a case the caller drops. A reject-case that was never altered is not a weak
      # test, it is a wrong one.
      assert Derive.alter_one_character("") == nil
    end
  end
end
