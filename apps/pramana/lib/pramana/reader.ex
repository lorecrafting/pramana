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

  That field is not hedging. Deep links to these readers **cannot be checked by fetching
  them**: both CBETA Online and SAT are single-page apps that resolve content in the
  browser, and they return HTTP 200 with a byte-identical body for a real path and for
  complete nonsense. There is no server-side signal to test against, so a link checker
  would be theatre. The honest move is to say so in the payload.

  ## Only formats confirmed against real pages are shipped

  CBETA Online's `/{lang}/{work}_{juan}` form is confirmed by indexed pages that render
  the expected text. SAT's is **not** confirmed, so there is no SAT template here — it
  arrives with the SAT source itself in Phase 2 (task #14), where it can be checked
  against real ingested identifiers rather than guessed at.

  Returning `nil` for a source we have no confirmed template for is deliberate. A link
  that looks plausible and lands on the wrong passage is worse than no link, because
  nothing about it appears wrong.
  """

  alias Pramana.Cbeta.Collections

  @cbeta_base "https://cbetaonline.dila.edu.tw"

  @type link :: %{
          edition: String.t(),
          url: String.t(),
          granularity: String.t(),
          linehead: String.t() | nil,
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
  """
  @spec reference(String.t(), map(), keyword()) :: link() | nil
  def reference(urn_string, provenance, opts \\ [])

  def reference(urn_string, %{source: "cbeta"} = provenance, opts) when is_binary(urn_string) do
    case work_component(urn_string) do
      nil ->
        nil

      work ->
        lang = if opts[:lang] == "zh", do: "zh", else: "en"

        %{
          edition: "CBETA Online",
          # `work` is already the reader's own path segment (`T0262_001` — text number
          # and juan). Taking it verbatim rather than reassembling it from parts means
          # there is no second place for the two to disagree.
          url: "#{@cbeta_base}/#{lang}/#{work}",
          granularity: "juan",
          linehead: linehead(provenance),
          verified: false,
          note:
            "Opens the fascicle, not the line — the reader has no line-addressable URL. " <>
              "Paste `linehead` into its Goto box to jump to the exact line. " <>
              "The URN is the citation; this link is a convenience and is not verified."
        }
    end
  end

  def reference(_urn_string, _provenance, _opts), do: nil

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

  # The work component of `pramana:cbeta.T:T0262_001@p0001a03` is `T0262_001`.
  defp work_component(urn_string) do
    case Pramana.URN.parse(urn_string) do
      {:ok, %Pramana.URN{work: work}} -> work
      {:error, _} -> nil
    end
  end

  defp pad_line(line), do: line |> Integer.to_string() |> String.pad_leading(2, "0")
end
