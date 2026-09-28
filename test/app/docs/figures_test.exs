defmodule Docs.FiguresTest do
  @moduledoc """
  The figures documentation is allowed to state, and the refusal that keeps them honest.

  The dangerous failure is not a wrong number — it is a check that reports green over an
  empty database. Every figure here is a count, so a checkout with no bake regenerates the
  documentation to zeroes and calls it current. This test suite runs in exactly that
  condition, which makes it the right place to pin the refusal.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Docs.Figures

  describe "available?/0" do
    # The sandbox is a real database with no corpus in it — precisely the state that would
    # rewrite `docs/STATUS.md` to say the corpus holds nothing.
    test "is false when no text is loaded, so nothing is written or compared" do
      refute Figures.available?()
    end
  end

  describe "blocks/0" do
    test "every block is a list of label/value pairs, both strings" do
      for {key, figures} <- Figures.blocks() do
        assert is_binary(key)
        assert figures != [], "block #{key} generates nothing, so its marker would render empty"

        for {label, value} <- figures do
          assert is_binary(label)

          assert is_binary(value),
                 "#{label} must be pre-formatted; the document takes it verbatim"
        end
      end
    end

    # Not every figure is a database count, and the one that is not is the one that had two
    # documents disagreeing while the filesystem settled it.
    test "the MCP tool count is read from the directory, so it is right with no corpus" do
      tools =
        Figures.blocks()
        |> Map.fetch!("corpus")
        |> Enum.find_value(fn {label, value} -> label == "MCP tools" && value end)

      assert String.to_integer(tools) > 0
    end

    test "counts read zero on an empty corpus rather than raising" do
      texts =
        Figures.blocks()
        |> Map.fetch!("corpus")
        |> Enum.find_value(fn {label, value} -> label == "texts" && value end)

      assert texts == "0"
    end

    # Not every value is a bare number — `derived` figures are ratios with their unit
    # attached — so the invariant is about the digits, not the shape: a reader who has to
    # count digits will misread the figure. `72120` and `3,923` shared a table until this
    # test was written.
    test "no number reaches a document without thousands separators" do
      unseparated = ~r/(?<![\d,])\d{4,}/

      for {block, figures} <- Figures.blocks(), {label, value} <- figures do
        refute value =~ unseparated,
               "#{block}/#{label} renders #{inspect(value)}; four digits need a separator"
      end
    end
  end
end
