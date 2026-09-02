defmodule Pramana.Translate.Transfer do
  @moduledoc """
  Moves passages out to a generation host and renderings back in.

  The counterpart of `Pramana.Embed.Transfer`, and deliberately the same shape: a JSONL
  file out, a JSONL file back, and **the sha256 travels with the text so the import can
  prove the rendering still describes the passage it claims to**. The generation host is
  a rented GPU running `priv/embed/modal_translate.py`; it is handed text and hands text
  back, and every decision about what any of it means happens here.

  ## What comes back is never a source

  A rendering stored here is `method: "llm"` and `tier: "t1"` — `CLAUDE.md` invariant #8.
  It is a layer over a source anchor, never a top-level URN, and `Pramana.Guard` rejects
  any quote resolving to `method != human` presented as canonical. That is also what the
  Gemma Prohibited Use Policy requires of us — its "false attribution of human authorship"
  clause — so the licence and the invariant want the same thing, and the invariant is the
  one that is structurally enforced. `docs/PLAN.md` § E1 records the licence reading.

  ## Anchored to the chunk, not to a line

  A generative model is given a chunk, because a passage is what it can translate well;
  the resulting English therefore covers the chunk's whole ordinal span and is stored
  range-anchored, the way 84000's folio-level English is. `Chunk.Vectors.range_renderings/2`
  finds it by `ordinal_start`/`ordinal_end` — see rule 68 for why it must not be found by
  a prefix match on the anchor.

  ## The rendering carries what produced it

  `model_id` is the model, `prompt_version` is the sidecar's `params_sha256` — a hash of
  the model, revision, decoding settings and library version it actually ran with. A
  changed setting is then detectable rather than silently mixed into one tranche, which
  is the same reason `modal_embed.py` records `max_length` per row.
  """

  import Ecto.Query

  alias Pramana.Bake
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Text
  alias Pramana.Repo
  alias Pramana.Translations

  @default_lang "en"

  @doc """
  Writes one `{id, sha256, content, target_lang}` per line for the selected chunks.

  Options:

    * `:work` — a single work id, e.g. `"T0026"`
    * `:covered_by` — only chunks a named human translator already renders, which is what
      a bake-off needs: it is the subset where a human rendering exists to blind the
      model arms against
    * `:limit` — how many chunks
    * `:lang` — target language, default `"en"`
  """
  @spec export(String.t(), keyword()) :: {:ok, map()}
  def export(path, opts \\ []) do
    lang = Keyword.get(opts, :lang, @default_lang)
    chunks = select_chunks(opts)

    bytes =
      File.open!(path, [:write, :utf8], fn handle ->
        Enum.reduce(chunks, 0, fn chunk, acc ->
          line =
            Jason.encode!(%{
              id: chunk.id,
              sha256: chunk.content_sha256,
              content: chunk.content,
              target_lang: lang
            }) <> "\n"

          IO.write(handle, line)
          acc + byte_size(line)
        end)
      end)

    {:ok, %{path: path, chunks: length(chunks), bytes: bytes, lang: lang}}
  end

  defp select_chunks(opts) do
    Chunk
    |> join(:inner, [c], t in Text, on: t.id == c.text_id)
    |> then(fn q ->
      if opts[:work], do: where(q, [_c, t], t.work_id == ^opts[:work]), else: q
    end)
    |> then(fn q -> if opts[:covered_by], do: covered_by(q, opts[:covered_by]), else: q end)
    |> order_by([c], asc: c.id)
    |> then(fn q -> if opts[:limit], do: limit(q, ^opts[:limit]), else: q end)
    |> select([c], %{id: c.id, content: c.content, content_sha256: c.content_sha256})
    |> Repo.all()
  end

  # Chunks that a named human translator already speaks for. The join is on the ordinal
  # span rather than on the anchor URN, for the reason `Translations.covering/2` gives:
  # a locator grammar belongs to its edition, and a rendering may be anchored to a line
  # or to a range. Both forms are matched here.
  defp covered_by(query, translator_id) do
    where(
      query,
      [c, t],
      fragment(
        """
        EXISTS (
          SELECT 1 FROM translations tr
          LEFT JOIN segments s ON s.urn = tr.anchor_urn
          WHERE tr.translator_id = ?
            AND tr.work_id = ?
            AND COALESCE((tr.meta ->> 'ordinal_start')::int, s.ordinal) <= ?
            AND COALESCE((tr.meta ->> 'ordinal_end')::int, s.ordinal) >= ?
        )
        """,
        ^translator_id,
        t.work_id,
        c.last_ordinal,
        c.first_ordinal
      )
    )
  end

  @doc """
  Reads renderings back and stores them as `t1` / `llm` translations.

  `translator_id` is supplied by the caller rather than derived from the model name,
  because it is the identity a reader sees beside the text and comparing two arms means
  holding both at once — `model:mitra` and `model:gemma-base` render the same anchors.

  A row whose `sha256` no longer matches the chunk it names is **rejected, not stored**.
  The passage may have been re-chunked between export and import, and a rendering of text
  that is no longer there would be attached to whatever now occupies that id.
  """
  @spec import(String.t(), String.t(), keyword()) :: {:ok, map()}
  def import(path, translator_id, opts \\ []) do
    lang = Keyword.get(opts, :lang, @default_lang)

    rows =
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.map(&Jason.decode!/1)

    chunks = chunk_index(Enum.map(rows, & &1["id"]))
    {ok, mismatched} = Enum.split_with(rows, &matches?(&1, chunks))
    {ok, empty} = Enum.split_with(ok, &(String.trim(&1["text"]) != ""))

    prepared = Enum.map(ok, &row(&1, Map.fetch!(chunks, &1["id"]), translator_id, lang))
    {:ok, written} = Translations.store(prepared)

    {:ok,
     %{
       read: length(rows),
       written: written,
       # PUBLISHED, not swallowed. A silent drop here is a tranche that was paid for and
       # is quietly smaller than the count says — rules 22, 44 and 54.
       mismatched: length(mismatched),
       empty: length(empty)
     }}
  end

  defp matches?(row, chunks) do
    case Map.fetch(chunks, row["id"]) do
      {:ok, chunk} -> chunk.content_sha256 == row["sha256"]
      :error -> false
    end
  end

  defp chunk_index(ids) do
    from(c in Chunk,
      join: t in Text,
      on: t.id == c.text_id,
      where: c.id in ^ids,
      select: %{
        id: c.id,
        urn: c.urn,
        work_id: t.work_id,
        content_sha256: c.content_sha256,
        first_ordinal: c.first_ordinal,
        last_ordinal: c.last_ordinal
      }
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp row(rendering, chunk, translator_id, lang) do
    %{
      anchor_urn: chunk.urn,
      work_id: chunk.work_id,
      lang: lang,
      translator_id: translator_id,
      translator_name: rendering["model"],
      # INVARIANT #8. Not `t0`, not `human`, and not negotiable: this is the field the
      # citation guard reads before it will let a quote be presented as canonical.
      tier: "t1",
      method: "llm",
      text: String.trim(rendering["text"]),
      model_id: rendering["model"],
      prompt_version: rendering["params_sha256"],
      bake_id: Bake.current_id(),
      review_state: "raw",
      # Generated FROM CBETA, whose terms are non-commercial, so the output inherits the
      # stricter of the two constraints rather than Gemma's permissive one. We do not
      # redistribute the corpus and do not redistribute this either.
      license_class: "nc",
      redistributable: false,
      meta: %{
        "ordinal_start" => chunk.first_ordinal,
        "ordinal_end" => chunk.last_ordinal,
        "revision" => rendering["revision"],
        "chunk_id" => chunk.id
      }
    }
  end
end
