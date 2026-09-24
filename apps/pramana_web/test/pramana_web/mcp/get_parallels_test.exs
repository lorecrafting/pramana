defmodule PramanaWeb.MCP.GetParallelsTest do
  @moduledoc """
  "What is the Pāli parallel to this Āgama passage?"

  The answer comes from hand-curated comparative scholarship, not embedding similarity,
  and the tests here are mostly about the two ways that answer could mislead: presenting
  a passing mention as a parallel, and presenting a text we do not hold as one we can
  quote.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Parallels
  alias PramanaWeb.MCP.Tools.GetParallels

  setup do
    Repo.insert!(%Pramana.Corpus.Source{
      id: "cbeta",
      name: "fixture",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Pramana.Corpus.Witness{id: "T", name: "Taishō"})
    Repo.insert!(%Pramana.Corpus.Work{id: "T0101", title: "fixture parallel"})

    Pramana.CorpusFixtures.text!(
      %{
        work_id: "T0101",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T0101",
        meta: %{}
      },
      [{"pramana:cbeta.T:T0101_001@p0496b22", "如是我聞一時佛住"}]
    )

    {:ok, _} =
      Parallels.store_anchors([
        %{
          uid: "sa1",
          work_id: "T0099",
          urn: "pramana:cbeta.T:T0099_001@p0001a06",
          acronym: "SA 1",
          volpage: "T ii 001a06"
        },
        %{
          uid: "sa-3.12",
          work_id: "T0101",
          urn: "pramana:cbeta.T:T0101_001@p0496b22",
          acronym: "SA-3 12",
          volpage: "T ii 496b22"
        }
      ])

    {:ok, _} =
      Parallels.store([
        %{source_uid: "sa1", target_uid: "sn22.51", relation: "full", partial: false},
        %{source_uid: "sa1", target_uid: "sa-3.12", relation: "resembling", partial: false},
        %{source_uid: "sa1", target_uid: "mn10", relation: "mentions", partial: false}
      ])

    :ok
  end

  defp call!(params),
    do:
      GetParallels.execute(params, %{})
      |> elem(1)
      |> Map.fetch!(:content)
      |> hd()
      |> Map.fetch!("text")
      |> Jason.decode!()

  describe "by SuttaCentral uid" do
    test "returns the parallels for a text" do
      data = call!(%{uid: "sa1"})
      assert data["total"] == 3
    end

    test "reports the anchor, so the reader knows which passage was asked about" do
      anchor = call!(%{uid: "sa1"})["anchor"]

      assert anchor["urn"] == "pramana:cbeta.T:T0099_001@p0001a06"
      assert anchor["volpage"] == "T ii 001a06"
    end

    test "groups by relation and puts a full parallel before a passing mention" do
      # Ordering is not cosmetic: a `mentions` at the top of the list reads as the
      # strongest available link.
      relations = call!(%{uid: "sa1"})["groups"] |> Enum.map(& &1["relation"])
      assert relations == ["full", "resembling", "mentions"]
    end

    test "never flattens relation strength into one list" do
      data = call!(%{uid: "sa1"})

      refute Map.has_key?(data, "parallels")
      assert Enum.all?(data["groups"], &Map.has_key?(&1, "relation"))
    end
  end

  describe "what can and cannot be quoted" do
    test "a parallel in this corpus carries a resolvable URN" do
      group = call!(%{uid: "sa1"})["groups"] |> Enum.find(&(&1["relation"] == "resembling"))
      parallel = hd(group["parallels"])

      assert parallel["urn"] == "pramana:cbeta.T:T0101_001@p0496b22"

      assert {:ok, span} = Pramana.Corpus.resolve(parallel["urn"])
      assert span.content == "如是我聞一時佛住"
      assert span.sha256 == Pramana.CorpusFixtures.sha256(span.content)
    end

    test "a Pāli parallel carries a null URN rather than a fabricated one" do
      # The relation is real scholarship about a text we do not hold. Inventing an
      # address for it would be the worst possible answer.
      group = call!(%{uid: "sa1"})["groups"] |> Enum.find(&(&1["relation"] == "full"))
      parallel = hd(group["parallels"])

      assert parallel["uid"] == "sn22.51"
      assert parallel["urn"] == nil
    end

    test "each group counts how many of its parallels are actually held" do
      groups = Map.new(call!(%{uid: "sa1"})["groups"], &{&1["relation"], &1})

      assert groups["full"]["in_corpus"] == 0
      assert groups["resembling"]["in_corpus"] == 1
    end

    test "the note says plainly that some parallels cannot be quoted from here" do
      note = call!(%{uid: "sa1"})["note"]

      assert note =~ "NOT in this corpus"
      assert note =~ "suttacentral.net"
    end

    test "and warns against treating a mention as a parallel" do
      assert call!(%{uid: "sa1"})["note"] =~ "Do not present them as equivalent"
    end
  end

  describe "by work id" do
    test "finds parallels through the resolved anchor" do
      assert call!(%{work_id: "T0099"})["total"] == 3
    end

    test "filters to a relation type when asked" do
      data = call!(%{work_id: "T0099", relations: "full"})

      assert data["total"] == 1
      assert [%{"relation" => "full"}] = data["groups"]
    end
  end

  describe "honest empties and errors" do
    test "a text with no recorded parallels says so rather than returning nothing" do
      data = call!(%{uid: "dn1"})

      assert data["total"] == 0
      assert data["note"] =~ "No parallels are recorded"
    end

    test "asking with neither argument is an error that says what to give" do
      {:reply, response, _} = GetParallels.execute(%{}, %{})

      assert response.isError
      text = response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text")
      assert text =~ "work_id or uid"
    end

    test "names its source, so the answer is attributable" do
      assert call!(%{uid: "sa1"})["source"] =~ "SuttaCentral"
    end
  end
end
