defmodule Pramana.CorpusFixtures do
  @moduledoc "Minimal source text fixtures with byte-faithful bodies, offsets and hashes."

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Repo

  @doc "Insert one text for existing work/source/witness rows and ordered {URN, content} lines."
  def text!(attrs, lines) when is_map(attrs) and is_list(lines) and lines != [] do
    body = Enum.map_join(lines, "\n", &elem(&1, 1))

    text =
      attrs
      |> Map.merge(%{body: body, body_sha256: sha256(body), char_count: String.length(body)})
      |> then(&struct!(Text, &1))
      |> Repo.insert!()

    {segments, _offsets} =
      lines
      |> Enum.with_index()
      |> Enum.map_reduce({0, 0}, fn {{urn, content}, ordinal}, {chars, bytes} ->
        segment =
          Repo.insert!(%Segment{
            text_id: text.id,
            urn: urn,
            ordinal: ordinal,
            content: content,
            content_sha256: sha256(content),
            char_start: chars,
            char_end: chars + String.length(content),
            byte_start: bytes,
            byte_end: bytes + byte_size(content),
            meta: %{}
          })

        {segment, {segment.char_end + 1, segment.byte_end + 1}}
      end)

    %{text: text, segments: segments}
  end

  @doc "Insert an alignment only when its lemma is present at both declared positions."
  def alignment!(root, commentary, lemma, opts \\ []) do
    root_offset = Keyword.get(opts, :root_offset, 0)
    commentary_offset = Keyword.get(opts, :commentary_offset, 0)
    length = String.length(lemma)

    unless String.slice(root.content, root_offset, length) == lemma and
             String.slice(commentary.content, commentary_offset, length) == lemma do
      raise ArgumentError, "alignment fixture must quote both source spans exactly"
    end

    root_text = Repo.get!(Text, root.text_id)
    commentary_text = Repo.get!(Text, commentary.text_id)

    Repo.insert!(
      struct!(Pramana.Corpus.CommentaryAlignment, %{
        lemma: lemma,
        lemma_sha256: sha256(lemma),
        length: length,
        root_text_id: root.text_id,
        root_work_id: root_text.work_id,
        root_urn: root.urn,
        root_char_start: root.char_start + root_offset,
        root_char_end: root.char_start + root_offset + length,
        commentary_text_id: commentary.text_id,
        commentary_work_id: commentary_text.work_id,
        commentary_urn: commentary.urn,
        commentary_char_start: commentary.char_start + commentary_offset,
        commentary_char_end: commentary.char_start + commentary_offset + length,
        method: "lemma_match",
        confidence: "probable"
      })
    )
  end

  def sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
