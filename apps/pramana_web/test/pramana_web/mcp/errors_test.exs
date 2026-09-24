defmodule PramanaWeb.MCP.ErrorsTest do
  @moduledoc """
  An error a model can branch on.

  Nineteen error paths across seventeen tools were each a hand-written sentence. Prose is the
  right thing to show a caller and the wrong thing to hand it as a contract: distinguishing
  "this URN is malformed" from "this URN addresses nothing" required matching on English,
  which changes whenever someone improves the wording.

  What is pinned here is the *shape*, not the sentences — the sentences are free to improve.
  """
  use Pramana.DataCase, async: true

  alias Anubis.Server.Response
  alias Pramana.Release
  alias PramanaWeb.MCP.Tools.GetPassage
  alias PramanaWeb.MCP.Tools.GetPerson
  alias PramanaWeb.MCP.Tools.Search

  defp call(module, params) do
    {:reply, %Response{} = response, %{}} = module.execute(params, %{})
    body = response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text")

    {response, Jason.decode!(body)}
  end

  test "a malformed URN and a missing one are different reasons, not different sentences" do
    {_, bad} = call(GetPassage, %{urn: "not-a-urn"})
    {_, missing} = call(GetPassage, %{urn: "pramana:cbeta.T:T9999_001@p0001a01"})

    assert bad["error"]["reason"] == "bad_urn"
    assert missing["error"]["reason"] == "not_found"

    # The caller's mistake and a fact about this bake are two different next steps.
    refute bad["error"]["reason"] == missing["error"]["reason"]
  end

  test "an error is still an MCP error, not a success carrying an error field" do
    {response, _} = call(GetPassage, %{urn: "not-a-urn"})

    assert response.isError
  end

  test "the sentence a person reads survives beside the reason" do
    {_, body} = call(GetPassage, %{urn: "not-a-urn"})

    assert body["error"]["message"] =~ "Malformed URN"
    assert body["error"]["message"] =~ "Expected pramana:"
  end

  test "a failure names the corpus it is a fact about" do
    # Failures carry source identity, the recorded release and replay just as results do.
    {:ok, stamped} = Release.stamp()
    {_, body} = call(GetPassage, %{urn: "pramana:cbeta.T:T9999_001@p0001a01"})

    assert Map.has_key?(body, "bake_id")
    assert body["release_id"] == stamped.release_id
    assert body["replay"]["tool"] == "get_passage"
    assert body["replay"]["arguments"]["urn"] == "pramana:cbeta.T:T9999_001@p0001a01"
  end

  test "the same parse works for a failure as for a result" do
    # The point of putting JSON in the error body: a caller does not need two code paths.
    {_, body} = call(Search, %{query: ""})

    assert body["error"]["reason"] == "empty_query"
    assert is_map(body["replay"])
  end

  test "an unknown authority id is its own reason" do
    {_, body} = call(GetPerson, %{authority_id: "A_NOPE"})

    assert body["error"]["reason"] == "unknown_authority_id"
  end

  test "tool error paths preserve null release identity until explicitly stamped" do
    for {module, params} <- [
          {GetPassage, %{urn: "not-a-urn"}},
          {Search, %{query: ""}},
          {GetPerson, %{authority_id: "A_NOPE"}}
        ] do
      {response, body} = call(module, params)
      assert response.isError
      assert Map.fetch!(body, "release_id") == nil
    end

    assert Release.current() == nil
  end

  test "tool error paths use the recorded release without changing their error semantics" do
    {:ok, stamped} = Release.stamp()

    for {module, params, reason} <- [
          {GetPassage, %{urn: "not-a-urn"}, "bad_urn"},
          {Search, %{query: ""}, "empty_query"},
          {GetPerson, %{authority_id: "A_NOPE"}, "unknown_authority_id"}
        ] do
      {response, body} = call(module, params)
      assert response.isError
      assert body["release_id"] == stamped.release_id
      assert body["error"]["reason"] == reason
    end

    assert Release.current() == stamped
    assert Pramana.Repo.aggregate(Pramana.Corpus.Release, :count) == 1
  end
end
