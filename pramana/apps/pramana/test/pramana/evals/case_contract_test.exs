defmodule Pramana.Evals.CaseContractTest do
  use ExUnit.Case, async: true
  alias Pramana.Evals
  alias Pramana.Evals.Case, as: GoldCase
  @urn "pramana:cbeta.T:T0001_001@p0001a01"
  @content "爾時世尊告諸比丘"
  defp gold(attrs), do: attrs |> Map.new() |> Jason.encode!() |> GoldCase.parse!("test.jsonl", 1)

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

    test "case type names map to their declared atoms" do
      # Mapping behavior here; ColdStartTest owns the fresh-VM atom-table contract.
      for type <- GoldCase.types() do
        assert GoldCase.type_atom(type) == String.to_atom(type)
      end
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
