defmodule PramanaWeb.MCP.ReplyTest do
  @moduledoc """
  A URN is a reproducible citation of a passage. `replay` is the same thing one layer up,
  for a retrieval: `{tool, arguments, bake_id}` is enough to run the query again and get the
  same answer.

  It is the smallest useful form of what `docs/IDEAS.md` stars as "show your work" mode, and
  it is stateless on purpose — a per-session trace would be a write path from the model's
  side of the boundary, which invariant #7 does not allow however benign.
  """
  # DataCase, not a plain case: `Reply.json/3` reads `Bake.current_id/0`, which queries.
  # That is deliberate — a replay record without the corpus it ran against reproduces
  # nothing — and it means this needs a sandbox connection.
  use Pramana.DataCase, async: true

  alias PramanaWeb.MCP.Reply

  defp decode(response), do: response.content |> hd() |> Map.fetch!("text") |> Jason.decode!()

  describe "json/3" do
    test "records the tool and the arguments the caller actually sent" do
      data = decode(Reply.json("search", %{query: "云何", mode: "phrase"}, %{results: []}))

      assert data["replay"] == %{
               "tool" => "search",
               "arguments" => %{"query" => "云何", "mode" => "phrase"}
             }
    end

    # The KEY is always present; the value is nil on a corpus with no bake recorded, which
    # is what an empty test database is. Asserting a string here would be asserting that a
    # bake exists, which is a different claim.
    test "attaches the bake, because a retrieval is only reproducible against one corpus" do
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
  end
end
