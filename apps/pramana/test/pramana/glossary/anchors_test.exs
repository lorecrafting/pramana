defmodule Pramana.Glossary.AnchorsTest do
  @moduledoc """
  Resolving a glossary's printed citations to lines this corpus holds.

  The tests are about the two things in a Taishō citation that are not a line number: a
  siglum naming whose translation is being quoted, and a **minus sign** that reverses the
  direction of counting. Both were found in the data rather than assumed, and each was
  putting hundreds of citations somewhere wrong or nowhere.
  """
  use ExUnit.Case, async: true

  alias Pramana.Glossary.Anchors

  doctest Pramana.Glossary.Anchors

  describe "parse/1" do
    test "a bare citation" do
      assert {:ok, p} = Anchors.parse("T.262:6a23")
      assert p.work_id == "T0262"
      # CBETA pads the page to four digits; `p6a23` addresses nothing.
      assert p.page == "0006"
      assert p.register == "a"
      assert p.line == 23
      refute p.from_foot
      refute p.absent
    end

    test "a siglum naming the translation is not part of the address" do
      assert {:ok, %{work_id: "T0224", page: "0464", register: "b", line: 18}} =
               Anchors.parse("T.224:Lk. 464b18")

      assert {:ok, %{work_id: "T0263", page: "0105", register: "b", line: 4}} =
               Anchors.parse("T.263:Z. 105b4.")
    end

    # THE ONE THAT PUT 285 CITATIONS NOWHERE. `27b-1` is the LAST line of the register,
    # not line 1. Verified against the text before it was implemented: the entry citing
    # `T.262 27b-1` quotes 能於四衆示教利喜, which sits at line 29 of a register whose last
    # line is 29.
    test "a minus sign counts from the foot of the register" do
      assert {:ok, %{page: "0027", register: "b", line: 1, from_foot: true}} =
               Anchors.parse("T.262:27b-1")

      assert {:ok, %{page: "0019", register: "a", line: 6, from_foot: true}} =
               Anchors.parse("T.262:19a-6")
    end

    # Karashima records a NON-correspondence by naming the line he checked. The address is
    # real and the claim is that nothing is there, so it parses and is flagged rather than
    # being discarded as noise.
    test "'not found' is an address plus a claim, and both survive" do
      assert {:ok, p} = Anchors.parse("T.263:Z. not found at 68c1")
      assert p.work_id == "T0263"
      assert p.page == "0068"
      assert p.register == "c"
      assert p.line == 1
      assert p.absent
    end

    test "a cross-reference carrying no address is refused rather than guessed at" do
      assert {:error, {:unparseable_locator, "T.224:Cf."}} = Anchors.parse("T.224:Cf.")
    end

    test "a work outside the Taishō is refused" do
      assert {:error, {:unknown_work, _}} = Anchors.parse("X.1234:5a6")
    end
  end
end
