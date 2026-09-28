defmodule PramanaWeb.MCP.Tools.VerifyCitation do
  @moduledoc """
  Byte-compares a quotation against the passage its URN addresses.

  Exposing the guard as a tool lets a model check itself *before* answering. That is
  useful, but it is not the guarantee: the guarantee is that `Pramana.Guard` also runs
  after generation, outside the model, where nothing the model does can skip it.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Guard
  alias PramanaWeb.MCP.Reply

  schema do
    field(:urn, :string, required: true, description: "The URN the quotation is attributed to.")

    field(:quoted_text, :string,
      required: true,
      description: "The exact text being quoted. Compared byte-for-byte, not fuzzily."
    )
  end

  @impl true
  def execute(%{urn: urn, quoted_text: quoted} = params, frame) do
    # DIAGNOSED. `:quote_mismatch` is true of a fabricated sūtra, of a quotation from an
    # edition that punctuates differently, and of a citation naming the first of the two
    # lines it quotes. Returning the same sentence for all three is what makes a caller
    # treat the verdict as noise.
    finding = urn |> Guard.check(quoted) |> Guard.diagnose()

    payload = %{
      urn: finding.urn,
      verdict: finding.verdict,
      verified: finding.verdict == :ok and finding.quoted != nil,
      verification:
        if(finding.verdict == :ok and finding.quoted == nil,
          do: :existence_only,
          else: :quotation
        ),
      quoted: finding.quoted,
      actual: finding.actual,
      provenance: finding.provenance,
      reason: finding[:reason],
      found_at: finding[:found_at],
      search_status: finding[:search_status],
      explanation: finding[:explanation] || explain(finding)
    }

    {:reply, Reply.json("verify_citation", params, payload), frame}
  end

  defp explain(%{verdict: :ok, quoted: nil}),
    do: "Only the existence of this URN was checked; no nonblank quotation was verified."

  defp explain(%{verdict: :ok}), do: "The quoted text appears verbatim at this URN."

  # Only reached when the diagnosis declined to be more specific, which it does not for a
  # mismatch — kept so the tool still answers if `diagnose/1` ever returns nothing.
  defp explain(%{verdict: :quote_mismatch}),
    do:
      "This URN exists, but the quoted text does not appear in it. Compare against " <>
        "`actual` and correct the quotation, or cite a different passage."

  defp explain(%{verdict: :not_found}),
    do: "No passage exists at this URN in the current bake. Do not cite it."

  defp explain(%{verdict: :bad_urn}), do: "The URN is malformed and addresses nothing."

  defp explain(%{verdict: :not_citable_as_source}),
    do:
      "This is a generated translation layer, not source text. Cite the source anchor " <>
        "it renders instead."
end
