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
    finding = Guard.check(urn, quoted)

    payload = %{
      urn: finding.urn,
      verdict: finding.verdict,
      verified: finding.verdict == :ok,
      quoted: finding.quoted,
      actual: finding.actual,
      provenance: finding.provenance,
      explanation: explain(finding.verdict)
    }

    {:reply, Reply.json("verify_citation", params, payload), frame}
  end

  defp explain(:ok), do: "The quoted text appears verbatim at this URN."

  defp explain(:quote_mismatch),
    do:
      "This URN exists, but the quoted text does not appear in it. Compare against " <>
        "`actual` and correct the quotation, or cite a different passage."

  defp explain(:not_found),
    do: "No passage exists at this URN in the current bake. Do not cite it."

  defp explain(:bad_urn), do: "The URN is malformed and addresses nothing."

  defp explain(:not_citable_as_source),
    do:
      "This is a generated translation layer, not source text. Cite the source anchor " <>
        "it renders instead."
end
