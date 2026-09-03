defmodule Mix.Tasks.Pramana.Doctor do
  @shortdoc "Prints the state a session otherwise rediscovers with hand-written SQL"

  @moduledoc """
  What is true about this checkout, right now, in one command.

      mix pramana.doctor

  Not a monitoring system and not a health check that passes or fails. It is the answer to
  the questions every session opens with — *which bake is this, what is loaded, what is
  acquired, what is missing* — which were being answered by hand-written `psql` several
  times a day. `docs/OBSERVABILITY.md` records the audit that produced it.

  ## Everything here is computed

  No figure in this task is written down anywhere, which is the rule that the rest of this
  project's documentation follows and the reason a stale number cannot survive here.
  `Pramana.Inventory.snapshot/0` supplies most of it, so the reader's `/inventory` page and
  this command cannot disagree.

  ## The one thing it checks rather than reports

  **Whether the recorded `bake_id` still describes its inputs.** Acquisition rewrites
  `sources.lock.json` and only a bake writes the row, so between the two every response is
  stamped for a corpus that no longer exists. That was true for weeks and nothing noticed;
  it is a gate step now (rule 64) and it is the first line here, because it invalidates
  everything printed below it.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Coverage
  alias Pramana.Repo
  alias Pramana.Retrieval.Semantic
  alias Pramana.Sources

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    bake()
    corpus()
    sources()
    gaps()
    derivations()
    stranded()
    reference()
    migrations()

    Mix.shell().info("")
  end

  defp bake do
    heading("bake")

    case Bake.current() do
      nil ->
        warn("no bake recorded — run `mix pramana.bake`")

      recorded ->
        row("id", String.slice(recorded.id, 0, 16))
        row("pipeline_version", recorded.pipeline_version)
        row("config", inspect(recorded.config))
        row("built", to_string(recorded.built_at))

        case Bake.bake_id(recorded.config) do
          {:ok, id, _} when id == recorded.id ->
            ok("matches its inputs")

          {:ok, id, _} ->
            warn(
              "DIVERGED — these inputs give #{String.slice(id, 0, 16)}. " <>
                "sources.lock.json changed since the bake was recorded, so every response " <>
                "is stamped for a corpus that no longer exists."
            )

          {:error, reason} ->
            warn("could not recompute: #{inspect(reason)}")
        end
    end
  end

  # COUNTS, not `Inventory.snapshot/0`. That function sums `length(body)` across 548 million
  # characters, which makes Postgres detoast every text: 9.8 s of the 10 s this command used
  # to take, against ~300 ms for every coverage figure combined. The character total is read
  # from the recorded bake instead, where it was computed once.
  #
  # The same cost is paid by the reader's `/inventory` page on every load — recorded in
  # `docs/OBSERVABILITY.md`, because the fix is a stored column rather than something to
  # work around twice.
  defp corpus do
    heading("corpus")

    row("texts", Repo.aggregate(from(t in "texts"), :count))
    row("segments", Repo.aggregate(from(s in "segments"), :count))
    row("works", Repo.aggregate(from(w in "works"), :count))

    case Bake.current() do
      %{stats: %{"chars" => chars}} -> row("chars", "#{chars} (as recorded at bake time)")
      _ -> :ok
    end

    counts =
      Repo.all(
        from t in "texts",
          group_by: [t.source_id, t.witness_id],
          select: {t.source_id, t.witness_id, count(t.id)},
          order_by: [desc: count(t.id)]
      )

    for {source, witness, n} <- Enum.take(counts, 12) do
      row("  #{source} / #{witness}", n)
    end

    if length(counts) > 12, do: row("  …", "#{length(counts) - 12} more")
  end

  # EVERY source, not the ones that happen to be loaded. A source declared and never
  # acquired is a normal state — SAT has been one for phases — and it is also exactly what a
  # session needs to know before wondering why a search returns nothing.
  # READS the lockfile; does not re-hash `raw/`. Verifying every recorded file means hashing
  # roughly eighteen thousand of them, which took 13 s — too slow for the command a session
  # opens with, and duplicated work besides: the gate's `lockfile` step verifies on every
  # run. A status command that people skip because it is slow reports nothing.
  defp sources do
    heading("sources")

    for id <- Enum.sort(Sources.ids()) do
      case Lockfile.get_source(id) do
        {:ok, entry} ->
          pin = get_in(entry, ["pin", "commit"]) || get_in(entry, ["pin", "edition"]) || "—"
          row(id, "#{entry["file_count"]} file(s) @ #{String.slice(to_string(pin), 0, 12)}")

        {:error, :not_locked} ->
          row(id, "declared, never acquired")
      end
    end

    Mix.shell().info("    (hashes are checked by the gate's lockfile step, not here)")
  end

  # THE GAPS, not the totals. A five-figure text count is impressive and uninformative;
  # which collections are absent decides whether this corpus can answer your question.
  defp gaps do
    heading("what is missing")

    row("embedding", embedding(Semantic.coverage()))
    row("taishō", note_of(Coverage.taisho()))
    row("cbeta collections", note_of(Coverage.cbeta()))
    row("text_role", note_of(Coverage.roles()))
    row("parallels", note_of(Coverage.parallels()))

    dated = Coverage.dated()
    row("dates", "#{dated.dated} of #{dated.works} works; #{dated.authority_linked} linked")
  end

  # HOW FAR EACH DERIVATION HAS GOT, against what it could reach.
  #
  # `gaps/0` above asks what has not been ACQUIRED. This asks whether the things the
  # corpus derives FROM what it holds have finished — and it exists because that question
  # was misread four times on 2026-09-02, every time by checking a value instead of the
  # work. "24 commentaries aligned" reads as a quarter of 89 relations until you know the
  # 43 pairs above the floor collapse to 24 works, at which point it is complete.
  #
  # A count without its denominator invites exactly that misreading, which is rules 22, 44
  # and 54 — applied here to a derivation rather than to a coverage figure.
  defp derivations do
    heading("what has been derived")

    Enum.each(Coverage.derivations(), fn d ->
      pct = if d.eligible > 0, do: Float.round(100 * d.done / d.eligible, 1), else: 0.0
      row(d.what, "#{d.done} of #{d.eligible} #{d.unit} (#{pct}%)")
      row("", d.note)
    end)
  end

  # DATA THAT IS HELD AND CANNOT BE REACHED.
  #
  # The failure this exists for: 2,675 Tengyur works had their title extracted at ingest
  # and written into `works.meta`, while `works.title` — the column `get_outline` and
  # `search` read — stayed null. Every count said the corpus was healthy, and the whole
  # *pramāṇa* literature was nameless to a reader. Worse, `count(title) = 0` invited
  # writing a parser for text that was already parsed.
  #
  # So this asks a different question from `gaps/0`. That one asks what has not been
  # acquired; this asks what has been acquired, derived, and then left somewhere nothing
  # queries. A row here is not a missing ingest — it is a promotion nobody ran.
  defp stranded do
    heading("held but unreachable")

    case Coverage.stranded() do
      [] ->
        ok("nothing stranded — every derived field is in the column that is read")

      rows ->
        Enum.each(rows, fn r ->
          warn("#{r.count} #{r.what}")
          row("", r.fix)
        end)
    end
  end

  # `Coverage.caveat/0` is deliberately NOT printed here: it is the taishō and collection
  # notes concatenated, both of which are two lines above. A summary that repeats what the
  # detail already said is how people learn to skim past the detail.
  defp embedding(%{total: total, embedded: embedded, percent: percent}),
    do: "#{embedded} of #{total} chunks (#{percent}%)"

  # No catch-all: `Semantic.coverage/0` always returns these keys, and dialyzer refuses a
  # clause that cannot be reached. A defensive fallback here would be dead code pretending
  # to be caution.

  defp reference do
    heading("reference data")

    for {table, label} <- [
          {"authority_people", "people"},
          {"authority_places", "places"},
          {"authority_relations", "relations"}
        ] do
      row(label, Repo.aggregate(from(t in table), :count))
    end
  end

  defp migrations do
    heading("migrations")

    case Ecto.Migrator.migrations(Repo) do
      [] ->
        row("status", "none found")

      all ->
        pending = Enum.count(all, fn {status, _, _} -> status == :down end)

        if pending == 0,
          do: ok("#{length(all)} applied, none pending"),
          else: warn("#{pending} migration(s) PENDING — run `mix ecto.migrate`")
    end
  end

  # Every coverage map carries a `note`; it is nil only where a gap does not apply.
  defp note_of(%{note: note}) when is_binary(note), do: note
  defp note_of(map) when is_map(map), do: inspect(Map.drop(map, [:note]), limit: 6)

  defp heading(text), do: Mix.shell().info(["\n  ", :bright, text, :reset])
  defp row(label, value), do: Mix.shell().info("    #{String.pad_trailing(label, 26)} #{value}")
  defp ok(text), do: Mix.shell().info(["    ", :green, text, :reset])
  defp warn(text), do: Mix.shell().info(["    ", :yellow, text, :reset])
end
