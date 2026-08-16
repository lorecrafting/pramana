defmodule Pramana.CompareTest do
  @moduledoc """
  Setting a passage beside its other versions.

  The distinction under test is the one a merged list would destroy: a **rendering** is
  someone's English for the text in front of you; a **parallel** is a different text that
  scholarship judges to transmit the same discourse. Neither the Pāli sutta nor the
  Chinese Āgama is a translation of the other — both descend from something earlier — and
  a caller shown one list cannot tell which relationship it is looking at.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Compare
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Parallels
  alias Pramana.Repo
  alias Pramana.Translations

  @chinese "pramana:cbeta.T:T0099_001@p0001a06"
  @pali "pramana:sc.ms:sn22.12@1.2"

  defp seed_text!(source_id, witness_id, work_id, urn, content) do
    Repo.insert!(%Work{id: work_id, title: work_id})

    text =
      Repo.insert!(%Text{
        work_id: work_id,
        source_id: source_id,
        witness_id: witness_id,
        urn_prefix: "pramana:#{source_id}.#{witness_id}:#{work_id}",
        body: content,
        body_sha256: "x",
        meta: %{}
      })

    Repo.insert!(%Segment{
      text_id: text.id,
      urn: urn,
      ordinal: 0,
      content: content,
      content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
      char_start: 0,
      char_end: String.length(content),
      byte_start: 0,
      byte_end: byte_size(content),
      meta: %{}
    })

    text
  end

  setup do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Source{
      id: "sc",
      name: "SuttaCentral",
      license_spdx: "CC-PDM-1.0",
      license_class: "public-domain",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Witness{id: "T", name: "Taishō"})
    Repo.insert!(%Witness{id: "ms", name: "Mahāsaṅgīti"})

    seed_text!("cbeta", "T", "T0099", @chinese, "如是我聞一時佛住舍衛國")
    seed_text!("sc", "ms", "sn22.12", @pali, "Rūpaṁ, bhikkhave, aniccaṁ")

    # A second Chinese text we DO hold, linked at a weaker strength. Without it the only
    # resolvable parallel is the `full` one and the test cannot tell whether strength is
    # preserved or merely defaulted.
    seed_text!("cbeta", "T", "ea9.7", "pramana:cbeta.T:ea9.7_001@p0001a01", "增一阿含經文")

    {:ok, _} =
      Parallels.store_anchors([
        %{uid: "sa1", work_id: "T0099", urn: @chinese, acronym: "SA 1", volpage: "T ii 001a06"}
      ])

    {:ok, _} =
      Parallels.store([
        %{source_uid: "sa1", target_uid: "sn22.12", relation: "full", partial: false},
        %{source_uid: "sa1", target_uid: "ea9.7", relation: "mentions", partial: false},
        %{source_uid: "sa1", target_uid: "mn10", relation: "mentions", partial: false}
      ])

    {:ok, _} =
      Translations.store([
        %{
          anchor_urn: @pali,
          work_id: "sn22.12",
          lang: "en",
          translator_id: "sujato",
          tier: "t0",
          method: "human",
          text: "Form, mendicants, is impermanent.",
          redistributable: true,
          license_class: "cc0"
        }
      ])

    :ok
  end

  describe "renderings" do
    test "are the translations OF this passage" do
      {:ok, result} = Compare.versions(@pali)

      assert result.renderings.count == 1
      assert hd(result.renderings.pool).translator_id == "sujato"
    end

    test "are nil rather than an empty shell when there are none" do
      {:ok, result} = Compare.versions(@chinese)
      assert result.renderings == nil
    end
  end

  describe "parallels" do
    test "are resolved to actual passages, not left as identifiers" do
      {:ok, result} = Compare.versions(@chinese)

      pali = Enum.find(result.parallels.versions, &(&1.work_id == "sn22.12"))
      assert pali.passage.content =~ "Rūpaṁ"
    end

    test "keep their relation strength rather than being flattened to related" do
      {:ok, result} = Compare.versions(@chinese, relations: ["full", "mentions"])

      relations = result.parallels.versions |> Enum.map(& &1.relation) |> Enum.sort()
      assert "full" in relations
      # A passing mention is present and still labelled a mention.
      assert "mentions" in relations
    end

    test "default to full and resembling, excluding passing mentions" do
      {:ok, result} = Compare.versions(@chinese)

      refute Enum.any?(result.parallels.versions, &(&1.relation == "mentions"))
    end

    test "count what is referenced but not held, rather than staying silent about it" do
      {:ok, result} = Compare.versions(@chinese, relations: ["full", "mentions"])

      # mn10 is linked by the scholarship and absent from this corpus. Reporting only
      # what we hold would present a partial comparison as a complete one.
      assert result.parallels.referenced_but_not_held == 1
      assert result.parallels.quotable == 2
    end

    test "include_text: false returns identifiers without resolving them" do
      {:ok, result} = Compare.versions(@chinese, include_text: false)

      refute Map.has_key?(hd(result.parallels.versions), :passage)
    end
  end

  describe "the response as a whole" do
    test "carries the source passage itself" do
      {:ok, result} = Compare.versions(@chinese)
      assert result.passage.content =~ "如是我聞"
    end

    test "states that parallels are different texts, not editions of one another" do
      {:ok, result} = Compare.versions(@chinese)
      assert result.note =~ "DIFFERENT texts"
    end

    test "a URN addressing nothing is not found, not an empty comparison" do
      assert {:error, :not_found} = Compare.versions("pramana:cbeta.T:T9999_001@p0001a01")
    end

    test "a malformed URN is rejected" do
      # The URN parser's own reason travels out unchanged rather than being flattened
      # to a generic error; the MCP tool is what turns it into a message.
      assert {:error, :bad_scheme} = Compare.versions("not-a-urn")
    end
  end
end
