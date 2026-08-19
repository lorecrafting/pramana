defmodule Pramana.Normalize.Catalogue84000 do
  @moduledoc """
  Reads one record of 84000's RDF catalogue: what a Tōhoku number is called, and what
  BDRC calls it.

  The Derge etext titles *volumes*, not works, so the Kangyur arrives here with 1,195
  works and no titles. 84000's TEI supplies them for the 385 texts it has translated. This
  covers the rest: **1,160 Tōhoku numbers**, translated or not, which is the whole
  catalogue.

  ## Four descriptions of one text, and each holds a different title

  A record describes the same work four times over, because they are four different
  things and the field distinguishes them:

      WAI…   the abstract Indic work        Sanskrit title, English title
      WAT…   the Tibetan translation        Tibetan title
      WEKD…  the Degé printing of it        Tibetan title, and the BDRC id of that print
      WAE…   84000's English translation    English title, and who made it

  The Tibetan title is therefore taken from `WEKD` — the edition this corpus actually
  holds — and the Sanskrit from `WAI`, which is the work the Tibetan translates. Reading
  any `skos:prefLabel` with the right language tag would collapse the four and quietly
  attribute the Degé's title to the Sanskrit original.

  ## The metadata is CC0 even though the translations are not

  The repository's README states CC BY-NC-ND, and the record's own `adm:license` says
  `LicenseCC0` with the label "Metadata related to the translations by 84000, provided
  under the CC0 License". Both are true of different things: the prose of a translation is
  restricted, the fact that Toh 1-1 is called *Pravrajyāvastu* is not. This is the same
  shape as bilara-data, whose repository claimed CC0 while its publication file recorded
  Public Domain Mark and CC BY-SA — and the rule there applies here: **the more specific
  statement governs, and a licence is recorded per publication rather than per
  repository** (`docs/STATUS.md`).
  """

  @behaviour Saxy.Handler

  @type t :: %{
          toh: String.t(),
          titles: %{String.t() => String.t()},
          bdrc: %{String.t() => String.t()},
          translators: [String.t()]
        }

  # The subject prefixes, longest first: `WAT` is a prefix of nothing but `WA` is a prefix
  # of `WAI`, `WAT` and `WAE`, so order decides correctness here.
  @kinds [{"WEKD", :derge}, {"WAI", :indic}, {"WAT", :tibetan}, {"WAE", :english}]

  @doc """
  Parses one `tohN.rdf` file.

  Returns the titles keyed by the language tags the file uses — `en`, `sa-x-iast`, `bo` —
  plus the BDRC resource ids, which are what a IIIF image link is built from.
  """
  @spec parse(binary() | Enumerable.t()) :: {:ok, t()} | {:error, term()}
  def parse(xml) do
    state = %{
      subject: nil,
      kind: nil,
      lang: nil,
      pref?: false,
      buffer: nil,
      labels: %{},
      bdrc: %{},
      person?: false,
      translators: [],
      toh: nil
    }

    with {:ok, final} <- run(xml, state) do
      {:ok,
       %{
         toh: final.toh,
         titles: titles(final.labels),
         bdrc: final.bdrc,
         translators: final.translators |> Enum.reverse() |> Enum.uniq()
       }}
    end
  end

  # The Tibetan is the Degé's own, falling back to the abstract Tibetan work; the Sanskrit
  # is the Indic work's; the English is 84000's translation title, falling back to the one
  # recorded on the Indic work.
  defp titles(labels) do
    %{
      "bo" => labels[{:derge, "bo"}] || labels[{:tibetan, "bo"}],
      "sa" => labels[{:indic, "sa-x-iast"}],
      "en" => labels[{:english, "en"}] || labels[{:indic, "en"}]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp run(xml, state) when is_binary(xml), do: Saxy.parse_string(xml, __MODULE__, state)
  defp run(stream, state), do: Saxy.parse_stream(stream, __MODULE__, state)

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:end_document, _data, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attrs}, state) do
    {:ok, start(local(name), Map.new(attrs), state)}
  end

  @impl Saxy.Handler
  def handle_event(:end_element, name, state), do: {:ok, finish(local(name), state)}

  @impl Saxy.Handler
  def handle_event(:characters, _text, %{buffer: nil} = state), do: {:ok, state}

  def handle_event(:characters, text, state),
    do: {:ok, %{state | buffer: state.buffer <> text}}

  defp local(name), do: name |> String.split(":") |> List.last()

  defp start("Description", attrs, state) do
    subject = attrs["rdf:about"] |> to_string() |> String.split("/") |> List.last()
    %{state | subject: subject, kind: kind_of(subject), toh: state.toh || toh_of(subject)}
  end

  # A person named inside the English work's `creator` block. Their `prefLabel` is a name
  # rather than a title, so it must not land in the title map.
  defp start("Person", _attrs, state), do: %{state | person?: true}

  defp start("prefLabel", attrs, state),
    do: %{state | pref?: true, lang: attrs["xml:lang"], buffer: ""}

  # `owl:sameAs` on the Degé printing is the BDRC id of that print — `MW22084_0001-1` —
  # which is what a IIIF manifest is addressed by. On the other three it identifies the
  # abstract work, which is worth keeping and is not the same thing.
  defp start("sameAs", attrs, %{kind: kind} = state) when not is_nil(kind) do
    case attrs["rdf:resource"] do
      nil ->
        state

      uri ->
        %{state | bdrc: Map.put(state.bdrc, to_string(kind), List.last(String.split(uri, "/")))}
    end
  end

  defp start(_name, _attrs, state), do: state

  defp finish("Description", state), do: %{state | subject: nil, kind: nil}
  defp finish("Person", state), do: %{state | person?: false}

  defp finish("prefLabel", %{pref?: true, person?: true} = state) do
    %{state | pref?: false, buffer: nil, translators: [squeeze(state.buffer) | state.translators]}
  end

  defp finish("prefLabel", %{pref?: true, kind: kind, lang: lang} = state)
       when not is_nil(kind) and not is_nil(lang) do
    labels = Map.put_new(state.labels, {kind, lang}, squeeze(state.buffer))
    %{state | pref?: false, buffer: nil, labels: labels}
  end

  defp finish("prefLabel", state), do: %{state | pref?: false, buffer: nil}
  defp finish(_name, state), do: state

  defp kind_of(subject) do
    Enum.find_value(@kinds, fn {prefix, kind} ->
      if String.starts_with?(subject, prefix), do: kind
    end)
  end

  # `WEKDTOH1-1` -> `toh1-1`. Taken from the subject rather than the filename so a record
  # is self-describing.
  defp toh_of(subject) do
    case Regex.run(~r/TOH([\w.-]+)$/, subject) do
      [_, number] -> "toh" <> String.downcase(number)
      nil -> nil
    end
  end

  defp squeeze(nil), do: nil
  defp squeeze(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()
end
