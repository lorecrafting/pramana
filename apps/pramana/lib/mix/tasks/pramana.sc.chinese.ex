defmodule Mix.Tasks.Pramana.Sc.Chinese do
  @shortdoc "Ingests bilara-data's English of the Chinese Āgamas as renderings of CBETA"

  @moduledoc """
  Gives the Chinese canon its first English layer.

      mix pramana.sc.chinese                 # align and ingest
      mix pramana.sc.chinese --dry-run       # report the alignment, write nothing
      mix pramana.sc.chinese --limit 5

  Expects the sparse checkout extended a third time:

      cd raw/sc/bilara-data && git sparse-checkout set root/pli/ms translation/en root/lzh/sct

  ## What this closes

  `docs/PLAN.md` § E1: 4,263 CBETA works held **zero** English renderings while the Pāli
  held 5,845 and the Kangyur 472, and that one fact was the whole of `topical/chinese`
  scoring 0%. `mix pramana.recall --renderings` puts English→Pāli and English→Tibetan
  at 93.8% *because* there are 241,409 human renderings to reach them through. There
  were none at all over Chinese.

  Part of the answer was already on disk. Charles Patton's CC0 translations of the
  Chinese Saṃyukta and Madhyama Āgamas have been in the `sc-translations` lockfile
  entry since #39 — 54 files, counted, hashed, and **discarded at ingest**, because
  their anchors (`sa379:2.2`) named SuttaCentral addresses and this corpus holds those
  Āgamas as CBETA. `mix pramana.sc.translations` filed every one of them under
  `no_such_anchor`, which is also where the Pāli's legitimate elisions land, so the loss
  looked like normal noise.

  ## What it does NOT close, measured

  **3,354 renderings over 54 sūtras — 2 of 4,263 CBETA works — and `topical/chinese`
  stayed at 0 of 12.** Those cases search the whole corpus, where 191 English vectors over
  the Chinese meet 55,135 over the Pāli and lose every time. Isolated from that,
  `mix pramana.recall --renderings --to cbeta.T` scores 63.0% work-level and **37.0% on
  the line**, against `--to sc.ms` at 89.0% and 79.0%.

  So this is the pipeline and the first non-zero, not the coverage. Anything built on top
  of it needs to reach a substantial fraction of 4,263 works or it will land here too —
  `docs/PLAN.md` § E1 records the two routes that could.

  ## The renderings anchor to the Taishō, not to a second Chinese text

  `Pramana.Sc.Lzh` does the joining, and its moduledoc argues the design: bilara's own
  Chinese is used as a **bridge and never stored**, so an English reader who follows one
  of these citations arrives at a Taishō page-and-line address they can check against a
  print edition. Loading bilara's Chinese as a second witness would have been less work
  and would have pointed every reader at our own convenience copy.

  Each rendering records how its anchor was found — `anchor_method: "exact"` where the
  two editions' text matched, `"interpolated"` where it is bounded by neighbours that
  did. Both are honest anchors; they are not the same claim, so they are not stored as
  though they were.

  ## Licence, per publication as always

  The translations are `scpub20` (Saṃyukta) and `scpub35` (Madhyama), both CC0, both
  published. Resolution goes through `Mix.Tasks.Pramana.Sc.Translations.publication_for/3`
  rather than a second copy of that logic — it is public precisely because it decides a
  licensing question, and rule 41 is what a second copy earns.

  ## Two SuttaCentral segments can land on one Taishō line

  SuttaCentral segments a sentence at a time; the Taishō breaks at 17 characters. Where
  several renderings fall on one line they are **joined in order**, not stored twice: the
  pool is unique on `{anchor_urn, lang, translator_id}`, so storing them separately would
  silently keep whichever arrived last, and Postgres rejects the batch outright when the
  duplicate is inside one insert.
  """

  use Mix.Task

  import Ecto.Query

  alias Mix.Tasks.Pramana.Sc.Translations, as: ScTranslations
  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Corpus.Text
  alias Pramana.Repo
  alias Pramana.Sc.Lzh
  alias Pramana.Sources
  alias Pramana.Translations
  alias Pramana.URN

  @switches [limit: :integer, dry_run: :boolean, root: :string, translator: :string]

  @default_root "raw/sc/bilara-data"
  @source_id "sc-lzh"
  @lang "en"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    root = Keyword.get(opts, :root, @default_root)

    unless File.dir?(Path.join(root, "root/lzh")) do
      Mix.raise("no root/lzh under #{root} — widen the sparse checkout, see the moduledoc")
    end

    {anchors, alignment} = Lzh.anchors(root: root)
    Mix.shell().info(alignment_report(alignment))

    files = files(root, anchors, opts)

    if files == [] do
      Mix.raise("no English translations over an anchored Chinese work under #{root}")
    end

    Mix.shell().info("#{if opts[:dry_run], do: "DRY RUN — ", else: ""}#{length(files)} file(s)")

    publications = ScTranslations.publications(root)
    works = known_works()

    {rows, skipped} =
      Enum.reduce(files, {[], %{}}, fn file, acc ->
        collect(file, root, anchors, publications, works, acc)
      end)

    bake =
      unless opts[:dry_run] do
        maybe_lock(root, opts)
        # THE LOCKFILE AND THE BAKE ID MOVE TOGETHER. `bake_id` is a hash of
        # `sources.lock.json`, so registering `sc-lzh` changes it, and a bake row that no
        # longer describes its inputs means every API response is stamped with an id for a
        # corpus that does not exist. `mix pramana.gate`'s lockfile step caught exactly
        # that here. `Bake.record/1` is cheap — it writes a row, it does not re-bake, and
        # nothing this task does changes a single `texts` or `segments` row.
        {:ok, bake} = Bake.record(%{"source" => @source_id, "mode" => "sc_chinese"})
        bake
      end

    report(rows, skipped, alignment, bake, opts[:dry_run])
  end

  # Every English file whose work this corpus can anchor. Driven by the ANCHORS rather
  # than by a hard-coded list of translators: the day someone publishes an English
  # Dīrgha Āgama in bilara, adding `da` to `Pramana.Sc.Lzh.collections/0` is the whole
  # change, and a translator named here would have been the thing forgotten.
  defp files(root, anchors, opts) do
    anchored = anchors |> Map.keys() |> MapSet.new(&uid_of_segment/1)
    translator = Keyword.get(opts, :translator, "*")

    root
    |> Path.join("translation/#{@lang}/#{translator}/**/*.json")
    |> Path.wildcard()
    |> Enum.filter(&MapSet.member?(anchored, Lzh.uid_of(&1)))
    |> Enum.sort()
    |> then(fn all -> if opts[:limit], do: Enum.take(all, opts[:limit]), else: all end)
  end

  defp uid_of_segment(segment_id), do: segment_id |> String.split(":", parts: 2) |> hd()

  defp known_works do
    from(t in Text, where: t.source_id == "cbeta", select: t.work_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp collect(file, root, anchors, publications, works, {rows, skipped}) do
    {lang, translator} = attribution(file, root)
    uid = Lzh.uid_of(file)
    work = work_id(uid)

    license =
      publications
      |> Map.get({lang, translator}, [])
      |> ScTranslations.publication_for(uid, Path.relative_to(file, root))
      |> ScTranslations.license()

    {placed, misses} =
      file
      |> File.read!()
      |> Jason.decode!()
      |> Enum.reduce({%{}, %{}}, fn {segment_id, text}, {acc, misses} ->
        text = String.trim(text)

        cond do
          text == "" ->
            {acc, misses}

          not MapSet.member?(works, work) ->
            {acc, bump(misses, :no_such_work)}

          # A segment bilara translates that the alignment could not place. These are
          # the headings — `sa379:0.1` is "Connected Discourses 379", the translation's
          # own furniture — and the handful the two editions disagree on too sharply to
          # bound. Dropped rather than given an invented address.
          not Map.has_key?(anchors, segment_id) ->
            {acc, bump(misses, :no_such_anchor)}

          true ->
            {merge(acc, Map.fetch!(anchors, segment_id), segment_id, text), misses}
        end
      end)

    new_rows =
      Enum.map(placed, fn {_urn, group} ->
        row(group, work, lang, translator, license, file, root)
      end)

    {new_rows ++ rows, merge_skips(skipped, {lang, translator}, misses)}
  end

  # Renderings that share a Taishō line are one row, in segment order.
  defp merge(placed, anchor, segment_id, text) do
    Map.update(
      placed,
      anchor.urn,
      %{anchor: anchor, parts: [{segment_id, text}]},
      fn existing -> %{existing | parts: [{segment_id, text} | existing.parts]} end
    )
  end

  defp row(%{anchor: anchor, parts: parts}, work, lang, translator, license, file, root) do
    parts = Enum.sort_by(parts, fn {id, _} -> sort_key(id) end)

    %{
      anchor_urn: anchor.urn,
      work_id: work,
      lang: lang,
      translator_id: translator,
      translator_name: license.author_name,
      tier: "t0",
      method: "human",
      text: parts |> Enum.map_join(" ", fn {_id, text} -> text end) |> String.trim(),
      review_state: "approved",
      license_spdx: license.spdx,
      license_class: license.class,
      redistributable: license.redistributable,
      attribution: license.attribution,
      source_file: Path.relative_to(file, File.cwd!()),
      meta:
        ordinals(anchor, %{
          "publication" => license.publication_id,
          "root" => root,
          "license_confidence" => license.confidence,
          # Which of the two editions' agreement placed this. A reader comparing an
          # English line against the Taishō page is entitled to know whether we matched
          # the Chinese or bounded it.
          "anchor_method" => Atom.to_string(anchor.method),
          "sc_segments" => Enum.map(parts, fn {id, _} -> id end)
        })
    }
  end

  # `Pramana.Chunk.Vectors.range_renderings/2` treats ANY rendering carrying
  # `ordinal_start` as range-anchored, and `point_renderings/2` finds the same row by
  # URN equality. A point anchor carrying ordinals would therefore be embedded twice.
  # So the ordinals go on range anchors only — which are the ones that need them, since
  # no equality join can find a range.
  defp ordinals(anchor, meta) do
    if URN.range?(URN.parse!(anchor.urn)) do
      Map.merge(meta, %{
        "ordinal_start" => anchor.ordinal_start,
        "ordinal_end" => anchor.ordinal_end
      })
    else
      meta
    end
  end

  defp work_id(uid) do
    prefix = uid |> String.replace(~r/\d+$/, "")
    Map.fetch!(Lzh.collections(), prefix)
  end

  defp sort_key(segment_id) do
    segment_id
    |> String.split(":", parts: 2)
    |> List.last()
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  rescue
    ArgumentError -> [0]
  end

  defp attribution(file, root) do
    case file |> Path.relative_to(root) |> Path.split() do
      ["translation", lang, translator | _] -> {lang, translator}
      _ -> {"und", "unknown"}
    end
  end

  defp bump(counts, key), do: Map.update(counts, key, 1, &(&1 + 1))

  defp merge_skips(skipped, _key, misses) when misses == %{}, do: skipped

  defp merge_skips(skipped, key, misses) do
    Map.update(skipped, key, misses, fn existing ->
      Map.merge(existing, misses, fn _k, a, b -> a + b end)
    end)
  end

  # The bridge is a raw input to this ingest, so it is pinned like any other. It is its
  # own entry rather than joining `sc` or `sc-translations` for the reason those two are
  # separate: one sparse checkout of bilara-data, now four publications, and an entry
  # states one licence.
  defp maybe_lock(root, opts) do
    if opts[:limit] || opts[:translator] do
      Mix.shell().info("  (filtered run: sources.lock.json left alone)")
    else
      files =
        root
        |> Path.join("root/lzh/**/*.json")
        |> Path.wildcard()
        |> Enum.sort()
        |> Enum.map(fn path ->
          bytes = File.read!(path)

          %{
            path: Path.relative_to(path, root),
            sha256: Lockfile.sha256(bytes),
            bytes: byte_size(bytes)
          }
        end)

      Lockfile.build_entry(Sources.fetch!(@source_id),
        files: files,
        raw_root: "sc/bilara-data",
        pin: %{"type" => "git", "commit" => commit(root), "sparse" => "root/lzh"}
      )
      |> Lockfile.put_source()

      :ok
    end
  end

  defp commit(root) do
    case System.cmd("git", ["-C", root, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end

  defp alignment_report(alignment) do
    placeable = alignment.works_seen - alignment.unsupported
    anchored = alignment.exact + alignment.interpolated

    """

    aligned bilara's Chinese against CBETA
      works placed:        #{alignment.works_placed} of #{placeable} in a supported collection\
    #{if alignment.unsupported > 0, do: " (#{alignment.unsupported} of #{alignment.works_seen} in collections with no anchoring)", else: ""}
      anchors exact:       #{alignment.exact}#{percent(alignment.exact, anchored)}
      anchors interpolated:#{alignment.interpolated}#{percent(alignment.interpolated, anchored)}
      segments dropped:    #{alignment.dropped}
      failures:            #{inspect(alignment.failures)}
    """
  end

  defp percent(_part, 0), do: ""
  defp percent(part, whole), do: " (#{Float.round(part * 100 / whole, 1)}%)"

  defp report(rows, skipped, alignment, bake, dry_run?) do
    written =
      if dry_run? do
        0
      else
        {:ok, n} = Translations.store(rows)
        n
      end

    Mix.shell().info("""

    ingested English over the Chinese canon
      renderings prepared: #{length(rows)}
      written:             #{written}
      anchors available:   #{alignment.exact + alignment.interpolated}
      by licence:          #{inspect(licenses(rows))}
      bake:                #{(bake && bake.id) || "not recorded (dry run)"}
    """)

    for {{lang, translator}, counts} <- skipped do
      Mix.shell().info(
        "  #{lang}/#{translator}: #{Map.get(counts, :no_such_anchor, 0)} segment(s) with no " <>
          "anchor (headings, and text the two editions place differently), " <>
          "#{Map.get(counts, :no_such_work, 0)} in works we hold nothing of"
      )
    end
  end

  defp licenses(rows) do
    Enum.frequencies_by(rows, & &1.license_class)
  end
end
