defmodule Pramana.Normalize.BilaraTest do
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Bilara

  defp normalize!(map, opts \\ [work_id: "mn1"]) do
    {:ok, ir} = Bilara.normalize(Jason.encode!(map), opts)
    ir
  end

  defp anchors(ir), do: Enum.map(ir.lines, & &1.anchor)

  describe "segment ids" do
    test "become locators with the work prefix removed" do
      ir = normalize!(%{"mn1:1.1" => "Evaṁ me sutaṁ—"})

      assert anchors(ir) == ["1.1"]
      assert hd(ir.lines).text == "Evaṁ me sutaṁ—"
    end

    test "keep every component the edition prints, including letter suffixes" do
      ir = normalize!(%{"mn1:2.1a" => "a", "mn1:2.1b" => "b"}, work_id: "mn1")

      assert anchors(ir) == ["2.1a", "2.1b"]
    end
  end

  describe "ordering" do
    # The failure mode here is silent: string ordering produces a sutta that reads
    # plausibly and is wrong.
    test "is numeric, so 1.10 follows 1.2 rather than preceding it" do
      ir =
        normalize!(%{
          "mn1:1.10" => "tenth",
          "mn1:1.2" => "second",
          "mn1:1.1" => "first",
          "mn1:2.1" => "next section"
        })

      assert anchors(ir) == ["1.1", "1.2", "1.10", "2.1"]
    end

    test "survives a map large enough to lose insertion order" do
      map = Map.new(1..200, fn n -> {"mn1:1.#{n}", "line #{n}"} end)

      assert anchors(normalize!(map)) == Enum.map(1..200, &"1.#{&1}")
    end
  end

  describe "text" do
    # Bilara pads segments with a trailing space so they concatenate into running text.
    # The segment is the citable unit and its sha256 must cover the words, not the
    # typesetting — an unpadded quote of a padded segment would fail the guard.
    test "is trimmed of the padding bilara adds for concatenation" do
      ir = normalize!(%{"mn1:1.1" => "Evaṁ me sutaṁ— "})

      assert hd(ir.lines).text == "Evaṁ me sutaṁ—"
    end

    test "preserves diacritics exactly" do
      ir = normalize!(%{"mn1:1.1" => "ukkaṭṭhāyaṁ viharati subhagavane sālarājamūle"})

      assert hd(ir.lines).text == "ukkaṭṭhāyaṁ viharati subhagavane sālarājamūle"
    end
  end

  describe "titles" do
    test "come from the 0.x block, which is where bilara puts them" do
      ir =
        normalize!(%{
          "mn1:0.1" => "Majjhima Nikāya 1 ",
          "mn1:0.2" => "Mūlapariyāyasutta",
          "mn1:1.1" => "Evaṁ me sutaṁ—"
        })

      assert ir.title == "Majjhima Nikāya 1 — Mūlapariyāyasutta"
    end

    test "are nil rather than invented when the file has no 0.x block" do
      assert normalize!(%{"mn1:1.1" => "Evaṁ me sutaṁ—"}).title == nil
    end
  end

  describe "normalize_file/2" do
    # A file is a packaging unit, not a citation unit. Taking the work id from the
    # filename collapsed ten suttas' `1.0` segments onto one address.
    test "splits one file into one IR per work" do
      {:ok, irs} =
        Bilara.normalize_file(
          Jason.encode!(%{
            "an1.1:0.1" => "Aṅguttara Nikāya 1.1",
            "an1.1:1.1" => "first sutta",
            "an1.2:0.1" => "Aṅguttara Nikāya 1.2",
            "an1.2:1.1" => "second sutta"
          }),
          witness: "ms"
        )

      assert Enum.map(irs, & &1.work_id) == ["an1.1", "an1.2"]
      assert Enum.map(irs, &length(&1.lines)) == [2, 2]
    end

    test "gives each work its own locator space, so identical locators do not collide" do
      {:ok, irs} =
        Bilara.normalize_file(
          Jason.encode!(%{"an1.1:1.0" => "one", "an1.2:1.0" => "two"}),
          witness: "ms"
        )

      assert Enum.map(irs, &{&1.work_id, anchors(&1)}) == [
               {"an1.1", ["1.0"]},
               {"an1.2", ["1.0"]}
             ]
    end

    test "reports malformed JSON rather than raising" do
      assert {:error, _} = Bilara.normalize_file("{not json", witness: "ms")
    end
  end
end
