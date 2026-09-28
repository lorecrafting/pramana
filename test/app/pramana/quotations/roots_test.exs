defmodule Pramana.Quotations.RootsTest do
  @moduledoc """
  What a commentary comments on, proposed from the quotation graph.

  Four properties carry the weight, and each was a wrong answer before it was a test.

  **Distinct passages, never rows.** A root text that repeats itself contributes one
  quotation row per repetition, so a single stock phrase printed five times outvoted a
  real root — rule 73.

  **Families, not work ids.** `T0220a`–`T0220d` are one work, and counting them
  separately splits the evidence and manufactures ties — rule 72.

  **Partners restricted to root-role works**, without which two commentaries on one sūtra
  point at each other.

  **A tie is not an answer**, and neither is a role nothing has tested.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Quotations.Roots
  alias Pramana.Repo

  setup do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Witness{id: "T", name: "Taishō"})
    :ok
  end

  defp work!(id, role) do
    Repo.insert!(%Work{id: id, title: "title-#{id}", text_role: role})

    Repo.insert!(%Text{
      work_id: id,
      source_id: "cbeta",
      witness_id: "T",
      urn_prefix: "pramana:cbeta.T:#{id}",
      body: "",
      body_sha256: "x",
      meta: %{}
    })
  end

  # One shared passage between two works. `text` identifies the passage: repeating the
  # same string is the corpus repeating itself, which must not count twice. Offsets are
  # distinct per row because that is what a repeated passage looks like — the same
  # characters printed at a different place — and the table's unique index says so.
  defp shared!(a, b, label) do
    # The table refuses a match shorter than 20 characters — a scan that admitted them
    # would be reporting coincidence — so a fixture passage is padded to a plausible
    # length while staying identified by its label.
    text = String.pad_trailing(label, 20, "。")
    offset = System.unique_integer([:positive, :monotonic])

    Repo.insert!(%Quotation{
      text: text,
      text_sha256: Base.encode16(:crypto.hash(:sha256, text), case: :lower),
      length: String.length(text),
      a_text_id: a.id,
      a_work_id: a.work_id,
      a_urn: "#{a.urn_prefix}_001@p0001a01",
      a_char_start: offset,
      a_char_end: offset + String.length(text),
      b_text_id: b.id,
      b_work_id: b.work_id,
      b_urn: "#{b.urn_prefix}_001@p0001a01",
      b_char_start: offset,
      b_char_end: offset + String.length(text),
      meta: %{}
    })
  end

  defp for_work(candidates, id), do: Enum.find(candidates, &(&1.work_id == id))

  describe "candidates/1" do
    test "proposes the dominant root partner, and the runner-up travels with it" do
      commentary = work!("T1509", "commentary")
      root = work!("T0223", "root")
      other = work!("T0224", "root")

      for n <- 1..6, do: shared!(commentary, root, "root passage #{n}")
      shared!(commentary, other, "stray passage")

      candidate = for_work(Roots.candidates(), "T1509")

      assert candidate.target_work_id == "T0223"
      assert candidate.passages == 6
      assert candidate.runner_up == 1
      assert candidate.families == 2
      assert candidate.band == :strong
    end

    test "a passage the root repeats counts once, not once per printing" do
      commentary = work!("T1723", "commentary")
      repetitive = work!("T0220a", "root")
      real = work!("T0262", "root")

      # The ten-stage list, printed five times in the longer text. Counting rows would
      # make this 5 against 2 and propose the wrong root.
      for _ <- 1..5, do: shared!(commentary, repetitive, "乾慧地性地八人地見地")
      shared!(commentary, real, "諸佛世尊唯以一大事因緣故")
      shared!(commentary, real, "十方佛土中唯有一乘法")

      candidate = for_work(Roots.candidates(), "T1723")

      assert candidate.target_work_id == "T0262"
      assert candidate.passages == 2
      assert candidate.runner_up == 1
    end

    test "divisions of one work are counted as one partner and reported as its members" do
      commentary = work!("T1695", "commentary")
      first = work!("T0220a", "root")
      second = work!("T0220b", "root")
      rival = work!("T0262", "root")

      shared!(commentary, first, "般若理趣分 one")
      shared!(commentary, first, "般若理趣分 two")
      shared!(commentary, second, "般若理趣分 three")
      for n <- 1..2, do: shared!(commentary, rival, "lotus #{n}")

      candidate = for_work(Roots.candidates(), "T1695")

      assert candidate.family == "T0220"
      assert candidate.passages == 3, "the family's members must be summed, not ranked apart"
      assert candidate.target_work_id == "T0220a", "the best-attested witness is proposed"

      assert candidate.family_members == [
               %{work_id: "T0220a", passages: 2},
               %{work_id: "T0220b", passages: 1}
             ]
    end

    test "a partner in the source's own family is self-reference, not evidence" do
      commentary = work!("T1510a", "commentary")
      sibling = work!("T1510b", "root")
      root = work!("T0236a", "root")

      for n <- 1..9, do: shared!(commentary, sibling, "same work, other id #{n}")
      shared!(commentary, root, "diamond")

      candidate = for_work(Roots.candidates(), "T1510a")

      assert candidate.target_work_id == "T0236a"
      assert candidate.families == 1
    end

    test "a commentary is never proposed as another commentary's root" do
      commentary = work!("T1703", "commentary")
      neighbour = work!("T1701", "commentary")
      root = work!("T0235", "root")

      for n <- 1..9, do: shared!(commentary, neighbour, "the sutra's own words #{n}")
      shared!(commentary, root, "diamond")

      candidate = for_work(Roots.candidates(), "T1703")

      assert candidate.target_work_id == "T0235",
             "restricting partners to root-role works is what makes the rule work at all"
    end

    test "a work with no root partner at all is absent, not proposed with nothing" do
      commentary = work!("T9999", "commentary")
      neighbour = work!("T9998", "commentary")
      shared!(commentary, neighbour, "only a commentary")

      assert for_work(Roots.candidates(), "T9999") == nil
    end

    test "equal partners are a tie, and a tie is banded apart" do
      commentary = work!("T1716", "commentary")
      one = work!("T0227", "root")
      two = work!("T0262", "root")

      shared!(commentary, one, "stock phrase A")
      shared!(commentary, two, "stock phrase B")

      candidate = for_work(Roots.candidates(), "T1716")

      assert candidate.tied == 2
      assert candidate.band == :tied
    end

    test "min_passages excludes, and is proven to change the result set" do
      commentary = work!("T1792", "commentary")
      root = work!("T0685", "root")
      shared!(commentary, root, "a single passage")

      assert for_work(Roots.candidates(), "T1792")
      refute for_work(Roots.candidates(min_passages: 2), "T1792")
    end
  end

  describe "assertable/1" do
    setup do
      root = work!("T0220a", "root")

      for {id, role} <- [
            {"T1537", "treatise"},
            {"T1789", "commentary"},
            {"T1830", "subcommentary"}
          ] do
        work = work!(id, role)
        for n <- 1..6, do: shared!(work, root, "#{id} passage #{n}")
      end

      :ok
    end

    test "keeps the one role whose works are about root scripture" do
      assertable = Roots.candidates() |> Roots.assertable() |> Enum.map(& &1.work_id)

      assert "T1789" in assertable
    end

    test "refuses treatises, which nothing has tested and which need not be about anything" do
      candidates = Roots.candidates()

      assert for_work(candidates, "T1537"), "a refused proposal is still derived and reported"
      refute "T1537" in Enum.map(Roots.assertable(candidates), & &1.work_id)
    end

    # 論疏部 (T1816-T1850) explains 論, and every 論 division is `text_role: treatise`, so
    # the partner set excludes by construction the only works these can be about. A
    # `subcommentary_of` aimed at a sūtra is incoherent however strong the evidence.
    test "refuses subcommentaries, whose roots are treatises the partner set excludes" do
      candidates = Roots.candidates()

      assert for_work(candidates, "T1830"), "a refused proposal is still derived and reported"
      refute "T1830" in Enum.map(Roots.assertable(candidates), & &1.work_id)
    end

    test "refuses a tie regardless of role" do
      commentary = work!("T1711", "commentary")
      for id <- ["T0253", "T0262"], do: shared!(commentary, work!(id, "root"), "one phrase #{id}")

      candidates = Roots.candidates()

      assert for_work(candidates, "T1711").band == :tied
      refute "T1711" in Enum.map(Roots.assertable(candidates), & &1.work_id)
    end
  end

  describe "already_rooted/0" do
    test "a work is corroborated, not newly linked, when something already explains it" do
      commentary = work!("T1789", "commentary")
      root = work!("T0670", "root")
      unlinked = work!("T1799", "commentary")
      other = work!("T0945", "root")

      for n <- 1..6, do: shared!(commentary, root, "lanka #{n}")
      for n <- 1..6, do: shared!(unlinked, other, "surangama #{n}")

      Repo.insert!(%WorkRelation{
        source_work_id: "T1789",
        target_work_id: "T0670",
        relation: "comments_on",
        method: "title_match",
        confidence: "probable",
        scope: "whole_work",
        evidence: %{}
      })

      rooted = Roots.already_rooted()

      assert MapSet.member?(rooted, "T1789")
      refute MapSet.member?(rooted, "T1799")
    end

    test "a parallel is a sibling, not a root, and does not count as reaching one" do
      work!("T0099", "root")
      work!("T0100", "root")

      Repo.insert!(%WorkRelation{
        source_work_id: "T0099",
        target_work_id: "T0100",
        relation: "parallel_of",
        method: "catalogue",
        confidence: "probable",
        scope: "whole_work",
        evidence: %{}
      })

      refute MapSet.member?(Roots.already_rooted(), "T0099")
    end
  end

  describe "thresholds the task reports" do
    test "the assertable roles and the strong floor are read from here, not restated" do
      assert Roots.assertable_roles() == ~w(commentary)
      assert Roots.strong_passages() == 5
    end
  end

  describe "validate/1" do
    test "scores only against title-matched links, and reports the roles it scored" do
      commentary = work!("T1789", "commentary")
      root = work!("T0670", "root")
      unscored = work!("T1799", "commentary")
      other = work!("T0945", "root")

      for n <- 1..6, do: shared!(commentary, root, "lanka #{n}")
      for n <- 1..6, do: shared!(unscored, other, "surangama #{n}")

      Repo.insert!(%WorkRelation{
        source_work_id: "T1789",
        target_work_id: "T0670",
        relation: "comments_on",
        method: "title_match",
        confidence: "probable",
        scope: "whole_work",
        evidence: %{}
      })

      assert %{
               written: %{works: 1, correct: 1, bands: [%{band: :strong, works: 1, correct: 1}]},
               refused: %{works: 0, correct: 0, bands: []},
               roles: %{"commentary" => 1}
             } = Roots.candidates() |> Roots.validate()
    end

    # The two sides are never summed. Blending them charges the rule for proposals it
    # declines to write, and hides whether declining them was right.
    test "a refused proposal is scored apart from a written one, never blended in" do
      root = work!("T0670", "root")
      written = work!("T1789", "commentary")
      refused = work!("T1537", "treatise")

      for n <- 1..6, do: shared!(written, root, "written #{n}")
      for n <- 1..6, do: shared!(refused, root, "refused #{n}")

      for id <- ["T1789", "T1537"] do
        Repo.insert!(%WorkRelation{
          source_work_id: id,
          target_work_id: "T0670",
          relation: "comments_on",
          method: "title_match",
          confidence: "probable",
          scope: "whole_work",
          evidence: %{}
        })
      end

      assert %{
               written: %{works: 1, correct: 1},
               refused: %{works: 1, correct: 1},
               roles: %{"commentary" => 1, "treatise" => 1}
             } = Roots.candidates() |> Roots.validate()
    end

    test "bands come back strongest first, and a wrong proposal scores as wrong" do
      root = work!("T0670", "root")
      rival = work!("T0945", "root")

      cases = [
        # dominant and well attested, and right
        {"T1789", ["T0670"], 6, 0},
        # dominant on one passage, and wrong: the title says T0670
        {"T1799", ["T0670"], 0, 1},
        # tied, so not written, and scored apart
        {"T1800", ["T0670"], 1, 1}
      ]

      for {id, _targets, to_root, to_rival} <- cases do
        work = work!(id, "commentary")
        # `//1` matters: `1..0` counts DOWN and would silently insert two rows.
        for n <- 1..to_root//1, do: shared!(work, root, "#{id} root #{n}")
        for n <- 1..to_rival//1, do: shared!(work, rival, "#{id} rival #{n}")
      end

      for {id, targets, _, _} <- cases, target <- targets do
        Repo.insert!(%WorkRelation{
          source_work_id: id,
          target_work_id: target,
          relation: "comments_on",
          method: "title_match",
          confidence: "probable",
          scope: "whole_work",
          evidence: %{}
        })
      end

      assert %{
               written: %{
                 bands: [
                   %{band: :strong, works: 1, correct: 1},
                   %{band: :weak, works: 1, correct: 0}
                 ]
               },
               refused: %{bands: [%{band: :tied, works: 1, correct: 1}]}
             } = Roots.candidates() |> Roots.validate()
    end
  end
end
