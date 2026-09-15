defmodule Mix.Tasks.Pramana.Glossary.Dila do
  @shortdoc "Imports DILA's TEI glossaries — Soothill-Hodous, Karashima, Mahāvyutpatti"

  @moduledoc """
  The lexicon layer, from Dharma Drum's glossary project.

      mix pramana.glossary.dila                    # every glossary in the registry
      mix pramana.glossary.dila --only kumarajiva
      mix pramana.glossary.dila --dry-run

  Expects the TEI sources in `raw/dila-glossaries/`:

      curl -O https://glossaries.dila.edu.tw/data/soothill-hodous.ddbc.tei.p5.xml.zip
      curl -O https://glossaries.dila.edu.tw/data/kumarajiva.dila.tei.p5.xml.zip
      curl -O https://glossaries.dila.edu.tw/data/dharmaraksa.dila.tei.p5.xml.zip
      curl -O https://glossaries.dila.edu.tw/data/lokaksema.dila.tei.p5.xml.zip
      curl -O https://glossaries.dila.edu.tw/data/mahavyutpatti.dila.tei.p5.xml.zip

  ## Why these five

  `docs/PLAN.md` L1 called dictionaries "the largest functional gap", and the gap was
  never that we hold none — it is that the 56,382 entries we do hold are Tibetan-shaped.
  55,807 carry a Tibetan equivalent and *acalā* has seven of them and **not one with
  Chinese**. These five are the Chinese side, and they were chosen for accuracy rather
  than for reach:

    * **Soothill-Hodous** (16,792) — the standard Chinese→English Buddhist dictionary,
      1937, corrected by Charles Muller 2002-3. Dated, and sound on its translations.
    * **Karashima × 3** (2,409 · 3,356 · 1,607) — Kumārajīva's and Dharmarakṣa's Lotus
      and Lokakṣema's Aṣṭasāhasrikā. Not general dictionaries: glossaries of **one
      translator's** usage, which is what makes them worth more than their size.
    * **Mahāvyutpatti** (9,379) — Sanskrit-headed with Chinese *and* Tibetan equivalents,
      so it is a cross-canon bridge rather than a dictionary.

  ## Measured before it was built

  Seeded 200-headword samples, checked against the CBETA text this bake holds: Soothill-
  Hodous **187 of 199**, Karashima's Kumārajīva **190 of 199**, the Mahāvyutpatti's
  Chinese side **140 of 199**. The vocabulary is live in the corpus rather than
  lexicographers' cabinet.

  ## Scope is how a gloss stays honest

  A Karashima glossary is evidence about **one translator**, so its entries carry the
  `work_id` they describe — T0262 for Kumārajīva's Lotus, T0263 for Dharmarakṣa's, T0224
  for Lokakṣema's Aṣṭasāhasrikā. Soothill-Hodous and the Mahāvyutpatti carry none,
  because they claim to be general and a scope invented for them would be a lie about
  where they apply.

  That column is the answer to polysemy. 法 in Kumārajīva is "as a rule, normally" in one
  entry and a kiṃnara king's name in the next; both are stored, both are scoped to T0262,
  and neither is presented as what 法 means.

  ## Licence — CC BY-NC-SA 4.0, and the NC is load-bearing

  Stated by the glossary site. **The TEI header says only "Published on the Web with a
  Creative Commons License" without naming a version**, and a secondary source said
  BY-SA 3.0, so the site's statement is taken as binding and the restrictive reading is
  the one recorded — rule 10, and the direction it is safe to be wrong in.

  NonCommercial makes these `redistributable: false`, which is the same footing CBETA is
  already on: usable for everything this project does locally, and **excluded from the
  public artefact** by `mix pramana.public.bake` for the same reason CBETA is.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.DilaGlossary
  alias Pramana.Repo
  alias Pramana.Sources

  @switches [only: :string, dry_run: :boolean, root: :string]

  @default_root "raw/dila-glossaries"
  @source_id "dila-glossaries"

  # `work_id` is the SCOPE of the claim, not the file it came from. A Karashima glossary
  # describes one translator's usage in one work; a general dictionary describes nothing
  # in particular and gets `nil` rather than a plausible-looking guess.
  @glossaries [
    %{
      id: "shh",
      file: "ddbc.soothill-hodous.tei.p5.xml",
      shape: :soothill,
      work_id: nil,
      name: "Soothill-Hodous, A Dictionary of Chinese Buddhist Terms"
    },
    %{
      id: "kumarajiva",
      file: "kumarajiva.dila.tei.p5.xml",
      shape: :karashima,
      work_id: "T0262",
      name: "Karashima, Glossary of Kumārajīva's Lotus Sūtra"
    },
    %{
      id: "dharmaraksa",
      file: "dharmaraksa.dila.tei.p5.xml",
      shape: :karashima,
      work_id: "T0263",
      name: "Karashima, Glossary of Dharmarakṣa's Lotus Sūtra"
    },
    %{
      id: "lokaksema",
      file: "lokaksema.xml",
      shape: :karashima,
      work_id: "T0224",
      name: "Karashima, Glossary of Lokakṣema's Aṣṭasāhasrikā"
    },
    %{
      id: "mvy",
      file: "mahavyutpatti.dila.tei.p5.xml",
      shape: :mahavyutpatti,
      work_id: nil,
      name: "Mahāvyutpatti"
    }
  ]

  @doc "The glossaries this task knows how to read, with the scope each claim carries."
  @spec glossaries() :: [map()]
  def glossaries, do: @glossaries

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    root = Keyword.get_lazy(opts, :root, fn -> Pramana.Paths.data(@default_root) end)
    wanted = selected(opts[:only])

    unless File.dir?(root) do
      Mix.raise("no #{root} — download the TEI sources, see the moduledoc")
    end

    # The `sources` row must exist before any entry references it, and it must AGREE with
    # the registry — `Loader.ensure_source!/1` replaces on conflict, which is rule 9: a
    # table mirroring a declaration in code that is written once goes stale silently, and
    # `redistributable_only` filters by joining exactly this row.
    unless opts[:dry_run], do: Loader.ensure_source!(@source_id)

    tally = Enum.map(wanted, &ingest(&1, root, opts[:dry_run]))

    if opts[:dry_run] do
      report(tally, nil)
    else
      maybe_lock(root, opts)
      {:ok, bake} = Bake.record(%{"source" => @source_id, "mode" => "dila_glossary"})
      report(tally, bake)
    end
  end

  defp selected(nil), do: @glossaries

  defp selected(only) do
    ids = String.split(only, ",", trim: true)

    case Enum.filter(@glossaries, &(&1.id in ids)) do
      [] ->
        Mix.raise(
          "no such glossary: #{only}. Known: #{Enum.map_join(@glossaries, ", ", & &1.id)}"
        )

      found ->
        found
    end
  end

  defp ingest(glossary, root, dry_run?) do
    path = Path.join(root, glossary.file)

    unless File.exists?(path), do: Mix.raise("missing #{path} — see the moduledoc")

    entries =
      path
      |> File.read!()
      |> DilaGlossary.parse(glossary.shape, glossary.id)

    # AN ENTRY WITH NO GLOSS IN ANY LANGUAGE IS NOT AN ENTRY, and the schema says so:
    # `glossary_entry_has_a_term` requires one of sanskrit, tibetan or english. 276 of
    # Karashima's headwords are cross-references and variant spellings whose content is
    # elsewhere — 嘊喍, 輩, 阿波修天 — carrying a headword, no definition and no citations.
    #
    # They are DROPPED AND COUNTED rather than admitted by loosening the constraint. A
    # check that exists because an entry without a gloss is meaningless does not become
    # wrong when a new source produces some; the source does.
    {glossed, bare} =
      Enum.split_with(entries, &(&1.english || &1.sanskrit || &1.tibetan))

    rows = Enum.map(glossed, &row(&1, glossary, path))
    written = if dry_run?, do: 0, else: store(rows)

    Map.merge(glossary, %{
      parsed: length(entries),
      bare: length(bare),
      written: written,
      attested: Enum.count(glossed, &(&1.chinese_attestation == "source")),
      citations: glossed |> Enum.map(&length(&1.citations)) |> Enum.sum()
    })
  end

  defp row(entry, glossary, path) do
    now = DateTime.utc_now()

    %{
      source_id: @source_id,
      work_id: glossary.work_id,
      gloss_id: entry.gloss_id,
      english: entry.english,
      english_alternatives: [],
      sanskrit: entry.sanskrit,
      sanskrit_attestation: if(entry.sanskrit, do: entry.chinese_attestation),
      tibetan: entry.tibetan,
      wylie: nil,
      tibetan_attestation: if(entry.tibetan, do: "source"),
      chinese: entry.chinese,
      chinese_attestation: entry.chinese_attestation,
      pali: nil,
      definition: entry.definition,
      meta: %{
        "glossary" => glossary.id,
        "glossary_name" => glossary.name,
        "source_file" => path,
        "pinyin" => entry.pinyin,
        # The Taishō addresses this gloss rests on, as the edition prints them. Anchoring
        # them to URNs is a separate step and a separate claim; keeping them is what makes
        # that step possible at all.
        "citations" => entry.citations
      },
      inserted_at: now,
      updated_at: now
    }
  end

  defp store([]), do: 0

  defp store(rows) do
    rows
    |> Enum.chunk_every(2_000)
    |> Enum.reduce(0, fn batch, acc ->
      {n, _} =
        Repo.insert_all(GlossaryEntry, batch,
          on_conflict:
            {:replace,
             [
               :work_id,
               :english,
               :sanskrit,
               :sanskrit_attestation,
               :tibetan,
               :tibetan_attestation,
               :chinese,
               :chinese_attestation,
               :definition,
               :meta,
               :updated_at
             ]},
          conflict_target: [:source_id, :gloss_id]
        )

      acc + n
    end)
  end

  defp maybe_lock(root, opts) do
    if opts[:only] do
      Mix.shell().info("  (--only run: sources.lock.json left alone)")
    else
      files =
        @glossaries
        |> Enum.map(fn g ->
          bytes = File.read!(Path.join(root, g.file))
          %{path: g.file, sha256: Lockfile.sha256(bytes), bytes: byte_size(bytes)}
        end)

      Lockfile.build_entry(Sources.fetch!(@source_id),
        files: files,
        pin: %{"type" => "content", "files_sha256" => Lockfile.manifest_hash(files)}
      )
      |> Lockfile.put_source()

      :ok
    end
  end

  defp report(tally, bake) do
    for g <- tally do
      Mix.shell().info(
        "  #{String.pad_trailing(g.id, 12)} #{g.parsed} parsed, #{g.written} written, " <>
          "#{g.bare} with no gloss (dropped), #{g.attested} source-attested, " <>
          "#{g.citations} Taishō citation(s)" <>
          if(g.work_id, do: " — scoped to #{g.work_id}", else: "")
      )
    end

    held = Repo.aggregate(from(e in GlossaryEntry, where: e.source_id == ^@source_id), :count)

    Mix.shell().info("""

    DILA glossaries
      entries for this source: #{held}
      bake:                    #{(bake && bake.id) || "not recorded (dry run)"}
    """)
  end
end
