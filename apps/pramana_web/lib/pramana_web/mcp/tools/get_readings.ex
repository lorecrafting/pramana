defmodule PramanaWeb.MCP.Tools.GetReadings do
  @moduledoc """
  How a passage is pronounced, where the ordinary answer is wrong.

  Transliterated Sanskrit in Chinese follows conventional readings that ignore the
  characters' ordinary values, and a general pinyin library gets them confidently wrong
  in exactly the passages a reader most wants help with. 般若 is *bōrě*, not *bānruò*;
  迦葉 is *jiāshè*, not *jiāyè*; and 佛 — 533,670 occurrences of it — is *fó*, where
  Unicode's per-character field says *fú*.

  **Every token says where its reading came from.** A reading marked `base` is the
  ordinary one applied unchanged and carries no claim about Buddhist convention; one
  marked `exception` was overridden by the dictionary; one marked `unknown` has no
  reading recorded, and is returned as `null` rather than guessed. A caller that wants
  to show only what is defensible can filter on that field, which it could not do if the
  three were flattened into one string.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias PramanaWeb.MCP.Reply
  alias Pramana.Corpus
  alias Pramana.Readings

  schema do
    field(:urn, :string,
      required: true,
      description:
        "The passage to read aloud, e.g. pramana:cbeta.T:T0251_001@p0848c07. Ranges " <>
          "are accepted."
    )

    field(:scheme, :string,
      description:
        "Romanisation scheme. Defaults to `pinyin`. Chinese Buddhist texts are also " <>
          "read in Japanese 呉音 (`on-yomi`) and Korean (`mccune-reischauer`), and the " <>
          "same characters take different readings in each."
    )
  end

  @impl true
  def execute(%{urn: urn} = params, frame) do
    scheme = params[:scheme] || "pinyin"

    case Corpus.resolve(urn) do
      {:ok, span} ->
        tokens = Readings.render(span.content, scheme: scheme, lang: lang_for(scheme))

        {:reply, Reply.json("get_readings", params, payload(span, tokens, scheme)), frame}

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
           "Malformed URN: #{urn}. Expected pramana:<source>.<witness>:<work>@<locator>."
         ), frame}
    end
  end

  # The reading conventions that apply, which is not the same as the language of the
  # text: a Chinese sūtra chanted in a Japanese temple is read with 呉音.
  defp lang_for("wylie"), do: "bo"
  defp lang_for("on-yomi"), do: "ja"
  defp lang_for("kun-yomi"), do: "ja"
  defp lang_for("mccune-reischauer"), do: "ko"
  defp lang_for(_), do: "lzh"

  defp payload(span, tokens, scheme) do
    exceptions = Enum.count(tokens, &(&1.source == :exception))
    unknown = Enum.count(tokens, &(&1.source == :unknown))

    %{
      urn: span.urn,
      text: span.content,
      scheme: scheme,
      reading: tokens |> Enum.map(& &1.reading) |> Enum.reject(&is_nil/1) |> Enum.join(" "),
      tokens: Enum.map(tokens, &%{form: &1.form, reading: &1.reading, source: &1.source}),
      counts: %{
        tokens: length(tokens),
        from_dictionary: exceptions,
        without_reading: unknown
      },
      note:
        "`source` is per token: `exception` means the Buddhist reading dictionary " <>
          "overrode the ordinary reading, `base` means the ordinary reading was used " <>
          "unchanged, `computed` means it was derived by a deterministic transliteration " <>
          "with no dictionary involved, `unknown` means no reading is recorded and none " <>
          "was guessed. " <>
          "Readings are a rendering aid — the text, not its pronunciation, is what is " <>
          "citable."
    }
  end
end
