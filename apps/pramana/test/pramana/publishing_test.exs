defmodule Pramana.PublishingTest do
  @moduledoc """
  What may be published is a licensing decision, and the failure mode is silent: the wrong
  answer publishes text nobody had the right to publish, or withholds text that was public
  domain all along. 66,199 rows spent two phases in the second state.

  The audit itself needs a corpus and so is not tested here; `mix pramana.public.bake`
  runs it as its last step and fails the build on an unsafe result, which is the check
  that matters.
  """
  use ExUnit.Case, async: true

  alias Pramana.Publishing

  describe "publishable?/1" do
    test "reads the licence from the source registry, not from a list kept here" do
      # A second list of "the public ones" is a list that goes stale the first time a
      # source's terms are re-read. These come from `Pramana.Sources`.
      assert Publishing.publishable?("sc")
      assert Publishing.publishable?("derge")
      assert Publishing.publishable?("derge-tengyur")
    end

    test "refuses the sources whose terms forbid redistribution" do
      # CBETA is non-commercial with the header intact; 84000's translations are ND.
      refute Publishing.publishable?("cbeta")
      refute Publishing.publishable?("84000")
      refute Publishing.publishable?("bdrc-derge")
    end

    test "an unknown source is not publishable" do
      # The safe direction for a source nobody has declared terms for.
      refute Publishing.publishable?("some-source-added-tomorrow")
    end
  end

  describe "sources/0" do
    test "is exactly the publishable half of the registry" do
      publishable = Publishing.sources()

      assert "sc" in publishable
      refute "cbeta" in publishable
      assert publishable == Enum.filter(publishable, &Publishing.publishable?/1)
      assert publishable == Enum.sort(publishable)
    end
  end

  describe "total/1" do
    test "sums a bucket" do
      assert Publishing.total([%{rows: 3}, %{rows: 4}]) == 7
      assert Publishing.total([]) == 0
    end
  end
end
