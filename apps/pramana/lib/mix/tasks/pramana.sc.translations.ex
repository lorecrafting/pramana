defmodule Mix.Tasks.Pramana.Sc.Translations do
  @shortdoc "Ingests bilara-data translations into the translation pool"

  @moduledoc """
  Loads SuttaCentral's segment-aligned translations as T0 (human) renderings.

      mix pramana.sc.translations                  # every language in the checkout
      mix pramana.sc.translations --lang en        # one language
      mix pramana.sc.translations --translator sujato
      mix pramana.sc.translations --limit 50 --dry-run

  Expects the sparse checkout extended:

      cd raw/sc/bilara-data && git sparse-checkout set root/pli/ms translation/en

  ## Why this is the right first content for the pool

  bilara-data is aligned segment-by-segment against the root text, so a translation row
  keys directly onto an existing anchor: `mn1:1.1` in Sujato's file renders
  `pramana:sc.ms:mn1@1.1`. No alignment step, no guessing. And it is natively
  multi-translator — Sujato, Brahmali, Patton and others on overlapping suttas — which
  is exactly the condition the selection policy exists for. A pool with one translator in
  it would not have exercised anything.

  ## Licence per publication, again

  `_publication.json` gives each publication its own licence. 139 are CC0; **one is
  CC BY-SA 3.0** (Anandajoti's Patna Dhammapada, `scpub69`), which carries attribution
  and share-alike obligations CC0 does not. The licence is resolved per file from
  `(language, author)` and stored on the row, so a rendering can never inherit a
  neighbouring publication's terms. A file whose publication cannot be identified is
  recorded as `unknown` and **not redistributable** — the safe direction to be wrong in.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Segment
  alias Pramana.Repo
  alias Pramana.Sources
  alias Pramana.Translations

  import Ecto.Query

  @switches [
    lang: :string,
    translator: :string,
    limit: :integer,
    dry_run: :boolean,
    root: :string
  ]

  @default_root "raw/sc/bilara-data"
  @source_id "sc"
  @witness "ms"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    root = Keyword.get(opts, :root, @default_root)
    publications = publications(root)
    files = files(root, opts)

    if files == [],
      do: Mix.raise("no translation files under #{root}/translation — see moduledoc")

    Mix.shell().info("#{if opts[:dry_run], do: "DRY RUN — ", else: ""}#{length(files)} file(s)")

    anchors = known_anchors()
    works = known_works()
    Mix.shell().info("#{map_size(anchors)} source anchors to key against")

    {rows, skipped} =
      Enum.reduce(files, {[], %{}}, fn file, acc ->
        collect(file, root, publications, {anchors, works}, acc)
      end)

    unless opts[:dry_run], do: maybe_lock(root, files, opts)

    report(rows, skipped, publications, opts[:dry_run])
  end

  # Translations get their own lockfile entry rather than joining the root text's. They
  # are a distinct body of content with distinct terms — CC0 for most publications, CC
  # BY-SA 3.0 for one — from the same repository and commit, and two mix tasks writing
  # one entry would each overwrite the other's file list.
  #
  # A filtered run does not write a lock at all: `--limit 1` once rewrote the `sc` entry
  # to claim a one-file corpus, and a pin that describes less than what was ingested is
  # worse than none, because it would verify.
  defp maybe_lock(root, files, opts) do
    if opts[:limit] || opts[:lang] || opts[:translator] do
      Mix.shell().info("  (filtered run: sources.lock.json left alone)")
    else
      :ok = write_lock(root, files)
    end
  end

  # Named `write_lock` rather than `lock`: `import Ecto.Query` puts its own `lock/2` in
  # scope, and the clash is a compile error rather than anything subtle.
  defp write_lock(root, files) do
    entries =
      Enum.map(files, fn file ->
        bytes = File.read!(file)

        %{
          path: Path.relative_to(file, root),
          sha256: Lockfile.sha256(bytes),
          bytes: byte_size(bytes)
        }
      end)

    # From the registry: this publication has its own entry because it has its own
    # licence, and stating it in two places is how they drift.
    Lockfile.build_entry(
      Sources.fetch!("sc-translations"),
      files: entries,
      # These bytes live inside the `sc` checkout — one sparse clone of bilara-data,
      # three sources with three licences. Without this, `Lockfile.verify/1` looks in
      # `raw/sc-translations/`, which nothing ever writes to.
      raw_root: "sc/bilara-data",
      pin: %{"type" => "git", "commit" => commit(root), "sparse" => "translation"}
    )
    |> Lockfile.put_source()
  end

  defp commit(root) do
    case System.cmd("git", ["-C", root, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end

  # Every segment URN in the corpus, so a rendering can be REJECTED when it names an
  # anchor we do not hold. Without this a typo'd or extra-segment translation lands in
  # the pool pointing at nothing, and the reader who follows the citation finds an empty
  # source — which looks like corpus corruption rather than a translation artefact.
  defp known_works do
    from(t in Pramana.Corpus.Text, where: t.source_id == ^@source_id, select: t.work_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp known_anchors do
    from(s in Segment,
      where: like(s.urn, "pramana:sc.ms:%"),
      select: {s.urn, true}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Grouped, not collapsed. One translator has twelve publications — `dn`, `mn`, `sn`,
  # `an`, `dhp`… — and keying them by {lang, author} alone keeps an arbitrary one. They
  # happen to agree on licence today, which is a property of this snapshot and not a
  # guarantee; the recorded `publication` id would be wrong either way, and that id is
  # how anyone later audits which terms a rendering was taken under.
  @doc """
  Every publication in `_publication.json`, grouped by `{language, author}`.

  Public for the same reason `publication_for/3` is: it is the first half of a licensing
  decision, and `mix pramana.sc.chinese` makes the same decision about the same file
  tree. A second copy of it is rule 41 waiting to happen — the licence would drift
  between two ingests reading one repository.
  """
  @spec publications(String.t()) :: %{{String.t(), String.t()} => [map()]}
  def publications(root) do
    root
    |> Path.join("_publication.json")
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn {id, pub} -> Map.put(pub, "id", id) end)
    |> Enum.group_by(&{&1["translation_lang_iso"], &1["author_uid"]})
  end

  defp files(root, opts) do
    lang = Keyword.get(opts, :lang, "*")
    translator = Keyword.get(opts, :translator, "*")

    root
    |> Path.join("translation/#{lang}/#{translator}/**/*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> then(fn all -> if opts[:limit], do: Enum.take(all, opts[:limit]), else: all end)
  end

  defp collect(file, root, publications, {anchors, works}, {rows, skipped}) do
    {lang, translator} = attribution(file, root)
    candidates = Map.get(publications, {lang, translator}, [])

    segments = file |> File.read!() |> Jason.decode!()

    license =
      license(publication_for(candidates, work_of(segments), Path.relative_to(file, root)))

    {new_rows, misses} =
      Enum.reduce(segments, {[], %{}}, fn {segment_id, text}, {acc, misses} ->
        anchor = anchor_urn(segment_id)
        work = work_id(segment_id)
        text = String.trim(text)

        cond do
          text == "" ->
            {acc, misses}

          # A work we hold nothing of. In this checkout that is entirely the `name/`
          # subtree — division and collection TITLES, not translations of segments.
          not MapSet.member?(works, work) ->
            {acc, bump(misses, :no_such_work)}

          # The work exists and this particular anchor does not. These are real and
          # interesting: where the Pāli abbreviates with `…pe…` the root segment is
          # empty, and the translator spells the passage out — so the translation has
          # content the edition does not. It is dropped rather than given an invented
          # anchor, because an address for text that is not in the edition is exactly
          # the thing this project refuses to manufacture.
          not Map.has_key?(anchors, anchor) ->
            {acc, bump(misses, :no_such_anchor)}

          true ->
            {[row(anchor, segment_id, text, lang, translator, license, file, root) | acc], misses}
        end
      end)

    {new_rows ++ rows, merge_skips(skipped, {lang, translator}, misses)}
  end

  defp bump(counts, key), do: Map.update(counts, key, 1, &(&1 + 1))

  defp merge_skips(skipped, _key, misses) when misses == %{}, do: skipped

  defp merge_skips(skipped, key, misses) do
    Map.update(skipped, key, misses, fn existing ->
      Map.merge(existing, misses, fn _k, a, b -> a + b end)
    end)
  end

  # The collection a file belongs to, taken from its segment ids — the same rule as the
  # root-text ingest, and for the same reason: the filename is packaging.
  defp work_of(segments) do
    segments
    |> Map.keys()
    |> List.first()
    |> case do
      nil -> ""
      id -> id |> String.split(":", parts: 2) |> hd()
    end
  end

  # Resolving a file to the publication whose terms govern it.
  #
  # THE PUBLICATION SAYS WHICH FILES IT COVERS, AND SAYS IT AS A PATH. Every record in
  # `_publication.json` carries a `source_url` pointing at the directory it publishes —
  # `.../tree/published/translation/en/brahmali/vinaya` — so the governing publication is
  # the one whose directory contains this file, longest match winning where publications
  # nest. That is SuttaCentral's own statement about its own files, and it is exact.
  #
  # It replaces matching on `text_uid`, which is usually a prefix of the works it covers
  # (`mn` covers `mn1`) and is sometimes a **collection uid that is not a prefix of its
  # members**: Brahmali's `pli-tv-vi` is the whole Vinaya Pitaka, whose works are
  # `pli-tv-bu-vb-pj1` and friends. That mismatch left **66,199 of his renderings** on an
  # inferred licence and therefore not redistributable — CC0 text withheld by our own
  # uncertainty, and the largest single block standing between this corpus and a public
  # demo. Path matching resolves 4,784 of 4,996 files exactly.
  #
  # `text_uid` is kept as a second attempt, because a publication whose `source_url` is
  # missing or shaped differently should still resolve if the uid can do it.
  #
  # The 212 files that match neither are real: 83 are Sujato's Jataka, in the repository
  # and absent from `_publication.json`, and 124 are `name/` files — proper-name
  # glossaries rather than translations of texts. For those the licence is INFERRED from
  # the translator's other publications, and only if they all agree. An inferred licence
  # is good enough to hold and search under and not good enough to republish on, so
  # `redistributable` stays false until a person confirms it. That these are two separate
  # columns is what makes the distinction expressible instead of a coin flip between
  # "unknown" and "CC0".
  @doc """
  The publication whose terms govern one translation file, and how sure we are.

  Public because it decides a licensing question, and a licensing question decided by an
  untested private function is how 66,199 rows of CC0 text spent two phases marked
  not-redistributable.

  Returns `{publication, :matched}` when the publication states it covers this file,
  `{publication, :inferred}` when the licence was taken from the translator's other
  publications and they all agree, and `{nil, :none}` when neither is possible.
  """
  @spec publication_for([map()], String.t(), String.t()) ::
          {map(), :matched | :inferred} | {nil, :none}
  def publication_for([], _work, _path), do: {nil, :none}

  def publication_for(candidates, work, path) do
    case by_path(candidates, path) do
      nil -> by_uid(candidates, work)
      publication -> {publication, :matched}
    end
  end

  defp by_path(candidates, path) do
    candidates
    |> Enum.filter(fn c ->
      case published_dir(c) do
        nil -> false
        dir -> path == dir or String.starts_with?(path, dir <> "/")
      end
    end)
    |> Enum.max_by(&String.length(published_dir(&1)), fn -> nil end)
  end

  # `https://github.com/suttacentral/bilara-data/tree/published/translation/en/...`
  # -> `translation/en/...`, the path as this repository stores it.
  defp published_dir(%{"source_url" => url}) when is_binary(url) do
    case String.split(url, "/tree/published/", parts: 2) do
      [_, dir] -> String.trim_trailing(dir, "/")
      _ -> nil
    end
  end

  defp published_dir(_), do: nil

  defp by_uid(candidates, work) do
    candidates
    |> Enum.filter(&String.starts_with?(work, &1["text_uid"] || "\u0000"))
    |> Enum.max_by(&String.length(&1["text_uid"] || ""), fn -> nil end)
    |> case do
      nil -> infer(candidates)
      publication -> {publication, :matched}
    end
  end

  defp infer(candidates) do
    case Enum.uniq(Enum.map(candidates, &get_in(&1, ["license", "license_abbreviation"]))) do
      [_agreed] -> {hd(candidates), :inferred}
      _disagree -> {nil, :none}
    end
  end

  # `translation/en/sujato/sutta/mn/mn1_translation-en-sujato.json` -> {"en", "sujato"}.
  defp attribution(file, root) do
    case file |> Path.relative_to(root) |> Path.split() do
      ["translation", lang, translator | _] -> {lang, translator}
      _ -> {"und", "unknown"}
    end
  end

  defp anchor_urn(segment_id) do
    [work, locator] = String.split(segment_id, ":", parts: 2)
    "pramana:#{@source_id}.#{@witness}:#{work}@#{locator}"
  end

  defp work_id(segment_id), do: segment_id |> String.split(":", parts: 2) |> hd()

  defp row(anchor, segment_id, text, lang, translator, license, file, root) do
    %{
      anchor_urn: anchor,
      work_id: work_id(segment_id),
      lang: lang,
      translator_id: translator,
      translator_name: license.author_name,
      # A published human translation. Not `t1`: nothing about it was generated, and the
      # tier is what a reader uses to decide how much to trust it.
      tier: "t0",
      method: "human",
      text: text,
      # Published and edited by SuttaCentral. `approved` is the state that means a person
      # stands behind it, which is exactly the claim a published translation makes.
      review_state: "approved",
      license_spdx: license.spdx,
      license_class: license.class,
      redistributable: license.redistributable,
      attribution: license.attribution,
      source_file: Path.relative_to(file, File.cwd!()),
      meta: %{
        "publication" => license.publication_id,
        "root" => root,
        # "matched" or "inferred". A reader auditing terms needs to know which.
        "license_confidence" => license.confidence
      }
    }
  end

  # CC0 waives everything; CC BY-SA 3.0 does not. Treating them alike would strip an
  # attribution the translator is entitled to, so the abbreviation is mapped explicitly
  # and anything unrecognised is `unknown` + not redistributable.
  @doc """
  The licence terms a `publication_for/3` result carries, ready to store on a rendering.

  Public alongside `publications/1` and for the same reason. The mapping from CC0 and
  CC BY-SA to `redistributable` is the decision, and an inferred licence never
  authorises redistribution however confident the abbreviation looks.
  """
  @spec license({map(), :matched | :inferred} | {nil, :none}) :: map()
  def license({nil, _}) do
    %{
      spdx: nil,
      class: "unknown",
      redistributable: false,
      attribution: nil,
      author_name: nil,
      publication_id: nil,
      confidence: "none"
    }
  end

  def license({publication, confidence}) do
    license = publication["license"] || %{}
    abbreviation = license["license_abbreviation"]

    {spdx, class, redistributable} =
      case abbreviation do
        "CC0" -> {"CC0-1.0", "cc0", true}
        "CC BY-SA 3.0" -> {"CC-BY-SA-3.0", "cc-by-sa", true}
        "CC BY-SA 4.0" -> {"CC-BY-SA-4.0", "cc-by-sa", true}
        "CC BY 4.0" -> {"CC-BY-4.0", "cc-by", true}
        _ -> {nil, "unknown", false}
      end

    %{
      spdx: spdx,
      class: class,
      # An inferred licence never authorises redistribution. The class is what we
      # believe; this column is what we are willing to act on.
      redistributable: redistributable and confidence == :matched,
      attribution: attribution_line(publication, license),
      author_name: publication["creator_name"] || publication["author_uid"],
      publication_id: publication["id"],
      confidence: Atom.to_string(confidence)
    }
  end

  defp attribution_line(publication, license) do
    [
      publication["translation_title"],
      publication["author_uid"] && "translated by #{publication["author_uid"]}",
      license["license_abbreviation"],
      publication["source_url"]
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(". ")
    |> case do
      "" -> nil
      line -> line
    end
  end

  defp report(rows, skipped, publications, dry_run?) do
    written =
      if dry_run? do
        0
      else
        {:ok, n} = Translations.store(rows)
        n
      end

    stats = if dry_run?, do: %{}, else: Translations.stats()

    Mix.shell().info("""

    ingested SuttaCentral translations
      renderings prepared: #{length(rows)}
      written:             #{written}
      publications known:  #{map_size(publications)}
      pool:                #{Map.get(stats, :renderings, 0)} rendering(s)
      by licence:          #{inspect(Map.get(stats, :by_license_class, %{}))}
      shared anchors:      #{Map.get(stats, :anchors_with_multiple, 0)} with >1 rendering
    """)

    for {{lang, translator}, counts} <- Enum.take(skipped, 20) do
      Mix.shell().info(
        "  #{lang}/#{translator}: #{Map.get(counts, :no_such_work, 0)} in works we hold " <>
          "nothing of, #{Map.get(counts, :no_such_anchor, 0)} at anchors the edition " <>
          "does not print"
      )
    end

    unlicensed = Map.get(stats[:by_license_class] || %{}, "unknown", 0)

    if unlicensed > 0 do
      Mix.shell().info(
        "\n  #{unlicensed} rendering(s) have no identifiable publication AND no agreeing " <>
          "sibling to infer from: stored as unknown / not redistributable. " <>
          "`Pramana.Translations.unlicensed/0` lists them by translator."
      )
    end
  end
end
