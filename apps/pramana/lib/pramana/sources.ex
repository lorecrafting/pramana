defmodule Pramana.Sources do
  @moduledoc """
  Registry of upstream corpus sources and their licenses.

  License data is structured, not free text, because `license_class` drives
  redistribution decisions that must be enforceable in a query. See
  `docs/SOURCES.md` and the licensing posture section of `CLAUDE.md`:
  **we publish the pipeline, not the corpus.**
  """

  @type license :: %{
          spdx: String.t(),
          class: String.t(),
          commercial_use: boolean(),
          redistributable: boolean(),
          # Optional: absent means "permitted", which is true of every source that
          # predates 84000 and is the only safe default for a column added later.
          derivatives: boolean(),
          notice: String.t() | nil
        }

  @type t :: %{
          id: String.t(),
          name: String.t(),
          # Which canon this source belongs to. NOT the same axis as
          # `composition_origin`, and the two disagree on real texts: a Pāli sutta and a
          # Derge sūtra are both `indic` in origin while belonging to different canons,
          # and SAT's Taishō 56–84 are `japanese` in origin while belonging to the
          # Chinese canon. Origin is where a text was composed; this is which collection
          # transmits it, which is the axis a reader means by "what does the Tibetan
          # canon say".
          tradition: String.t(),
          # nil for a locally-added text: there is no upstream to point at, and the
          # content hash IS the pin. Map typespecs are exact, so declaring this
          # String.t() made every caller's return type unsatisfiable.
          upstream_url: String.t() | nil,
          repo: String.t() | nil,
          license: license()
        }

  @sources %{
    "cbeta" => %{
      id: "cbeta",
      tradition: "chinese",
      name: "CBETA Chinese Buddhist Electronic Tripitaka (XML P5)",
      upstream_url: "https://github.com/cbeta-org/xml-p5",
      repo: "cbeta-org/xml-p5",
      license: %{
        spdx: "LicenseRef-CBETA-NC",
        class: "nc",
        commercial_use: false,
        redistributable: false,
        notice: "Available for non-commercial use when distributed with this header intact."
      }
    },
    "sat" => %{
      id: "sat",
      tradition: "chinese",
      name: "SAT Daizōkyō Text Database",
      upstream_url: "https://21dzk.l.u-tokyo.ac.jp/SAT/",
      repo: nil,
      license: %{
        spdx: "CC-BY-SA-4.0",
        class: "cc-by-sa",
        commercial_use: true,
        redistributable: true,
        notice: nil
      }
    },
    # bilara-data's LICENSE.md says everything is CC0. Its own `_publication.json`
    # disagrees in two places, and the difference is not cosmetic:
    #
    #   scpub64  the Mahāsaṅgīti Pāli root text  -> Public Domain Mark
    #   scpub69  the Patna Dhammapada            -> CC BY-SA 3.0
    #
    # CC BY-SA carries attribution and share-alike obligations CC0 does not, so
    # republishing it under a blanket CC0 assumption would be a licence violation. This
    # entry covers the ROOT TEXT, which is what `mix pramana.sc.ingest` loads; a
    # per-publication licence belongs on any translation ingested later (#39).
    "sc" => %{
      id: "sc",
      tradition: "pali",
      name: "SuttaCentral bilara-data — Mahāsaṅgīti Pāli Tipiṭaka (root)",
      upstream_url: "https://github.com/suttacentral/bilara-data",
      repo: "suttacentral/bilara-data",
      license: %{
        spdx: "CC-PDM-1.0",
        class: "public-domain",
        commercial_use: true,
        redistributable: true,
        notice:
          "Public Domain Mark per bilara-data _publication.json (scpub64): free of " <>
            "known restrictions under copyright law. SuttaCentral asks that use accord " <>
            "with the values of the Buddhist tradition."
      }
    },
    # The Tibetan pair. They are deliberately two sources rather than one, because the
    # source text and its English translation have different licences and different
    # roles, and merging them would put a rendering under the same terms as the words it
    # renders.
    "derge" => %{
      id: "derge",
      tradition: "tibetan",
      name: "Digital Derge Kangyur (Esukhia–Barom, from the UVA–SOAS 2013 eKangyur)",
      upstream_url: "https://github.com/Esukhia/derge-kangyur",
      repo: "Esukhia/derge-kangyur",
      license: %{
        spdx: "CC-PDM-1.0",
        class: "public-domain",
        commercial_use: true,
        redistributable: true,
        derivatives: true,
        notice:
          "A mechanical reproduction of a public-domain woodblock edition, and so " <>
            "itself public domain, per the project's own README. The proofreading " <>
            "annotations are the editors' work; the text is not."
      }
    },
    "derge-tengyur" => %{
      id: "derge-tengyur",
      tradition: "tibetan",
      name: "Digital Derge Tengyur (Esukhia–Barom Theksum Choling)",
      upstream_url: "https://github.com/Esukhia/derge-tengyur",
      repo: "Esukhia/derge-tengyur",
      license: %{
        spdx: "CC-PDM-1.0",
        class: "public-domain",
        commercial_use: true,
        redistributable: true,
        derivatives: true,
        notice:
          "\"This work is a mechanical reproduction of a Public domain work, and as " <>
            "such is also in the Public domain\" — the repository's own statement, the " <>
            "same one the Kangyur carries. The other half of the same edition, kept as " <>
            "its own source because it is its own publication with its own release."
      }
    },
    "bdrc-derge" => %{
      id: "bdrc-derge",
      tradition: "tibetan",
      name: "BDRC scan of the Degé Kangyur (W4CZ5369), image lists only",
      upstream_url: "https://library.bdrc.io/show/bdr:W4CZ5369",
      repo: nil,
      license: %{
        spdx: "CC-BY-NC-4.0",
        class: "nc",
        commercial_use: false,
        redistributable: false,
        derivatives: false,
        notice:
          "What is stored here is BDRC's list of what it scanned — filenames and " <>
            "dimensions — not the scans. The images are served by BDRC over IIIF and " <>
            "are linked, never copied, so this corpus makes no claim to redistribute " <>
            "them and never reads them."
      }
    },
    # 84000 publishes twice over, under two licences, and the distinction is real: the
    # prose of a translation is restricted, the fact that Toh 113 is called
    # *Saddharmapuṇḍarīka* is not.
    "84000-rdf" => %{
      id: "84000-rdf",
      tradition: "tibetan",
      name: "84000 catalogue metadata (RDF/LOD export)",
      upstream_url: "https://github.com/84000/data-rdf",
      repo: "84000/data-rdf",
      license: %{
        spdx: "CC0-1.0",
        class: "cc0",
        commercial_use: true,
        redistributable: true,
        derivatives: true,
        notice:
          "Per each record's own `adm:license` — \"Metadata related to the " <>
            "translations by 84000, provided under the CC0 License\". The repository " <>
            "README states CC BY-NC-ND, which governs the translations themselves; the " <>
            "more specific statement governs here, as it does for bilara-data."
      }
    },
    "84000" => %{
      id: "84000",
      tradition: "tibetan",
      name: "84000: Translating the Words of the Buddha",
      upstream_url: "https://github.com/84000/data-tei",
      repo: "84000/data-tei",
      license: %{
        spdx: "CC-BY-NC-ND-3.0",
        class: "nc",
        commercial_use: false,
        redistributable: false,
        # The first ND source in this corpus, and the reason `derivatives` exists as a
        # column. NC and ND are not degrees of the same restriction: NC says who may
        # receive the text, ND says what may be made from it. A pipeline that segments,
        # chunks, embeds and (Phase 7) translates does the second thing constantly, so
        # the constraint has to be recordable even though whether any given step counts
        # as a derivative work is a judgement for the deployment, not for this table.
        derivatives: false,
        notice:
          "CC BY-NC-ND 3.0. May be copied or printed for fair use with full " <>
            "attribution, not for commercial advantage. See " <>
            "https://github.com/84000/all-data/blob/master/Terms_of_Use.md"
      }
    }
  }

  @doc "Fetches a source definition by id."
  @spec fetch(String.t()) :: {:ok, t()} | {:error, :unknown_source}
  def fetch(id) when is_binary(id) do
    case Map.fetch(@sources, id) do
      {:ok, source} -> {:ok, source}
      :error -> {:error, :unknown_source}
    end
  end

  @doc """
  Fetches a source definition, raising when the id is not registered.

  For callers that are naming a source they know exists — an ingest task, a test — where
  an unregistered id is a bug rather than a condition to handle.
  """
  @spec fetch!(String.t()) :: t()
  def fetch!(id) when is_binary(id) do
    case fetch(id) do
      {:ok, source} -> source
      {:error, :unknown_source} -> raise ArgumentError, "unknown source #{inspect(id)}"
    end
  end

  @doc """
  A source definition built from a local manifest rather than this registry.

  Locally-added texts are open-ended by design — one per folder someone drops in — so
  they cannot be enumerated here. The licence still has to be structured, because
  `license_class` is what excludes a text from public surfaces, and a modern in-copyright
  commentary is exactly the case that must be excluded.

  Ids are namespaced `local-<manifest id>` so a local text can never collide with, or be
  mistaken for, a pinned upstream source. The separator is a HYPHEN, not a colon: this id
  becomes the source component of every URN the text produces, and a colon there is the
  URN's own field separator — it would make every citation unparseable.
  """
  @spec from_manifest(Pramana.Local.Manifest.t()) :: t()
  def from_manifest(manifest) do
    license = manifest.license

    %{
      id: local_id(manifest.id),
      name: manifest.title_en || manifest.title,
      upstream_url: nil,
      repo: nil,
      license: %{
        spdx: license["spdx"] || "LicenseRef-Local-Restricted",
        class: license["class"] || "restricted",
        commercial_use: license["commercial_use"] == true,
        redistributable: license["redistributable"] == true,
        derivatives: license["derivatives"] != false,
        notice: license["note"]
      }
    }
  end

  @doc "The namespaced source id for a local manifest id."
  @spec local_id(String.t()) :: String.t()
  def local_id(manifest_id), do: "local-" <> manifest_id

  @doc "Whether a source id refers to a locally-added text."
  @spec local?(String.t()) :: boolean()
  def local?(id), do: String.starts_with?(id, "local-")

  @doc "All known source ids."
  @spec ids() :: [String.t()]
  def ids, do: Map.keys(@sources)

  @doc """
  The canon a source belongs to.

  An unregistered id — every `local-*` text, since those cannot be enumerated here —
  gets **its own tradition, named after itself**, rather than a guess or a nil. That is
  the conservative answer for a retrieval path that groups by tradition: a locally-added
  text is never silently folded into a canon it may not belong to, and never silently
  dropped for belonging to none. A local manifest that genuinely belongs to a canon can
  say so; see `from_manifest/1`.
  """
  @spec tradition(String.t()) :: String.t()
  def tradition(id) when is_binary(id) do
    case Map.fetch(@sources, id) do
      {:ok, %{tradition: tradition}} -> tradition
      :error -> id
    end
  end

  @doc """
  Registered source ids grouped by canon.

  `Pramana.Retrieval.Semantic` derives its per-tradition search groups from this, rather
  than keeping a second copy of the mapping. The second copy is what this replaces: it
  listed four of the eight registered sources, so `sat` — Taishō 56–84, the whole
  Japanese-composed corpus — would have been unreachable under `per_tradition: true` on
  the day #14 unblocks, with nothing failing to say so.
  """
  @spec by_tradition() :: %{String.t() => [String.t()]}
  def by_tradition do
    @sources
    |> Map.values()
    |> Enum.group_by(& &1.tradition, & &1.id)
    |> Map.new(fn {tradition, ids} -> {tradition, Enum.sort(ids)} end)
  end

  @doc """
  True when a source's content may be redistributed by us.

  Nothing in this project should ever republish corpus text for which this is false.
  """
  @spec redistributable?(t()) :: boolean()
  def redistributable?(%{license: %{redistributable: value}}), do: value
end
