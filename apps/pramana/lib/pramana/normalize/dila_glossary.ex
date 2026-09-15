defmodule Pramana.Normalize.DilaGlossary do
  @moduledoc """
  DILA's TEI P5 glossaries — Soothill-Hodous, Karashima, the Mahāvyutpatti.

  ## Why these, and what makes Karashima different from a dictionary

  A general Buddhist dictionary tells you what a word means. **Karashima's glossaries tell
  you what one translator meant by it**, which is a different and much sharper claim. Two
  entries make the case:

      佛   Soothill-Hodous   Buddha, from budh "to be aware of"…
      佛   Lokakṣema         enlightenment; Buddhaship — a transliteration of Skt. bodhi

      法   Soothill-Hodous   Dharma. Law, truth, religion, thing, anything Buddhist…
      法   Kumārajīva        as a rule, normally, conforming to what is expected

  In the earliest Chinese translations 佛 transliterates *bodhi*, not *buddha*; and
  Kumārajīva's 法 is frequently an ordinary adverb rather than *dharma* at all. Karashima
  also records that **Lokakṣema very often rendered Skt. *śrāvaka* as 阿羅漢** — an
  equivalence that silently corrupts a reading if you do not know it. No general lexicon
  carries any of that, because no general lexicon is scoped to a translator.

  That scoping is why these fit here rather than merely being good: this project's whole
  argument is that provenance is multi-axis and a claim carries the conditions it holds
  under. A gloss is a claim about a word, and `work_id` is where it says so.

  ## Three shapes, one entry

  The files disagree about markup because they were digitised at different times, and
  each shape is parsed on its own terms rather than through a lowest common denominator:

    * **Soothill-Hodous** — `<form>頭詞</form><sense>gloss</sense>`, Chinese-headed.
    * **Karashima** — `<form><orth/><pron/></form><def/>`, Chinese-headed, and each entry
      carries reconstructed Eastern Han and Qieyun phonology plus **Taishō citations with
      page-and-line references, the Chinese quote, and the Sanskrit witness beside it**.
    * **Mahāvyutpatti** — Sanskrit-headed, with `<cit type="translation">` giving the
      Chinese and Tibetan equivalents of one Sanskrit term. This is the only one of the
      three that is a *bridge* rather than a dictionary.

  ## The citations are the part that matters most

  A Karashima entry names `T.262` at `59b7`. That is a Taishō address this corpus already
  holds, so a gloss can be anchored to the lines that exhibit it and byte-verified like
  anything else — the dictionary joins the citation guard rather than sitting beside it.
  They are parsed and kept in `meta` here; anchoring them to URNs is a separate step, and
  a separate claim.

  ## Attestation, which is how a reader weighs an equivalence

  `chinese_attestation` is `source` when the entry carries a real Sanskrit witness with a
  reference, and `dictionary` otherwise. The column already existed for the 84000
  glossary and means the same thing: **did somebody see this in a text, or did they read
  it in a book.**
  """

  @typedoc "One parsed sense. `gloss_id` is unique within its glossary."
  @type entry :: %{
          gloss_id: String.t(),
          chinese: String.t() | nil,
          sanskrit: String.t() | nil,
          tibetan: String.t() | nil,
          english: String.t() | nil,
          definition: String.t() | nil,
          chinese_attestation: String.t() | nil,
          citations: [String.t()],
          pinyin: String.t() | nil
        }

  @doc """
  Parses one glossary file. `shape` is `:soothill`, `:karashima` or `:mahavyutpatti`.

  Returns entries in file order. A headword that appears more than once keeps **every**
  occurrence as its own entry — see the moduledoc: collapsing senses is the one thing a
  glossary of a polysemous language must not do.
  """
  @spec parse(String.t(), atom(), String.t()) :: [entry()]
  def parse(xml, shape, glossary_id) do
    xml
    |> entries()
    |> Enum.map(&parse_entry(&1, shape))
    |> Enum.reject(&is_nil/1)
    |> number(glossary_id)
  end

  # `Regex.scan` over `<entry>…</entry>` rather than a streaming parser: these are 4-7 MB
  # files read once at ingest, not a bake stage, and the whole file is already in memory
  # by the time anything decides what to do with it. `CLAUDE.md`'s Saxy rule is about
  # documents in the corpus pipeline, which this is not.
  defp entries(xml) do
    ~r/<entry\b.*?<\/entry>/s
    |> Regex.scan(xml)
    |> Enum.map(&hd/1)
  end

  defp parse_entry(entry, :soothill) do
    with head when head != nil <- text_of(entry, ~r/<form[^>]*>(.*?)<\/form>/s),
         gloss when gloss != nil <- text_of(entry, ~r/<sense[^>]*>(.*?)<\/sense>/s) do
      %{
        chinese: head,
        sanskrit: first_term(entry),
        tibetan: nil,
        english: gloss,
        definition: gloss,
        # Soothill-Hodous is a dictionary reporting other dictionaries. It is never
        # `source` — that would claim a witness nobody looked at.
        chinese_attestation: "dictionary",
        citations: [],
        pinyin: nil
      }
    else
      _ -> nil
    end
  end

  defp parse_entry(entry, :karashima) do
    case text_of(entry, ~r/<orth[^>]*>(.*?)<\/orth>/s) do
      nil ->
        nil

      head ->
        sanskrit = sanskrit_witness(entry)
        definition = text_of(entry, ~r/<def[^>]*>(.*?)<\/def>/s)

        %{
          chinese: head,
          sanskrit: sanskrit,
          tibetan: nil,
          english: definition,
          definition: definition,
          # A Sanskrit witness with an actual reading is somebody having seen the
          # equivalence in a text. Without one the entry is still Karashima's judgement,
          # which is worth a great deal and is still not an attestation.
          chinese_attestation: if(sanskrit, do: "source", else: "dictionary"),
          citations: citations(entry),
          pinyin: text_of(entry, ~r/<pron notation="pinyin">(.*?)<\/pron>/s)
        }
    end
  end

  defp parse_entry(entry, :mahavyutpatti) do
    case text_of(entry, ~r/<orth xml:lang="san-Latn">(.*?)<\/orth>/s) do
      nil ->
        nil

      sanskrit ->
        %{
          chinese: translation(entry, "zho-Hant"),
          sanskrit: sanskrit,
          tibetan: translation(entry, "bod-Tibt"),
          english: nil,
          definition: nil,
          # The Mahāvyutpatti IS the ninth-century commission's own equivalence table, so
          # its Chinese is an attested rendering rather than a modern lexicographer's
          # reading of one.
          chinese_attestation: "source",
          citations: [],
          pinyin: nil
        }
    end
  end

  # `T.262` + `59b7` -> "T.262:59b7". Kept as the edition prints them and resolved to URNs
  # elsewhere, because a locator grammar belongs to its edition — rule 68's lesson applied
  # before there is anything to get wrong.
  defp citations(entry) do
    ~r/<cit type="(T\.[\dA-Za-z]+)">\s*<bibl>(.*?)<\/bibl>/s
    |> Regex.scan(entry)
    |> Enum.map(fn [_, work, line] -> "#{work}:#{strip(line)}" end)
    |> Enum.uniq()
  end

  # BOUNDED TO THE ELEMENT, and the first version was not. Karashima records a Sanskrit
  # NON-correspondence as `<bibl>K. not found at 32.16</bibl>` with no `<quote>` at all —
  # a real finding, that the Sanskrit has no counterpart here. An unbounded
  # `<cit type="sa-witness">.*?<quote>` then ran past it into the next parallel's Chinese
  # quote, and stored a line of the Lotus Sūtra in the `sanskrit` column of 法.
  #
  # So the search stops at the element's own boundary, and an entry counts as attested
  # only when a witness carries a reading rather than merely a reference.
  # EVERY witness block, not the first: Karashima lists one per parallel passage, and the
  # first is frequently a "not found". 法 records `K. not found at 32.16` for its opening
  # parallel and `dharmatā` at `K. 40.15` for the next, so taking the first block alone
  # reported the word as unattested when Karashima had attested it one line down.
  defp sanskrit_witness(entry) do
    ~r/<cit type="sa-witness">((?:(?!<\/cit>).)*)/s
    |> Regex.scan(entry)
    |> Enum.find_value(fn [_, block] ->
      case Regex.run(~r/<quote>(.*?)<\/quote>/s, block) do
        [_, quote] -> strip(quote)
        nil -> nil
      end
    end)
  end

  defp first_term(entry) do
    case Regex.run(~r/<term xml:lang="san-Latn">(.*?)<\/term>/s, entry) do
      [_, term] -> strip(term)
      nil -> nil
    end
  end

  defp translation(entry, lang) do
    case Regex.run(
           ~r/<cit type="translation" xml:lang="#{lang}">\s*<quote>(.*?)<\/quote>/s,
           entry
         ) do
      [_, quote] -> strip(quote)
      nil -> nil
    end
  end

  defp text_of(entry, pattern) do
    case Regex.run(pattern, entry) do
      [_, inner] -> strip(inner)
      nil -> nil
    end
  end

  defp strip(fragment) do
    fragment
    |> String.replace(~r/<[^>]+>/, " ")
    |> unescape()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp unescape(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end

  # ONE ROW PER SENSE, and the ordinal is what makes that expressible. 法 appears in
  # Kumārajīva's glossary more than once because it means more than one thing; a
  # `gloss_id` keyed on the headword alone would keep whichever was parsed last and
  # report a polysemous word as having settled.
  defp number(entries, glossary_id) do
    entries
    |> Enum.reduce({[], %{}}, fn entry, {acc, seen} ->
      key = entry.chinese || entry.sanskrit || "?"
      n = Map.get(seen, key, 0) + 1

      {[Map.put(entry, :gloss_id, "#{glossary_id}:#{key}:#{n}") | acc], Map.put(seen, key, n)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
