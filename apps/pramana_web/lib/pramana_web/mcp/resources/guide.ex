defmodule PramanaWeb.MCP.Resources.Guide do
  @moduledoc """
  How to query this corpus, exposed as an MCP resource.

  Tools describe *what* they take; nothing was telling a model *how this corpus works* —
  that provenance filters exist and why they matter, that an ngram hit is weaker than a
  phrase hit, that a range URN is citable. Without that, a model uses the default path
  and the provenance modelling that distinguishes this project goes unused.
  """

  # `uri:` and `name:` belong in the options, not in hand-written callbacks: the macro
  # generates `name/0` from them and does not mark it overridable, so defining it below
  # would be silently shadowed by the option default (nil).
  use Anubis.Server.Component,
    type: :resource,
    uri: "pramana://guide",
    name: "Querying the Pramāṇa corpus",
    mime_type: "text/markdown"

  alias Anubis.Server.Response

  @impl true
  def description,
    do: "How citations, provenance axes and the retrieval tools work. Read this first."

  @impl true
  def read(_params, frame) do
    {:reply, Response.text(Response.resource(), guide()), frame}
  end

  defp guide do
    """
    # Querying the Pramāṇa corpus

    ## Citations are URNs, and they are checkable

        pramana:cbeta.T:T0262_001@p0001c19              one printed line
        pramana:cbeta.T:T0262_001@p0001c18-p0001c21     a range, equally citable

    The locator is the tradition's own citation grammar — for the Taishō, page,
    register and line — so a reader can check any citation against the printed volume.
    Never invent a URN. If you did not receive it from a tool, it does not exist.

    **Every quotation you make will be re-resolved and byte-compared.** Use
    `verify_citation` before asserting anything you are unsure of. A fabricated or
    altered quotation is caught, always.

    ## Provenance is several axes, not one label

    | axis | values |
    |---|---|
    | `composition_origin` | indic, chinese, japanese, tibetan, korean — where it was **composed** |
    | `text_role` | root, treatise, commentary, subcommentary, apocryphon, catalogue, history |
    | `division` | the Taishō 部: 阿含部, 般若部, 經疏部, 疑似部 … |

    This matters more than it looks. A text can be written in Classical Chinese and be
    an Indian sūtra in translation (`indic` + `root`), a Chinese exegete's commentary on
    one (`chinese` + `commentary`), or a Chinese composition **presenting itself as** an
    Indian sūtra (`chinese` + `apocryphon`).

    Use the filters. `search(query, origin: "indic", role: "root")` is scripture;
    `role: "apocryphon"` is the 57 works the canon itself marks as doubtful. Presenting
    an apocryphon as the Buddha's words is the mistake this corpus exists to prevent.

    Some works are deliberately **unattributed** — 古逸部 material recovered at Dunhuang
    records where a text was *found*, not where it was composed. Null is a considered
    answer, not missing data.

    ## Choosing a tool

    - **`search`** — hybrid by default: lexical (exact characters) fused with semantic
      (meaning) by rank. Use it first.
    - **`survey_corpus`** — exhaustive counts, not a ranked sample. Ask this before
      claiming anything about how often or where the canon says something. Five results
      do not support a claim about a canon of 4.7 million segments.
    - **`get_passage`** — a URN, optionally with `context_before`/`context_after`.
      **Taishō lines break mid-sentence**, so a single line often reads as a fragment;
      ask for 2–3 lines of context when quoting.
    - **`get_outline`** — a work's structure without its text. The canon is far too
      large to read; survey structure, then fetch what you need.
    - **`verify_citation`** — byte-compare a quotation against its URN.

    ## Reading the response

    - `retrievers` — which retrievers contributed. `["lexical"]` alone means semantic
      search was unavailable, so meaning-based matches were not considered.
    - `embedding_coverage` — how much of the corpus is vector-searchable. Partial
      coverage is not a small canon.
    - `mode` — `phrase` is strong evidence; `ngram` is a character-window fallback and
      weaker; weigh accordingly.
    - `addressing` — `canonical` can be checked against a printed edition; `derived`
      cannot, because that source has no printed page and line.
    - `bake_id` — which corpus snapshot produced this. Cite it for reproducibility.
    - `reader` — a link into the published edition, for a human who wants to check the
      passage. It opens the **fascicle, not the line**, and `verified: false` is
      literal: these readers are single-page apps that return HTTP 200 for any path,
      so the link cannot be checked by fetching it. `reader.linehead` is CBETA's own
      citation string (`T09n0262_p0001a05`) and pastes into the reader's Goto box.
      **Cite the URN, never the URL.**

    ## Things that are true and easy to get wrong

    - Classical Chinese has no spaces. Do not split queries on whitespace.
    - **A query in the wrong orthographic tradition returns NOTHING, silently.** This
      corpus is CBETA, which writes 眾生 and 說法. Searching the simplified 众生 or the
      Japanese 説法 finds **zero** results — not few, zero. If a query you expect to
      match finds nothing, retry with `normalize_variants: true`, which expands the
      query across variant Han forms and reports which characters it expanded. The
      stored text is never normalised; only the query is.
    - A machine translation is never citable as source; cite the source anchor.
    - `has_variants: true` means the passage carries variant readings from other
      witnesses (Song, Yuan, Ming, Koryŏ) — worth mentioning when the wording is the
      point of the question.
    """
  end
end
