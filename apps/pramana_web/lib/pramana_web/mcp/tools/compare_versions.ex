defmodule PramanaWeb.MCP.Tools.CompareVersions do
  @moduledoc """
  The same passage beside its other versions — translations of it, and the parallel
  texts scholarship links to it.

  The distinction this tool exists to preserve: a **rendering** is someone's English for
  the text in front of you; a **parallel** is a different text judged to transmit the
  same discourse. Merged into one list, a Pāli sutta reads as a translation of a Chinese
  Āgama, when in fact neither derives from the other. They arrive in separate keys and
  each parallel carries its relation strength.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Compare

  schema do
    field(:urn, :string,
      required: true,
      description:
        "The passage to compare, e.g. pramana:sc.ms:sn22.12@1.2. Renderings and " <>
          "parallels are gathered for the work this passage belongs to."
    )

    field(:lang, :string,
      description: "Translation language for the rendering pool. Defaults to en."
    )

    field(:translator, :string, description: "Pin one translator rather than the whole pool.")

    field(:relations, {:list, :string},
      description:
        "Which parallel strengths to include: full, resembling, sections, mentions, " <>
          "retells. Defaults to full and resembling. A `mentions` is a passing " <>
          "reference and is never a parallel."
    )

    field(:include_text, :boolean,
      description:
        "Resolve each parallel to its actual passage rather than returning ids alone. " <>
          "Defaults to true."
    )

    field(:limit, :integer, description: "Cap on parallels resolved. Defaults to 10.")
  end

  @impl true
  def execute(%{urn: urn} = params, frame) do
    opts =
      [
        lang: params[:lang],
        translator: params[:translator],
        relations: params[:relations],
        include_text: params[:include_text],
        limit: params[:limit]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Compare.versions(urn, opts) do
      {:ok, payload} ->
        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, :not_found} ->
        {:reply,
         Response.error(
           Response.tool(),
           "No passage exists at #{urn}. This URN is well-formed but addresses nothing " <>
             "in the current bake — do not cite it."
         ), frame}

      {:error, _} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Malformed URN: #{urn}. Expected pramana:<source>.<witness>:<work>[@<locator>]."
         ), frame}
    end
  end
end
