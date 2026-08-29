defmodule PramanaWeb.MCP.GetPersonTest do
  @moduledoc """
  The identity behind a byline, as a model sees it.

  `Pramana.AuthorityPersonTest` covers the domain function. What is tested here is the part
  a model actually consumes and can be misled by: that an unknown id is an error rather than
  an empty person, and that the response **names what is missing**. A person with no dates
  and a person whose dates were never looked up are the same shape in JSON, and only the
  note distinguishes them.
  """
  use Pramana.DataCase, async: true

  alias Anubis.Server.Response
  alias Pramana.Corpus.AuthorityPerson
  alias Pramana.Corpus.AuthorityRelation
  alias Pramana.Repo
  alias PramanaWeb.MCP.Tools.GetPerson

  defp insert!(attrs) do
    %AuthorityPerson{}
    |> Ecto.Changeset.change(Map.put_new(attrs, :source, "dila-authority"))
    |> Repo.insert!()
  end

  defp call(params) do
    {:reply, response, %{}} = GetPerson.execute(params, %{})
    response
  end

  defp json(params) do
    call(params)
    |> Map.fetch!(:content)
    |> hd()
    |> Map.fetch!("text")
    |> Jason.decode!()
  end

  test "an unknown id is an error, not an empty person" do
    response = call(%{authority_id: "A999999"})

    assert %Response{isError: true} = response
    assert response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text") =~ "unknown id"
  end

  test "returns the record, and stamps the bake and the replay" do
    insert!(%{
      id: "A000527",
      name: "求那跋陀羅",
      names: ["求那跋陀羅", "求那跋陁羅"],
      dynasty: "劉宋",
      birth_earliest: ~D[0394-01-01],
      birth_latest: ~D[0394-12-31],
      death_earliest: ~D[0468-01-01],
      death_latest: ~D[0468-12-31],
      sect: "禪宗",
      external_ids: %{"wikidata" => "Q1363621"}
    })

    payload = json(%{authority_id: "A000527"})

    assert payload["name"] == "求那跋陀羅"
    assert payload["also_known_as"] == ["求那跋陁羅"]
    assert payload["dynasty"] == "劉宋"
    assert payload["external_ids"] == %{"wikidata" => "Q1363621"}
    # Both ends, and the flag that says a range is not a point.
    assert payload["birth"]["earliest"] == "0394-01-01"
    assert payload["birth"]["latest"] == "0394-12-31"
    refute payload["birth"]["exact"]
    # Every response is replayable against a named corpus — see `PramanaWeb.MCP.Reply`.
    # The key, not its truthiness: there is no bake in the test environment, so the value is
    # nil and asserting on it would be asserting about the fixture rather than the contract.
    assert Map.has_key?(payload, "bake_id")
    assert payload["replay"]["tool"] == "get_person"
  end

  describe "the note says what is absent" do
    test "names every gap for a person the authority records almost nothing about" do
      insert!(%{id: "A1", name: "無名"})

      note = json(%{authority_id: "A1"})["note"]

      assert note =~ "no birth or death date is recorded"
      assert note =~ "no sect is recorded"
      assert note =~ "no external id"
      assert note =~ "no teacher or student is recorded"
    end

    test "names no gap when the record is complete" do
      insert!(%{
        id: "A2",
        name: "甲",
        birth_earliest: ~D[0700-01-01],
        birth_latest: ~D[0700-01-01],
        sect: "天台宗",
        external_ids: %{"wikidata" => "Q1"}
      })

      %AuthorityRelation{}
      |> Ecto.Changeset.change(%{
        person_id: "A2",
        related_id: "A3",
        related_name: "乙",
        type: "teacher",
        source: "dila-authority"
      })
      |> Repo.insert!()

      note = json(%{authority_id: "A2"})["note"]

      refute note =~ "For this person"
      # The standing caveat never goes away, because it is true of every link.
      assert note =~ "never `certain`"
    end
  end

  describe "teacher_chain_depth" do
    setup do
      insert!(%{id: "B1", name: "甲"})
      insert!(%{id: "B2", name: "乙"})

      for {from, to, name} <- [{"B1", "B2", "乙"}, {"B2", "B3", "丙"}] do
        %AuthorityRelation{}
        |> Ecto.Changeset.change(%{
          person_id: from,
          related_id: to,
          related_name: name,
          type: "teacher",
          source: "dila-authority"
        })
        |> Repo.insert!()
      end

      :ok
    end

    test "is not walked unless asked for" do
      refute Map.has_key?(json(%{authority_id: "B1"}), "teacher_chain")
      refute Map.has_key?(json(%{authority_id: "B1", teacher_chain_depth: 0}), "teacher_chain")
    end

    test "walks upward and reports why it stopped" do
      chain = json(%{authority_id: "B1", teacher_chain_depth: 5})["teacher_chain"]

      assert Enum.map(chain["chain"], & &1["id"]) == ["B2", "B3"]
      assert chain["stopped"] == "no_teacher_recorded"
      refute chain["branched"]
    end

    test "stops at the requested depth and says so" do
      chain = json(%{authority_id: "B1", teacher_chain_depth: 1})["teacher_chain"]

      assert length(chain["chain"]) == 1
      assert chain["stopped"] == "depth"
    end
  end
end
