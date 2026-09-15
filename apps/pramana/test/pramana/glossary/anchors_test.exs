defmodule Pramana.Glossary.AnchorsTest do
  @moduledoc """
  Resolving a glossary's printed citations to lines this corpus holds.

  The tests are about the two things in a Taishō citation that are not a line number: a
  siglum naming whose translation is being quoted, and a **minus sign** that reverses the
  direction of counting. Both were found in the data rather than assumed, and each was
  putting hundreds of citations somewhere wrong or nowhere.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.GlossaryAnchor
  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
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

  describe "resolve_source/2 and glossing/1" do
    setup do
      Repo.insert(%Source{id: "cbeta", name: "CBETA"}, on_conflict: :nothing)
      Repo.insert(%Source{id: "dila-glossaries", name: "DILA Glossaries"}, on_conflict: :nothing)
      Repo.insert(%Witness{id: "w-anchors-T", name: "Taisho"}, on_conflict: :nothing)
      Repo.insert(%Work{id: "T0262", title: "妙法蓮華經"}, on_conflict: :nothing)

      text =
        Repo.insert!(%Text{
          work_id: "T0262",
          witness_id: "w-anchors-T",
          source_id: "cbeta",
          urn_prefix: "pramana:cbeta.T:T0262"
        })

      # Line 23 of page 6 register a
      Repo.insert!(%Segment{
        urn: "pramana:cbeta.T:T0262_001@p0006a23",
        text_id: text.id,
        content: "如是我聞",
        content_sha256: "s1",
        char_start: 0,
        char_end: 4,
        byte_start: 0,
        byte_end: 12,
        page: "0006",
        register: "a",
        line: 23,
        ordinal: 1
      })

      # Line 28 of page 27 register b
      Repo.insert!(%Segment{
        urn: "pramana:cbeta.T:T0262_002@p0027b28",
        text_id: text.id,
        content: "第一行",
        content_sha256: "s2",
        char_start: 5,
        char_end: 8,
        byte_start: 13,
        byte_end: 22,
        page: "0027",
        register: "b",
        line: 28,
        ordinal: 2
      })

      # Line 29 of page 27 register b (foot of register)
      Repo.insert!(%Segment{
        urn: "pramana:cbeta.T:T0262_002@p0027b29",
        text_id: text.id,
        content: "能於四衆示教利喜",
        content_sha256: "s3",
        char_start: 9,
        char_end: 17,
        byte_start: 23,
        byte_end: 47,
        page: "0027",
        register: "b",
        line: 29,
        ordinal: 3
      })

      # Line 1 of page 68 register c (where absent is checked)
      Repo.insert!(%Segment{
        urn: "pramana:cbeta.T:T0262_003@p0068c01",
        text_id: text.id,
        content: "檢查行",
        content_sha256: "s4",
        char_start: 18,
        char_end: 21,
        byte_start: 48,
        byte_end: 57,
        page: "0068",
        register: "c",
        line: 1,
        ordinal: 4
      })

      entry =
        Repo.insert!(%GlossaryEntry{
          source_id: "dila-glossaries",
          gloss_id: "karashima-001",
          chinese: "方便",
          sanskrit: "upāya",
          definition: "skillful means",
          meta: %{
            "citations" => [
              "T.262:6a23",
              "T.262:27b-1",
              "T.262:Z. not found at 68c1",
              "T.262:99a99",
              "T.262:Cf."
            ],
            "glossary" => "karashima"
          }
        })

      # Entry with no citations (should be skipped by resolution)
      Repo.insert!(%GlossaryEntry{
        source_id: "dila-glossaries",
        gloss_id: "karashima-002",
        chinese: "無著",
        english: "unattached",
        definition: "unattached",
        meta: %{}
      })

      %{entry: entry}
    end

    test "resolves citations and persists anchors to database", %{entry: entry} do
      tally = Anchors.resolve_source("dila-glossaries")

      assert tally.total == 5
      assert tally["resolved"] == 2
      assert tally["absent"] == 1
      assert tally["unresolved"] == 2

      anchors = Repo.all(from a in GlossaryAnchor, where: a.entry_id == ^entry.id)
      assert length(anchors) == 5

      # Verify resolved forward citation
      resolved_anchor = Enum.find(anchors, &(&1.citation == "T.262:6a23"))
      assert resolved_anchor.status == "resolved"
      assert resolved_anchor.urn == "pramana:cbeta.T:T0262_001@p0006a23"
      assert resolved_anchor.work_id == "T0262"

      # Verify resolved foot-of-register citation (27b-1 resolves to last line 29)
      foot_anchor = Enum.find(anchors, &(&1.citation == "T.262:27b-1"))
      assert foot_anchor.status == "resolved"
      assert foot_anchor.urn == "pramana:cbeta.T:T0262_002@p0027b29"

      # Verify absent citation (urn is kept, status is absent)
      absent_anchor = Enum.find(anchors, &(&1.citation == "T.262:Z. not found at 68c1"))
      assert absent_anchor.status == "absent"
      assert absent_anchor.urn == "pramana:cbeta.T:T0262_003@p0068c01"

      # Verify unresolved citations
      unresolved_anchor = Enum.find(anchors, &(&1.citation == "T.262:99a99"))
      assert unresolved_anchor.status == "unresolved"
      assert unresolved_anchor.urn == nil
      assert unresolved_anchor.work_id == "T0262"

      invalid_anchor = Enum.find(anchors, &(&1.citation == "T.262:Cf."))
      assert invalid_anchor.status == "unresolved"
      assert invalid_anchor.urn == nil
      assert invalid_anchor.work_id == nil
    end

    test "dry_run does not write to database" do
      tally = Anchors.resolve_source("dila-glossaries", dry_run: true)

      assert tally.total == 5
      assert tally["resolved"] == 2
      assert Repo.aggregate(GlossaryAnchor, :count) == 0
    end

    test "glossing/1 retrieves glosses pointing to a specific segment URN" do
      Anchors.resolve_source("dila-glossaries")

      urn = "pramana:cbeta.T:T0262_001@p0006a23"
      assert [gloss] = Anchors.glossing(urn)
      assert gloss.chinese == "方便"
      assert gloss.sanskrit == "upāya"
      assert gloss.definition == "skillful means"
      assert gloss.status == "resolved"
      assert gloss.citation == "T.262:6a23"
      assert gloss.glossary == "karashima"

      # Absent citation is also retrievable by URN
      absent_urn = "pramana:cbeta.T:T0262_003@p0068c01"
      assert [absent_gloss] = Anchors.glossing(absent_urn)
      assert absent_gloss.status == "absent"
      assert absent_gloss.citation == "T.262:Z. not found at 68c1"

      # Unrelated URN has no glosses
      assert Anchors.glossing("pramana:cbeta.T:T0262_999@p9999z99") == []
    end
  end
end
