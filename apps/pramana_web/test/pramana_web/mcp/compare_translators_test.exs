defmodule PramanaWeb.MCP.Tools.CompareTranslatorsTest do
  @moduledoc """
  The tool that makes `Pramana.Translators` reachable at all.

  It was not: no MCP tool, no mix task, no reader screen touched it, which is rule 60 —
  a capability a model cannot reach has not shipped. These tests are mostly about the two
  refusals, because a comparison tool that answers a question nobody can support is how a
  model comes to believe the corpus holds something it does not.
  """
  use Pramana.DataCase, async: true

  alias PramanaWeb.MCP.Tools.CompareTranslators

  defp call(params) do
    {:reply, reply, _frame} = CompareTranslators.execute(params, %{})
    reply
  end

  defp body(reply), do: reply.content |> hd() |> Map.fetch!("text") |> Jason.decode!()

  test "an unknown translator is refused, and the refusal lists what would work" do
    data = call(%{a: "xuanzang", b: "kumarajiva"}) |> body()
    assert data["error"] == "unknown_translator"
    assert data["requested"] == ["xuanzang", "kumarajiva"]

    assert Enum.sort(Enum.map(data["available"], & &1["id"])) ==
             ["dharmaraksa", "kumarajiva", "lokaksema"]
  end

  test "a translator compared with himself is refused rather than answered with zero" do
    data = call(%{a: "kumarajiva", b: "kumarajiva"}) |> body()
    assert data["error"] == "same_translator"
    assert data["requested"] == "kumarajiva"
    refute Map.has_key?(data, "shared_headwords")
  end

  test "a supported pair reports empty evidence honestly when no glossaries are loaded" do
    data = call(%{a: "kumarajiva", b: "dharmaraksa", limit: 5}) |> body()
    assert data["shared_headwords"] == 0
    assert data["agreed"] == 0
    assert data["diverged"] == 0
    assert data["divergences"] == []
    assert data["source"] =~ "Karashima"
    assert data["translators"]["a"]["id"] == "kumarajiva"
    assert data["translators"]["b"]["id"] == "dharmaraksa"
  end
end
