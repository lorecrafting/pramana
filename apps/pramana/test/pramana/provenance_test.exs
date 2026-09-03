defmodule Pramana.ProvenanceTest do
  @moduledoc """
  Invariant #4, which this module enforces by shape rather than by asking a model to be
  careful: **a Japanese sectarian commentary must never be presentable as an Indian
  sūtra.**

  It was 9% covered. The enforcement is a grouping function, and a grouping function has
  exactly two ways to betray the invariant — putting two provenances in one bucket, and
  losing a result on the way — so those are the properties pinned here rather than the
  strings.

  The strings matter too, and for a reason worth stating: a bucket keyed
  `{"chinese", "apocryphon"}` is unmissable only to a reader who already knows the
  vocabulary, and the reader most likely to mis-attribute is the one who does not.
  """
  use ExUnit.Case, async: true

  doctest Pramana.Provenance

  alias Pramana.Provenance

  defp result(origin, role),
    do: %{span: %{provenance: %{composition_origin: origin, text_role: role}}}

  describe "group/1 — invariant #4 by shape" do
    # The whole feature in one test. These two must not be renderable as a flat list.
    test "a Japanese commentary and an Indian sūtra never share a bucket" do
      groups = Provenance.group([result("indic", "root"), result("japanese", "commentary")])

      assert length(groups) == 2

      for g <- groups, do: assert(g.count == 1)
    end

    # A caller that renders `count` and drops the rest, or renders results and trusts
    # `count`, must not be able to disagree with itself.
    test "no result is lost, and every count matches its bucket" do
      results =
        List.duplicate(result("indic", "root"), 3) ++
          List.duplicate(result("chinese", "commentary"), 2) ++
          [result("japanese", "subcommentary")]

      groups = Provenance.group(results)

      assert Enum.sum(Enum.map(groups, & &1.count)) == length(results)
      for g <- groups, do: assert(g.count == length(g.results))
    end

    # A work nobody has catalogued is a fact about the catalogue, not a reason to hide the
    # work — and hiding it would be the same silence-for-absence error `Pramana.Coverage`
    # exists to prevent.
    test "a result with no provenance is bucketed as unattributed, never dropped" do
      groups = Provenance.group([%{span: %{}}, %{}, result("indic", "root")])

      assert Enum.sum(Enum.map(groups, & &1.count)) == 3

      unattributed = Enum.find(groups, &(&1.composition_origin == Provenance.unattributed()))
      assert unattributed.count == 2
      assert unattributed.text_role == Provenance.unattributed()
    end

    test "provenance is read from a bare map as well as from a span" do
      bare = %{provenance: %{composition_origin: "tibetan", text_role: "treatise"}}

      assert [%{composition_origin: "tibetan", text_role: "treatise"}] = Provenance.group([bare])
    end

    test "every bucket carries a sentence, not only the keys" do
      [group] = Provenance.group([result("japanese", "commentary")])

      assert group.label == "Japanese-composed commentary"
    end

    test "an empty list groups to nothing rather than to an empty bucket" do
      assert Provenance.group([]) == []
    end
  end

  describe "group/1 — ordering" do
    # Alphabetical order would put "chinese" ahead of "indic" always, which quietly
    # implies a precedence the corpus does not have. Largest first says only how many.
    test "the largest bucket comes first" do
      results = [result("japanese", "commentary")] ++ List.duplicate(result("indic", "root"), 2)

      assert [%{composition_origin: "indic", count: 2}, %{composition_origin: "japanese"}] =
               Provenance.group(results)
    end

    test "ties break deterministically, so the same input always renders the same way" do
      results = [result("japanese", "commentary"), result("indic", "root")]

      assert Provenance.group(results) == Provenance.group(Enum.reverse(results))
    end
  end

  describe "label/2" do
    test "names a missing axis as missing rather than guessing it" do
      assert Provenance.label(nil, "root") == "root scripture, origin unattributed"
      assert Provenance.label("indic", nil) == "Indic-composed, role uncatalogued"
    end

    # An unknown value is passed through rather than swallowed: a role the registry has
    # not learned yet should look odd in the output, not vanish into "uncatalogued".
    test "an unrecognised axis is shown, not silently relabelled" do
      assert Provenance.label("martian", "root") =~ "root scripture"
      assert Provenance.label("indic", "colophon") =~ "Indic-composed"
    end
  end

  describe "the registries" do
    # Rule 11: an enumerated value the labels do not know is one no bucket can describe.
    # The check is not "the label differs from the key" — `catalogue`'s plain-language name
    # legitimately IS "catalogue" — but that a DECLARED value is never described as
    # missing, which is the sentence a reader would act on.
    test "a declared origin or role is never described as unattributed" do
      for origin <- Provenance.origins() do
        refute Provenance.label(origin, "root") =~ "origin unattributed",
               "#{origin} is a declared origin and reads as missing"
      end

      for role <- Provenance.roles() do
        refute Provenance.label("indic", role) =~ "role uncatalogued",
               "#{role} is a declared role and reads as missing"
      end
    end

    test "an undeclared value IS described as missing, which is what makes the above mean something" do
      assert Provenance.label("no-such-origin", "root") =~ "origin unattributed"
      assert Provenance.label("indic", "no-such-role") =~ "role uncatalogued"
    end

    test "the unattributed marker is not itself a valid origin or role" do
      refute Provenance.unattributed() in Provenance.origins()
      refute Provenance.unattributed() in Provenance.roles()
    end
  end
end
