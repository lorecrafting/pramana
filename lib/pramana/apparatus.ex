defmodule Pramana.Apparatus do
  @moduledoc """
  The critical apparatus: where the witnesses to a text disagree.

  The Taishō prints a variant apparatus — where the Song, Yuan, Ming, Koryŏ and other
  editions read differently from the base text — and CBETA's TEI encodes it as
  `<app><lem>…</lem><rdg wit="…">…</rdg></app>`. **572,701 segments in this corpus carry
  one.** It was captured from the beginning and, until now, was reachable only as an
  opaque blob attached to a passage a reader had already fetched.

  "This character differs in the Song edition" is what a philologist actually needs, and
  no other AI tool over this corpus offers it (`docs/COMPETITIVE.md`).

  ## Witness ids are per text, and assuming otherwise misattributes thousands of variants

  A `<rdg wit="#wit1">` names a witness declared in **that file's own header**, and the
  ids are not stable across the canon. Measured over all 2,471 CBETA files:

      wit1  means 38 different things — 宋 in 832 files, 明 in 375, 甲 in 322, 原 in 149
      wit2  means 33 different things
      only 4 of 23 witness ids are stable

  So a global table mapping `wit1` to 宋 would state, confidently and in the tradition's
  own vocabulary, that a Ming variant belongs to the Song edition — in roughly a thousand
  works. That is the exact shape of error this project exists to prevent, and it is why
  `mix pramana.witnesses.import` reads each text's declarations from its own pinned file.

  A segment whose text has no witness map yields variants with `witness: nil` and the raw
  id preserved, never a guess.
  """

  import Ecto.Query

  alias Pramana.Corpus
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Repo

  @doc """
  The variant readings recorded at a URN, with each witness named.

  Returns `{:ok, %{urn:, lemma_count:, variants: [...]}}`, or `{:ok, %{variants: []}}`
  when the edition records no disagreement here — which is the ordinary case and is
  reported as such rather than as an absence of data.
  """
  @spec at(String.t()) :: {:ok, map()} | {:error, atom()}
  def at(urn) when is_binary(urn) do
    with {:ok, segment} <- fetch_segment(urn) do
      witnesses = witness_map(segment.text)

      variants =
        segment.meta
        |> Map.get("apparatus", [])
        |> Enum.flat_map(&entry_variants(&1, witnesses))

      {:ok,
       %{
         urn: urn,
         work_id: segment.text.work_id,
         content: segment.content,
         lemma_count: length(Map.get(segment.meta, "apparatus", [])),
         variants: variants,
         witnesses: witnesses,
         note: note(variants)
       }}
    end
  end

  defp note([]),
    do:
      "No variant readings are recorded at this line. The witnesses collated by this " <>
        "edition agree here."

  defp note(variants),
    do:
      "#{length(variants)} variant reading(s). Each names the witness that reads " <>
        "differently from the base text, in the edition's own sigla."

  # One entry is one lemma — a word or character in the base text — with the readings the
  # other witnesses give for it. Flattened to one row per (lemma, witness) because that is
  # the claim a reader is checking: "this witness reads this here".
  defp entry_variants(entry, witnesses) do
    lemma = entry["lem"]

    entry
    |> Map.get("rdgs", [])
    |> Enum.flat_map(fn rdg ->
      rdg
      |> Map.get("wit", "")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(fn wit_id ->
        %{
          lemma: lemma,
          reading: rdg["text"],
          # An `omitted` reading means the witness has nothing where the base text has the
          # lemma. That is a different claim from "reads something else", and collapsing
          # the two would turn an omission into a substitution.
          omitted: rdg["omitted"] == true,
          witness_id: wit_id,
          witness: resolve(wit_id, witnesses)
        }
      end)
    end)
  end

  # nil rather than the raw id when unresolvable: a caller can show `witness_id` and say
  # it is unidentified, but must never be handed `#wit1` as though it were a sigil.
  defp resolve(wit_id, witnesses) do
    Map.get(witnesses, String.trim_leading(wit_id, "#"))
  end

  @doc """
  The witness sigla declared by a text, as `%{"wit1" => "【宋】"}`.

  Empty when the text has not had its declarations imported, which is honest: the
  alternative is a global table that is wrong for most of the canon.
  """
  @spec witness_map(Text.t()) :: map()
  def witness_map(%Text{meta: meta}) when is_map(meta), do: Map.get(meta, "witnesses", %{})
  def witness_map(_), do: %{}

  defp fetch_segment(urn) do
    case Repo.one(from s in Segment, where: s.urn == ^urn, preload: [text: :work]) do
      nil -> resolve_range(urn)
      segment -> {:ok, segment}
    end
  end

  # A range URN addresses several lines; the apparatus of the first is not the apparatus
  # of the range, so a range is refused rather than silently answered for one line of it.
  defp resolve_range(urn) do
    case Corpus.resolve(urn) do
      {:ok, _} -> {:error, :not_a_single_line}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  How many lines of one work carry a variant apparatus.

  A work-level question — *does this text have an apparatus at all, and how dense is it*
  — which a reader asks before opening a work, and which `at/1` cannot answer because it
  is per line. Lives here rather than in the view: a surface counting `meta ? 'apparatus'`
  for itself is a second definition of what an apparatus is.
  """
  @spec count_for_work(String.t()) :: non_neg_integer()
  def count_for_work(work_id) when is_binary(work_id) do
    Repo.aggregate(
      from(s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where: t.work_id == ^work_id and fragment("? \\? 'apparatus'", s.meta)
      ),
      :count
    )
  end

  @doc """
  How much of the corpus carries an apparatus, and how much of it is legible.

  The second number is the one that matters: a variant whose witness cannot be named is
  data we hold and cannot serve.
  """
  @spec coverage() :: map()
  def coverage do
    with_apparatus =
      Repo.aggregate(from(s in Segment, where: fragment("? \\? 'apparatus'", s.meta)), :count)

    texts_with_witnesses =
      Repo.aggregate(from(t in Text, where: fragment("? \\? 'witnesses'", t.meta)), :count)

    %{
      segments_with_apparatus: with_apparatus,
      texts_with_witness_map: texts_with_witnesses,
      texts: Repo.aggregate(Text, :count)
    }
  end
end
