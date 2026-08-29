defmodule PramanaWeb.MCP.Tools.GetGlosses do
  @moduledoc """
  Which commentaries explain **this line**, found by lemma match.

  `get_commentaries` answers which work explains a work. That is the easy half.
  `docs/COMMENTARY.md` calls this one "the single highest-value piece of the feature":
  land on a dense canonical line and be handed the layers of explanation attached to *that
  line*, each labelled with when and where it was written.

  ## Deterministic, and the method says so

  A Chinese commentary quotes a phrase of its root and then glosses it, so the alignment is
  already written in the text. A lemma anchors where its 8-character window occurs **exactly
  once** in the root — a property of the root, measured, not a similarity score. `method` is
  `lemma_match` and `confidence` is `probable`: the lemma is certain, and that this
  commentary is glossing *this* occurrence rather than quoting the phrase in passing is an
  inference.

  ## Nothing here is quotable as the root text

  Each result names the commentary passage's own URN, which is where its text lives. To
  read it you fetch it like any other passage, under the same guard and the same
  provenance. `CLAUDE.md`'s rule holds unchanged: pulling a commentary in because it
  explains a sūtra must never let it be quoted *as* the sūtra.

  ## Absence here is thin evidence, and the response says which kind

  Only 43 of 89 asserted `comments_on` pairs clear the alignment's density floor. A pair
  below it is **not a refuted relation** — a commentary may paraphrase its root, and 47 of
  them do — so an empty result means "no commentary quotes this line verbatim", never "no
  commentary explains it". The note says so, because a caller cannot tell those apart from
  an empty list.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Commentary
  alias PramanaWeb.MCP.Reply

  @note "Found by verbatim lemma match. An empty result means no commentary QUOTES this " <>
          "line, not that none explains it — a commentary that paraphrases is invisible " <>
          "to this method, and 47 of 89 asserted pairs are that. Nothing here is citable " <>
          "as the root text."

  schema do
    field(:urn, :string,
      required: true,
      description: "A root passage URN, e.g. pramana:cbeta.T:T0235_001@p0748c17."
    )

    field(:limit, :integer, description: "Maximum glosses to return (default 20).")
  end

  @impl true
  def execute(%{urn: urn} = params, frame) do
    glosses = Commentary.glosses_on(urn, limit: params[:limit] || 20)

    payload = %{
      root_urn: urn,
      glosses: Enum.map(glosses, &present/1),
      commentaries: glosses |> Enum.map(& &1.commentary_work_id) |> Enum.uniq(),
      method: "lemma_match",
      note: @note,
      bake_id: Pramana.Bake.current_id()
    }

    {:reply, Reply.json("get_glosses", params, payload), frame}
  end

  defp present(g) do
    %{
      # The commentary's OWN address, first. A caller reading this needs to know where the
      # explanation lives before it needs the words that matched.
      commentary_urn: g.commentary_urn,
      commentary_work_id: g.commentary_work_id,
      title: g.commentary_title,
      attributed_author: g.commentary_author,
      composition_origin: g.composition_origin,
      lemma: g.lemma,
      length: g.length,
      method: g.method,
      confidence: g.confidence
    }
  end
end
