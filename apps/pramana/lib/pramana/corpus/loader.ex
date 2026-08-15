defmodule Pramana.Corpus.Loader do
  @moduledoc """
  Persists a normalized `IR` into the corpus tables.

  Idempotent by design: loading the same text twice replaces its segments rather than
  duplicating them, so a partially-failed bake can simply be re-run
  (`CLAUDE.md`, working conventions).
  """

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Normalize.IR
  alias Pramana.Repo
  alias Pramana.Segment.Taisho
  alias Pramana.Sources

  @doc """
  Loads one normalized text and its segments.

  `provenance` supplies the work-level axes. They are passed in rather than inferred
  because for Taishō vols 1–55 and 85 the origin and role are catalogue data, and
  guessing them would be worse than leaving them null — a wrong provenance label is
  the failure this project exists to prevent.
  """
  @spec load(IR.t(), keyword()) :: {:ok, %{text: Text.t(), segments: non_neg_integer()}}
  def load(%IR{} = ir, opts) do
    source_id = Keyword.fetch!(opts, :source)
    witness_id = Keyword.fetch!(opts, :witness)
    provenance = Keyword.get(opts, :provenance, %{})

    Repo.transaction(fn ->
      ensure_source!(source_id, Keyword.get(opts, :source_definition))
      ensure_witness!(witness_id)
      segmenter = Keyword.get(opts, :segmenter, Taisho)
      work = upsert_work!(ir, provenance)

      text =
        upsert_text!(
          ir,
          work,
          witness_id,
          source_id,
          Keyword.get(opts, :addressing),
          Keyword.get(opts, :source_file)
        )

      count = replace_segments!(ir, text, source_id, witness_id, segmenter)

      %{text: text, segments: count}
    end)
  end

  # A local text's definition comes from its manifest: local sources are open-ended by
  # design and cannot live in the static registry.
  defp ensure_source!(source_id, nil) do
    {:ok, definition} = Sources.fetch(source_id)
    insert_source!(definition)
  end

  defp ensure_source!(_source_id, definition), do: insert_source!(definition)

  defp insert_source!(definition) do
    Repo.insert!(
      %Source{
        id: definition.id,
        name: definition.name,
        upstream_url: definition.upstream_url,
        license_spdx: definition.license.spdx,
        license_class: definition.license.class,
        commercial_use: definition.license.commercial_use,
        redistributable: definition.license.redistributable
      },
      # `Pramana.Sources` (or a local manifest) is the authority on licensing, so the row
      # must follow it. With `:nothing`, correcting bilara-data's licence from CC0 to
      # Public Domain Mark in code left the database still saying `cc0` through a full
      # re-ingest — the licence a query would have filtered on was the one we had already
      # established was wrong.
      on_conflict:
        {:replace,
         [
           :name,
           :upstream_url,
           :license_spdx,
           :license_class,
           :commercial_use,
           :redistributable,
           :updated_at
         ]},
      conflict_target: :id
    )
  end

  defp ensure_witness!("T" = id) do
    Repo.insert!(
      %Witness{id: id, name: "Taishō Shinshū Daizōkyō 大正新脩大藏經"},
      on_conflict: :nothing,
      conflict_target: :id
    )
  end

  defp ensure_witness!("ms" = id) do
    Repo.insert!(
      %Witness{id: id, name: "Mahāsaṅgīti Tipiṭaka Buddhavasse 2500"},
      on_conflict: :nothing,
      conflict_target: :id
    )
  end

  defp ensure_witness!(id) do
    Repo.insert!(%Witness{id: id, name: id}, on_conflict: :nothing, conflict_target: :id)
  end

  defp upsert_work!(ir, provenance) do
    attrs = %{
      id: ir.work_id,
      title: ir.title,
      title_original: ir.title_original,
      attributed_author: ir.author,
      composition_origin: provenance[:composition_origin],
      text_role: provenance[:text_role],
      division: provenance[:division],
      division_en: provenance[:division_en],
      attribution_confidence: provenance[:attribution_confidence],
      date_start: provenance[:date_start],
      date_end: provenance[:date_end],
      meta: %{"juan_count" => ir.juan_count, "canon" => ir.canon}
    }

    Repo.insert!(struct(Work, attrs),
      on_conflict:
        {:replace,
         [
           :title,
           :title_original,
           :attributed_author,
           :composition_origin,
           :text_role,
           :division,
           :division_en,
           :meta,
           :updated_at
         ]},
      conflict_target: :id
    )
  end

  defp upsert_text!(ir, work, witness_id, source_id, addressing, source_file) do
    body = IR.body(ir)
    prefix = Taisho.urn_prefix(source_id, witness_id, ir.work_id)

    Repo.insert!(
      %Text{
        work_id: work.id,
        witness_id: witness_id,
        source_id: source_id,
        urn_prefix: prefix,
        volume: ir.volume && Integer.to_string(ir.volume),
        body: body,
        body_sha256: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower),
        meta: %{
          "license_notice" => ir.license_notice,
          "gaiji_declared" => map_size(ir.gaiji),
          "unanchored_apparatus" => length(ir.unanchored_apparatus),
          # DECLARED by the source, not inferred from its id. Inferring it threw away
          # the distinction between a text anchored to printed page numbers and one
          # with no intrinsic anchor at all, reporting the weaker claim for both.
          "addressing" => addressing,
          # Which upstream file this text came from. A source whose works do not map
          # one-to-one onto files (bilara packs several suttas per file) cannot be
          # re-derived without it, and `mix pramana.verify` must be able to re-derive
          # every text or it is not checking anything.
          "source_file" => source_file
        },
        outline: %{"entries" => Enum.map(ir.outline, &stringify_entry/1)}
      },
      on_conflict:
        {:replace, [:body, :body_sha256, :urn_prefix, :volume, :meta, :outline, :updated_at]},
      conflict_target: [:work_id, :witness_id, :source_id],
      returning: true
    )
  end

  # jsonb wants string keys; doing it here keeps the IR clean of storage concerns.
  defp stringify_entry(entry) do
    %{
      "level" => entry.level,
      "n" => entry.n,
      "type" => entry.type,
      "title" => entry.title,
      "anchor" => entry.anchor,
      "juan" => entry.juan
    }
  end

  defp replace_segments!(ir, text, source_id, witness_id, segmenter) do
    Repo.delete_all(from s in Segment, where: s.text_id == ^text.id)

    {:ok, segments} = segmenter.segments(ir, source: source_id, witness: witness_id)
    now = DateTime.utc_now()

    rows =
      Enum.map(segments, fn seg ->
        seg
        |> Map.put(:text_id, text.id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    # Chunked because Postgres caps bound parameters at 65535 per statement. Segments
    # have 17 columns, so 2,000 rows is ~34k parameters — comfortably under, and half
    # as many round trips inside the transaction as 1,000 was.
    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(&Repo.insert_all(Segment, &1))

    length(rows)
  end
end
