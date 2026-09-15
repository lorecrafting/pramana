defmodule PramanaWeb.MCP.Tools.CompareTranslatorsTest do
  @moduledoc """
  The tool that makes `Pramana.Translators` reachable at all.

  It was not: no MCP tool, no mix task, no reader screen touched it, which is rule 60 —
  a capability a model cannot reach has not shipped. These tests are mostly about the two
  refusals, because a comparison tool that answers a question nobody can support is how a
  model comes to believe the corpus holds something it does not.
  """
  use PramanaWeb.ConnCase, async: false

  alias PramanaWeb.MCP.Tools.CompareTranslators

  defp call(params) do
    {:reply, reply, _frame} = CompareTranslators.execute(params, %{})
    reply
  end

  # The reply is an Anubis response struct wrapping JSON text; the assertions only need
  # the serialised body, so this flattens it to a string rather than modelling the wrapper.
  defp body(reply), do: inspect(reply, limit: :infinity, printable_limit: :infinity)

  test "an unknown translator is refused, and the refusal lists what would work" do
    text = call(%{a: "xuanzang", b: "kumarajiva"}) |> body()

    assert text =~ "unknown_translator"
    # A refusal saying only "unknown" makes a model guess again, and guessing at a corpus
    # is how it invents one.
    assert text =~ "kumarajiva"
    assert text =~ "dharmaraksa"
  end

  test "a translator compared with himself is refused rather than answered with zero" do
    text = call(%{a: "kumarajiva", b: "kumarajiva"}) |> body()

    assert text =~ "same_translator"
  end

  test "a real pair returns divergences beside the agreement they are measured against" do
    text = call(%{a: "kumarajiva", b: "dharmaraksa", limit: 5}) |> body()

    assert text =~ "shared_headwords"
    assert text =~ "agreed"
    assert text =~ "diverged"
    # Attested, and the response says so rather than leaving a caller to assume the
    # comparison was computed here.
    assert text =~ "Karashima"
  end
end
