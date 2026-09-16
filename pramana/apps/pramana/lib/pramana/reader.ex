defmodule Pramana.Reader do
  @moduledoc """
  Deep links from a URN into the published edition a human can check it against.

  A citation is only as good as a reader's ability to go and look. The URN makes that
  *possible* — page, register and line are the printed edition's own coordinates — but a
  link makes it happen, and the difference between "verifiable in principle" and "one
  click away" is most of the value.

  ## These links are conveniences, and are labelled as such

  **The URN is the citation. The URL is not.** The corpus is reproducible from
  `sources.lock.json`; a third-party website is not, and it can move, rename or vanish
  without our noticing. So a reference here carries `verified: false` and never replaces
  the URN in any response.

  That field is not hedging, and it is not uniform either — the three publishers differ
  in whether a link *could* be checked at all:

  | publisher | checkable by fetching? |
  |---|---|
  | CBETA Online | **No.** A single-page app; HTTP 200 with a byte-identical body for a real path and for nonsense. |
  | SuttaCentral | **No**, same reason — but its JSON API resolves every uid, which is what the format below was measured against. |
  | 84000 | **Yes.** Server-rendered: a real Toh number returns the work's title, `toh9999` returns a page titled "Toh 9999". |

  So for two of the three a link checker would be theatre. `verified: false` everywhere is
  the honest floor rather than a per-publisher claim nobody will keep current.

  ## Only formats measured against real identifiers are shipped

  - **CBETA Online**, `/{lang}/{work}_{juan}`. The path segment is the URN's own work
    component. Line anchors come from the `id` CBETA puts on each line in the HTML its
    site renders — see `linehead/1`.
  - **SuttaCentral**, `/{uid}`. Measured on 40 work ids drawn at random from the corpus:
    **all 40 resolve**, 37 to their own page and 3 — `dhp298`, `an1.70`, `sn45.142` — to
    the range page that contains them, because SuttaCentral groups short texts
    (`dhp290-305`). Landing on the containing range is the same bargain as CBETA's
    fascicle: the cited text is on the page.
  - **84000**, `/translation/{toh}.html`. Measured on 30 Toh numbers drawn at random from
    the Degé Kangyur and Tengyur: **29 of 30** return the work's own title, translated or
    not, because 84000 publishes the whole Degé catalogue and not only what it has
    translated.

  SAT's format is **not** confirmed, so there is no SAT template here — it arrives with
  the SAT source itself in Phase 2 (task #14), where it can be checked against real
  ingested identifiers rather than guessed at. Returning `nil` for a source we have no
  confirmed template for is deliberate: a link that looks plausible and lands on the wrong
  passage is worse than no link, because nothing about it appears wrong.

  ## `anchor` is whatever that edition calls a coordinate

  One field, three grammars — CBETA's linehead `T09n0262_p0001a05`, SuttaCentral's segment
  id `sn6.4:1.2`, and nothing at all for 84000, whose reading room marks folios in text
  rather than in addressable ids. `anchor_label` names which it is, because a bare string
  in three different notations is exactly the sigil problem `Pramana.Apparatus` exists to
  prevent one level down.
  """

  alias Pramana.Cbeta.Collections

  @cbeta_base "https://cbetaonline.dila.edu.tw"
  @suttacentral_base "https://suttacentral.net"
  @eightyfourthousand_base "https://read.84000.co/translation"

  @not_the_citation "The URN is the citation; this link is a convenience and is not verified."

  @type link :: %{
          edition: String.t(),
          url: String.t(),
          granularity: String.t(),
          anchor: String.t() | nil,
          anchor_label: String.t() | nil,
          verified: boolean(),
          note: String.t()
        }

  @doc """
  A reader reference for a resolved passage, or `nil` when none is confirmed.

  Takes the URN string and the provenance map that `Pramana.Corpus.provenance/1`
  already builds, since that carries the source, witness, volume and page/register/line
  this needs.

  ## Options

    * `:lang` — `"en"` (default) or `"zh"`, the reader's own UI language prefix.
      CBETA Online only; SuttaCentral and 84000 have no language in their path.
  """
  @spec reference(String.t(), map(), keyword()) :: link() | nil
  def reference(urn_string, provenance, opts \\ [])

  def reference(urn_string, %{source: "cbeta"} = provenance, opts) when is_binary(urn_string) do
    with_urn(urn_string, fn urn ->
      lang = if opts[:lang] == "zh", do: "zh", else: "en"

      %{
        edition: "CBETA Online",
        # `urn.work` is already the reader's own path segment (`T0262_001` — text number
        # and juan). Taking it verbatim rather than reassembling it from parts means
        # there is no second place for the two to disagree.
        url: "#{@cbeta_base}/#{lang}/#{urn.work}",
        granularity: "juan",
        anchor: linehead(provenance),
        anchor_label: "CBETA linehead",
        verified: false,
        note:
          "Opens the fascicle, not the line — the reader has no line-addressable URL. " <>
            "Paste the linehead into its Goto box to jump to the exact line. " <>
            @not_the_citation
      }
    end)
  end

  # `sc` is the Pāli root text and `sc-translations` its renderings; both cite the same
  # SuttaCentral uid, which is our work id verbatim. `sc-data` holds SuttaCentral's
  # structural metadata rather than text, so it has no page to open.
  def reference(urn_string, %{source: source} = provenance, _opts)
      when is_binary(urn_string) and source in ["sc", "sc-translations"] do
    with_urn(urn_string, fn urn ->
      %{
        edition: "SuttaCentral",
        url: "#{@suttacentral_base}/#{urn.work}",
        granularity: "sutta",
        anchor: segment_id(urn, provenance),
        anchor_label: "SuttaCentral segment ID",
        verified: false,
        note:
          "Opens the sutta — or, for a short text SuttaCentral groups into a range, the " <>
            "range that contains it. " <> @not_the_citation
      }
    end)
  end

  # 84000 publishes the Degé catalogue whole, so a Toh number resolves whether or not a
  # translation exists — which is the case that matters here, since the corpus holds the
  # Tibetan of far more works than 84000 has translated.
  def reference(urn_string, %{source: source}, _opts)
      when is_binary(urn_string) and source in ["derge", "derge-tengyur"] do
    with_urn(urn_string, fn urn ->
      %{
        edition: "84000",
        url: "#{@eightyfourthousand_base}/#{urn.work}.html",
        granularity: "work",
        # 84000's reading room prints folio references in the text rather than putting
        # them in addressable ids, so there is nothing to paste. The URN's own locator —
        # volume.folio.line — is what a reader carries to the Degé.
        anchor: nil,
        anchor_label: nil,
        verified: false,
        note:
          "Opens the work's 84000 page — the published translation where one exists, the " <>
            "catalogue entry where it does not. " <> @not_the_citation
      }
    end)
  end

  def reference(_urn_string, _provenance, _opts), do: nil

  defp with_urn(urn_string, build) do
    case Pramana.URN.parse(urn_string) do
      {:ok, %Pramana.URN{work: work} = urn} when is_binary(work) and work != "" -> build.(urn)
      _ -> nil
    end
  end

  # SuttaCentral writes a segment as `<uid>:<segment>` — `sn6.4:1.2` — which is the key
  # its own API returns and what its interface displays beside a line. Our locator is that
  # segment number verbatim, so the id only has to be reassembled, never invented.
  defp segment_id(%Pramana.URN{work: work, locator: locator}, _provenance)
       when is_binary(locator) and locator != "",
       do: "#{work}:#{locator}"

  defp segment_id(_urn, _provenance), do: nil

  @doc """
  CBETA's own citation string for a line, e.g. `T09n0262_p0037a13`.

  Worth returning even where no URL can address it: this is the identifier CBETA's
  reader, its search box and the printed apparatus all use, so it is what a person
  pastes or types when checking us. Returns `nil` rather than a partial string when any
  component is missing — half a citation is not a citation.

  ## This was Taishō-shaped, and nine collections later that was a defect

  It padded the volume to two digits unconditionally, which is right for T, X and J and
  wrong for A, P, L and U: `A1057` sits in volume `A091`, and `A91n1057_p0311b01` is a
  string CBETA's reader cannot find. The width now comes from
  `Pramana.Cbeta.Collections.volume_token/2`, checked against CBETA's own rendered lines.

  The second half of the same defect was upstream. `Pramana.Corpus.provenance/1` supplied
  the **text's** volume, and a work spanning volumes records its range there — `"130-133"`
  for L1557 — so the citation came out as `130-133n1557_p0003a01`. It now supplies the
  volume the cited line was itself printed in.

  Both shipped hidden behind a corpus that was one collection, of two-digit volumes, with
  no work spanning any of them. Ten collections made them reachable, and neither would
  ever have raised: a wrong linehead is a plausible-looking string that silently fails in
  someone else's search box.
  """
  @spec linehead(map()) :: String.t() | nil
  def linehead(%{
        witness: witness,
        volume: volume,
        work_id: work_id,
        page: page,
        register: register,
        line: line
      })
      when is_binary(witness) and is_binary(work_id) and
             is_binary(page) and is_binary(register) and is_integer(line) do
    # `work_id` is "T0262"; CBETA's linehead wants the number without the canon letter:
    # T09n0262_p0037a13. J numbers keep a letter of their own — J31nB271 — and stripping
    # only the canon prefix preserves it.
    number = String.replace_prefix(work_id, witness, "")

    case {number, Collections.volume_token(witness, volume)} do
      {"", _} -> nil
      {_, nil} -> nil
      {number, token} -> "#{token}n#{number}_p#{page}#{register}#{pad_line(line)}"
    end
  end

  def linehead(_), do: nil

  defp pad_line(line), do: line |> Integer.to_string() |> String.pad_leading(2, "0")
end
