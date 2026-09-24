defmodule PramanaWeb.MCP.ReplyTest do
  @moduledoc """
  Success and error responses carry the same recorded provenance and caller arguments.
  These records do not freeze the corpus or guarantee identical replay results.
  """
  # Both reply paths query recorded identities and need an isolated sandbox connection.
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Bake, as: BakeSchema
  alias Pramana.Release
  alias PramanaWeb.MCP.Reply

  defp decode(response), do: response.content |> hd() |> Map.fetch!("text") |> Jason.decode!()

  defp bake!(digit, built_at) do
    Pramana.Repo.insert!(%BakeSchema{
      id: String.duplicate(digit, 64),
      pipeline_version: Pramana.Bake.pipeline_version(),
      sources_lock_sha256: String.duplicate("c", 64),
      built_at: built_at
    })
  end

  defp replies do
    [
      Reply.json("search", %{query: ""}, %{results: []}),
      Reply.error("search", %{query: ""}, :empty_query, "The query is empty.")
    ]
  end

  describe "json/3" do
    test "records the tool and the arguments the caller actually sent" do
      data = decode(Reply.json("search", %{query: "云何", mode: "phrase"}, %{results: []}))

      assert data["replay"] == %{
               "tool" => "search",
               "arguments" => %{"query" => "云何", "mode" => "phrase"}
             }
    end

    # The key is present even when the test database has no recorded bake.
    test "attaches the recorded source identity" do
      data = decode(Reply.json("search", %{query: "x"}, %{results: []}))
      assert Map.has_key?(data, "bake_id")
    end

    test "keeps the payload the tool built" do
      data = decode(Reply.json("survey_corpus", %{query: "x"}, %{total: 7, note: "counted"}))

      assert data["total"] == 7
      assert data["note"] == "counted"
    end

    # A replay that re-sends a default pins a value that is free to change, so the record
    # would stop describing the call it claims to reproduce.
    test "drops options the caller did not set" do
      data = decode(Reply.json("search", %{query: "x", limit: nil, origin: nil}, %{}))

      assert data["replay"]["arguments"] == %{"query" => "x"}
    end

    test "normalises atom keys, so the record round-trips as what was sent" do
      data = decode(Reply.json("get_passage", %{urn: "pramana:sc.ms:mn1@1.1"}, %{}))

      assert data["replay"]["arguments"] == %{"urn" => "pramana:sc.ms:mn1@1.1"}
    end

    test "overwrites payload provenance with the recorded identities and actual call" do
      {:ok, stamped} = Release.stamp()

      data =
        decode(
          Reply.json("search", %{query: "x"}, %{
            results: [],
            bake_id: "not-the-bake",
            release_id: "not-the-release",
            replay: %{tool: "not-the-tool"}
          })
        )

      assert data["bake_id"] == nil
      assert data["release_id"] == stamped.release_id
      assert data["replay"] == %{"tool" => "search", "arguments" => %{"query" => "x"}}
      assert data["results"] == []
    end
  end

  describe "error/4" do
    test "preserves the MCP error flag, reason, message and normalized replay" do
      response =
        Reply.error(
          "search",
          %{:query => "", "limit" => nil, :origin => nil},
          :empty_query,
          "The query is empty."
        )

      assert response.isError
      data = decode(response)

      assert data["error"] == %{
               "reason" => "empty_query",
               "message" => "The query is empty."
             }

      assert data["replay"] == %{"tool" => "search", "arguments" => %{"query" => ""}}
    end
  end

  describe "shared provenance" do
    test "both paths include explicit null identities when nothing is recorded" do
      for response <- replies() do
        data = decode(response)
        assert Map.fetch!(data, "bake_id") == nil
        assert Map.fetch!(data, "release_id") == nil
      end

      assert Pramana.Repo.aggregate(BakeSchema, :count) == 0
      assert Pramana.Repo.aggregate(Pramana.Corpus.Release, :count) == 0
    end

    test "a recorded bake does not cause either path to invent a release stamp" do
      bake = bake!("a", ~U[2026-01-01 00:00:00.000000Z])

      for response <- replies() do
        data = decode(response)
        assert data["bake_id"] == bake.id
        assert Map.fetch!(data, "release_id") == nil
      end

      assert Pramana.Repo.aggregate(Pramana.Corpus.Release, :count) == 0
    end

    test "both paths carry the exact recorded release and the same replay" do
      bake = bake!("a", ~U[2026-01-01 00:00:00.000000Z])
      {:ok, stamped} = Release.stamp()
      [success, error] = replies()
      refute success.isError
      assert error.isError

      for response <- [success, error] do
        data = decode(response)
        assert data["bake_id"] == bake.id
        assert data["release_id"] == stamped.release_id
        assert data["replay"] == %{"tool" => "search", "arguments" => %{"query" => ""}}
      end

      assert Pramana.Repo.aggregate(Pramana.Corpus.Release, :count) == 1
    end

    test "source drift does not silently refresh or recompute response release IDs" do
      before = bake!("a", ~U[2026-01-01 00:00:00.000000Z])
      {:ok, stamped} = Release.stamp()
      after_bake = bake!("b", ~U[2026-01-02 00:00:00.000000Z])
      refute Release.ids().release_id == stamped.release_id

      for response <- replies() do
        data = decode(response)
        assert data["bake_id"] == after_bake.id
        assert data["release_id"] == stamped.release_id
      end

      assert Release.current() == stamped
      assert Pramana.Repo.aggregate(Pramana.Corpus.Release, :count) == 1

      assert Release.drift() == %{
               source_bake_id: %{stamped: before.id, live: after_bake.id}
             }
    end
  end

  test "both reply paths attach the selected A stamp after A to B to A" do
    a_bake = bake!("a", ~U[2026-01-01 00:00:00.000000Z])
    {:ok, a} = Release.stamp()
    b_bake = bake!("b", ~U[2026-01-02 00:00:00.000000Z])
    {:ok, b} = Release.stamp()
    refute a.release_id == b.release_id
    Pramana.Repo.delete!(b_bake)
    {:ok, ^a} = Release.stamp()

    for reply <- replies() do
      data = decode(reply)
      assert data["release_id"] == a.release_id
      assert data["bake_id"] == a_bake.id
    end
  end
end
