defmodule PramanaWeb.MCP.Tools.CompareTranslators do
  @moduledoc """
  Which Chinese word each translator chose for the same Sanskrit term.

  Two translators rendering one Indic original into Chinese make different lexical choices,
  and those choices are the most consequential thing about a translation. Whether *anattā*
  is 無我 — "there is no self" — or 非我 — "this is not self" — is one of the largest
  doctrinal disputes in the tradition, and it is a translator's decision.

  ## Attested, not inferred

  `Pramana.Translators.compare_hands/3` infers a translator's vocabulary from character
  n-gram rates across parallel works. That is deterministic and it is still a proxy:
  frequency stands in for choice.

  This is the choice itself. Seishi Karashima glossed **Dharmarakṣa's and Kumārajīva's
  Lotus Sūtra** term by term against the Sanskrit, so for a shared Sanskrit headword both
  Chinese renderings are recorded by a philologist rather than derived by this system. The
  same sūtra, two translators, a century and a half apart.

      adhimāna-prāpta   Kumārajīva 增上慢    Dharmarakṣa 貢高
      agra-bodhi        Kumārajīva 道心      Dharmarakṣa 佛道
      adhimukti         Kumārajīva 信力      Dharmarakṣa 信樂

  ## What an empty or thin result means

  601 Sanskrit headwords are shared between those two glossaries; 126 agree and 475 differ.
  A term absent from the comparison is one **at least one of the two did not gloss**, which
  is a fact about the glossaries and not about the translators — Karashima glossed what was
  interesting, not what was complete. An absence here is never evidence that a translator
  had no word for something.

  ## Agreement is the denominator

  The response returns both counts. A divergence figure quoted without the agreement it is
  measured against is a number with no denominator, and much of this vocabulary was settled
  before either translator was born.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Translators
  alias PramanaWeb.MCP.Reply

  @note "Attested by Seishi Karashima's glossaries, not inferred from frequency. A term " <>
          "missing from the comparison was not glossed by one of the two — a fact about " <>
          "the glossaries, never evidence that a translator had no word for it. " <>
          "Divergence is reported beside agreement because it means nothing alone."

  # The pairs this corpus can actually support. Named rather than free-text so a model
  # cannot ask for a comparison that would silently return nothing.
  @known %{
    "kumarajiva" => "Kumārajīva, 妙法蓮華經 (T0262)",
    "dharmaraksa" => "Dharmarakṣa, 正法華經 (T0263)",
    "lokaksema" => "Lokakṣema, 道行般若經 (T0224)"
  }

  schema do
    field(:a, :string,
      required: true,
      description: "First translator's glossary: kumarajiva, dharmaraksa or lokaksema."
    )

    field(:b, :string,
      required: true,
      description: "Second translator's glossary: kumarajiva, dharmaraksa or lokaksema."
    )

    field(:limit, :integer, description: "Maximum divergences to return (default 40).")
  end

  @impl true
  def execute(%{a: a, b: b} = params, frame) do
    cond do
      not Map.has_key?(@known, a) or not Map.has_key?(@known, b) ->
        {:reply, Reply.json("compare_translators", params, unknown(a, b)), frame}

      a == b ->
        {:reply, Reply.json("compare_translators", params, same(a)), frame}

      true ->
        {:reply, Reply.json("compare_translators", params, compare(params, a, b)), frame}
    end
  end

  defp compare(params, a, b) do
    result = Translators.attested(a, b, limit: params[:limit] || 40)

    %{
      translators: %{a: %{id: a, name: @known[a]}, b: %{id: b, name: @known[b]}},
      glossed_terms: %{a: result.terms_a, b: result.terms_b},
      shared_headwords: result.shared,
      agreed: result.agreed,
      diverged: result.diverged,
      divergences:
        Enum.map(result.examples, fn e ->
          %{sanskrit: e.sanskrit, a: e.a, b: e.b}
        end),
      source: "DILA Glossaries — Seishi Karashima, CC BY-NC-SA 4.0",
      note: @note
    }
  end

  # A refusal that lists what WOULD work. An error saying only "unknown" makes a model
  # guess again, and guessing at a corpus is how it invents one.
  defp unknown(a, b) do
    %{
      error: "unknown_translator",
      requested: [a, b],
      available: Enum.map(@known, fn {id, name} -> %{id: id, name: name} end),
      note:
        "Only translators with a term-by-term glossary can be compared this way. " <>
          "For translators without one, `Pramana.Translators.compare_hands/3` infers " <>
          "vocabulary from n-gram rates instead — a weaker claim, and not on this surface."
    }
  end

  defp same(a) do
    %{
      error: "same_translator",
      requested: a,
      note: "A translator does not diverge from himself; pass two different glossaries."
    }
  end
end
