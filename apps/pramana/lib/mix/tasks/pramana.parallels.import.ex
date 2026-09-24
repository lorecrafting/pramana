defmodule Mix.Tasks.Pramana.Parallels.Import do
  @shortdoc "Fetches and imports SuttaCentral's curated cross-tradition parallels"

  @moduledoc """
  Ingests `sc-data`'s parallel graph and anchors it into this corpus.

      mix pramana.parallels.import              # fetches, pins, imports
      mix pramana.parallels.import --dry-run    # writes nothing

  Two files, both pinned in `sources.lock.json` by content hash:

  - `relationship/new_parallels.json` — 388,074 hand-curated relations
  - `structure/text_extra_info.json` — the `volpage` for each text, which is what lets a
    SuttaCentral id become a URN in our corpus

  ## Why ingest rather than infer

  This is decades of comparative scholarship, typed by strength and freely given.
  `CLAUDE.md` invariant #5: deterministic before probabilistic. An embedding could
  approximate it and would be worse, unexplainable and unattributable.

  ## Anchoring, and what it costs to get wrong

  SuttaCentral records `sa1` as `T ii 001a06` — Taishō volume 2, page 001, register a,
  line 06. The URN is looked **up** rather than constructed, because the juan is in our
  data and not in their reference; building it by hand would be guessing at a component
  we already have. A mis-parsed anchor does not fail loudly, it produces a valid URN
  pointing at the wrong passage.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Parallels
  alias Pramana.Sources

  @switches [dry_run: :boolean]

  @parallels_url "https://raw.githubusercontent.com/suttacentral/sc-data/main/relationship/new_parallels.json"
  @info_url "https://raw.githubusercontent.com/suttacentral/sc-data/main/structure/text_extra_info.json"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    {parallels_raw, info_raw} = fetch()

    parallels = Jason.decode!(parallels_raw)
    info = Jason.decode!(info_raw)

    anchors = info |> Enum.map(&Parallels.resolve_anchor/1) |> Enum.reject(&is_nil/1)
    pairs = Parallels.flatten(parallels)

    report(info, anchors, pairs, opts[:dry_run])

    unless opts[:dry_run] do
      {:ok, stored_anchors} = Parallels.store_anchors(anchors)
      {:ok, stored} = Parallels.store(pairs)
      :ok = lock(parallels_raw, info_raw)

      # THE LOCKFILE AND THE BAKE ID MOVE TOGETHER — `bake_id` is a hash of
      # `sources.lock.json`, so writing it changes the id by definition. A bake row that no
      # longer describes its inputs stamps every response with an id for a corpus that does
      # not exist. `Bake.record/1` writes a row; it does not re-bake.
      {:ok, _} = Bake.record(%{"source" => "sc-data", "mode" => "parallels_import"})

      Mix.shell().info("""
        stored #{stored_anchors} anchor(s) and #{stored.written} parallel(s)
      """)

      summarise()
    end
  end

  defp fetch do
    Mix.shell().info("fetching sc-data (two files, ~24 MB)...")

    parallels = Req.get!(@parallels_url).body |> encode()
    info = Req.get!(@info_url).body |> encode()

    # PERSISTED, not just hashed. This task used to fetch into memory, record the hashes
    # in `sources.lock.json`, import, and drop the bytes — so `raw/sc-data/` never existed
    # and `Lockfile.verify("sc-data")` reported both files missing forever. The lockfile
    # was making a claim about files nothing had stored, which is invariant 3 inverted:
    # `raw/` is meant to be the append-only record a bake can be reproduced from.
    store!("relationship/new_parallels.json", parallels)
    store!("structure/text_extra_info.json", info)

    {parallels, info}
  end

  defp store!(path, bytes) do
    target = Path.join([Lockfile.raw_dir(), "sc-data", path])
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, bytes)
  end

  # Req decodes JSON by content type; we want the bytes, both to hash them and to decode
  # once ourselves.
  defp encode(body) when is_binary(body), do: body
  defp encode(body), do: Jason.encode!(body)

  defp lock(parallels_raw, info_raw) do
    files = [
      %{
        path: "relationship/new_parallels.json",
        sha256: Lockfile.sha256(parallels_raw),
        bytes: byte_size(parallels_raw)
      },
      %{
        path: "structure/text_extra_info.json",
        sha256: Lockfile.sha256(info_raw),
        bytes: byte_size(info_raw)
      }
    ]

    entry =
      Lockfile.build_entry(
        Sources.fetch!("sc-data"),
        files: files,
        pin: %{"type" => "content", "files_sha256" => Lockfile.manifest_hash(files)}
      )

    Lockfile.put_source(entry)
  end

  defp report(info, anchors, pairs, dry_run?) do
    by_relation = Enum.frequencies_by(pairs, & &1.relation)
    ranges = Enum.count(anchors, &String.contains?(&1.urn, "-"))

    Mix.shell().info("""

    #{if dry_run?, do: "DRY RUN — nothing written", else: "importing parallels"}

      text entries:        #{length(info)}
      anchored to Taishō:  #{length(anchors)}#{" (#{ranges} spanning a range)"}
      parallel pairs:      #{length(pairs)}
      by relation:         #{Enum.map_join(by_relation, ", ", fn {r, n} -> "#{r} #{n}" end)}
    """)
  end

  defp summarise do
    stats = Parallels.stats()

    Mix.shell().info("""
      IN THE CORPUS
        parallels stored:        #{stats.parallels}
        both ends resolvable:    #{stats.resolvable_both_ends}
        one end resolvable:      #{stats.resolvable_one_end}   ← the Āgama↔Nikāya case
    """)
  end
end
