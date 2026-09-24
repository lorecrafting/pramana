defmodule Pramana.Sources do
  @moduledoc """
  Registry of upstream corpus sources and their licenses.

  License data is structured, not free text, because `license_class` drives
  redistribution decisions that must be enforceable in a query. See
  `docs/SOURCES.md` and the licensing posture section of `CLAUDE.md`:
  **we publish the pipeline, not the corpus.**
  """

  # `optional(:derivatives)` and not `derivatives: boolean()`. The comment below has said
  # "optional" since 84000 arrived, and the SHORTHAND cannot express it: `key: type` in a
  # map typespec means required and exact. `cbeta`, `sat` and `sc` omit the key, so
  # `fetch!("sc")` returned a value that did not match `t()` — and every function typed
  # to take a source broke its contract, which is where all nine of dialyzer's warnings
  # came from. Mixing shorthand with `optional/1` is not allowed, so every key is written
  # out.
  @type license :: %{
          :spdx => String.t(),
          :class => String.t(),
          :commercial_use => boolean(),
          :redistributable => boolean(),
          # Absent means "permitted", which is true of every source that predates 84000
          # and is the only safe default for a column added later.
          optional(:derivatives) => boolean(),
          :notice => String.t() | nil
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
          "Mahāsaṅgīti Tipiṭaka Buddhavasse 2500. Public Domain Mark per bilara-data " <>
            "_publication.json (scpub64): free of known restrictions under copyright " <>
            "law. SuttaCentral asks that use accord with the values of the Buddhist " <>
            "tradition."
      }
    },
    # bilara-data publishes three things this corpus takes separately, exactly as 84000
    # publishes translations and metadata under different terms. They are separate
    # entries because they carry DIFFERENT LICENCES, and one entry would have to state
    # the weakest of them about all three.
    #
    # These two were previously written inline in their mix tasks, which is how `sc`'s
    # licence notice came to differ between the lockfile and the database — see the
    # commit that moved them.
    "sc-translations" => %{
      id: "sc-translations",
      tradition: "pali",
      name: "SuttaCentral bilara-data — translations",
      upstream_url: "https://github.com/suttacentral/bilara-data",
      repo: "suttacentral/bilara-data",
      license: %{
        # The entry-level licence is the WEAKEST of the publications it covers, so a
        # reader of the lockfile alone cannot conclude more than is true. The precise
        # terms live per rendering in `translations.license_spdx`, because that is the
        # granularity the data actually has.
        spdx: "CC-BY-SA-3.0",
        class: "cc-by-sa",
        commercial_use: true,
        redistributable: true,
        notice:
          "Mixed per publication: 139 CC0, 1 CC BY-SA 3.0 (scpub69, Patna " <>
            "Dhammapada). See `translations.license_spdx` for the terms on any " <>
            "individual rendering; this entry states the most restrictive."
      }
    },
    # The Chinese half of bilara-data, and the only source here that is READ AND NEVER
    # STORED. `Pramana.Sc.Lzh` matches it against the CBETA Āgamas this corpus already
    # holds and keeps a Taishō address; not one of its bytes lands in `texts` or
    # `segments`. It is registered and pinned anyway, because it is an input to an
    # ingest and a bake that cannot be reproduced from `sources.lock.json` is not a bake.
    # DILA's TEI glossaries — the lexicon layer. `docs/PLAN.md` L1.
    #
    # ONE CONSERVATIVE REGISTRY ENTRY FOR FIVE GLOSSARIES. This is not a claim that their
    # published licence history is identical: the current portal says CC BY-NC-SA 4.0,
    # while each exact digital-edition PDF reviewed for the Chinese pilot says CC BY-SA
    # 3.0 and points to the TEI source. The glossary id remains on each row in
    # `glossary_entries.meta["glossary"]`; operation-level authorization is owned by
    # `docs/strategy/CHINESE_PILOT_RIGHTS.md`, not this coarse serving/export gate.
    "dila-glossaries" => %{
      id: "dila-glossaries",
      # REFERENCE, not `chinese`, and the registry test is what forced the question. A
      # dictionary describes WORDS; it is not part of a canon. `sat-teihon` is filed here
      # for the parallel reason — it surveys manuscripts rather than being one — and the
      # hazard is the same: a per-tradition search for the Chinese canon that could return
      # lexicography where a reader asked for scripture.
      #
      # It is also not one canon's. Karashima's three gloss Chinese translations, but the
      # Mahāvyutpatti is Sanskrit-headed and bridges Chinese and Tibetan at once, so any
      # single canon would be wrong about part of this source.
      tradition: "reference",
      name: "DILA Glossaries for Buddhist Studies (Soothill-Hodous, Karashima, Mahāvyutpatti)",
      upstream_url: "https://glossaries.dila.edu.tw/",
      repo: nil,
      license: %{
        spdx: "CC-BY-NC-SA-4.0",
        class: "nc",
        commercial_use: false,
        # Conservative PUBLIC-SURFACE policy: the current portal has an NC term, so this
        # aggregate record remains excluded from the public artefact. This does not mean
        # every local transformation is automatically authorized.
        redistributable: false,
        notice:
          "Conservative aggregate record: the current DILA glossary portal states " <>
            "CC BY-NC-SA 4.0, while the exact Soothill-Hodous, three Karashima and " <>
            "Mahavyutpatti digital-edition PDFs reviewed in 2026-09 state CC BY-SA 3.0 " <>
            "and point to the TEI source. Keep the NC public-surface gate until that " <>
            "resource-level conflict is clarified; use docs/strategy/CHINESE_PILOT_RIGHTS.md " <>
            "for operation-specific pilot authorization."
      }
    },
    "sc-lzh" => %{
      id: "sc-lzh",
      # The canon it belongs to, not the repository it came from. bilara-data is
      # SuttaCentral's and mostly Pāli; this subtree is the Chinese Āgamas.
      tradition: "chinese",
      name: "SuttaCentral bilara-data — SuttaCentral Taishō (lzh root)",
      upstream_url: "https://github.com/suttacentral/bilara-data",
      repo: "suttacentral/bilara-data",
      license: %{
        # scpub39, "SuttaCentral Taisho". SuttaCentral publishes it CC0; it is derived
        # from SAT 2018, which is CC BY-SA 4.0, and re-punctuated and corrected against
        # CBETA and Yinshun. The two terms never have to be reconciled here because
        # nothing from this source is stored or served — see the note above.
        spdx: "CC0-1.0",
        class: "cc0",
        commercial_use: true,
        redistributable: true,
        notice:
          "CC0 per bilara-data _publication.json (scpub39). Corrected and re-punctuated " <>
            "from SAT 2018 (CC BY-SA 4.0). Used as an alignment bridge only: no text " <>
            "from this source is stored in the corpus or served by the API."
      }
    },
    "sc-data" => %{
      id: "sc-data",
      tradition: "pali",
      name: "SuttaCentral sc-data (parallels and text metadata)",
      upstream_url: "https://github.com/suttacentral/sc-data",
      repo: "suttacentral/sc-data",
      license: %{
        spdx: "NOASSERTION",
        class: "unknown",
        commercial_use: false,
        redistributable: false,
        notice: "sc-data carries no LICENSE file; terms unconfirmed as of 2026-08-15."
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
    # THE GAP DESCRIBED, WHICH IS NOT THE GAP FILLED. Taishō 56–84 is 547 works this corpus
    # does not hold and only SAT publishes; the request for the text was sent 2026-08-15 and
    # is unanswered. Separately, SAT and the National Institute of Japanese Literature
    # published the *base-text survey* for the 日本撰述部 under CC BY-SA 4.0 — which
    # manuscript or printed edition each work was edited from, where the original is held,
    # and sometimes a link to a scan of it.
    #
    # It covers **144 of the 547 works** (T2185–T2346), so it describes about a quarter of
    # the gap and fills none of it. Registered separately from `sat` because the licence is
    # not the same obligation: this one carries a SECOND creator, and attributing only SAT
    # would breach it.
    "sat-teihon" => %{
      id: "sat-teihon",
      # Reference data ABOUT texts, not a witness to any — the same axis `dila-authority`
      # sits on. It describes works this corpus cannot show.
      tradition: "reference",
      name: "SAT 底本調査 — base-text survey of the Taishō Japanese-composed section",
      upstream_url: "http://21dzk.l.u-tokyo.ac.jp/SAT/teihon.html",
      repo: nil,
      license: %{
        spdx: "CC-BY-SA-4.0",
        class: "cc-by-sa",
        commercial_use: true,
        redistributable: true,
        derivatives: true,
        notice:
          "CC BY-SA 4.0. Attribution is owed to BOTH creators — SAT大蔵経テキストデータベース" <>
            "研究会 and 国文学研究資料館 (National Institute of Japanese Literature) — per the " <>
            "licence line carried in the file itself. Naming only SAT is a licence breach, " <>
            "which is why this is a separate entry from `sat` rather than a second file " <>
            "under it."
      }
    },
    # 84000 publishes twice over, under two licences, and the distinction is real: the
    # prose of a translation is restricted, the fact that Toh 113 is called
    # *Saddharmapuṇḍarīka* is not.
    "dila-authority" => %{
      id: "dila-authority",
      # NOT a tradition: this is reference data ABOUT texts, not a witness to any of them.
      # The axis exists so `per_tradition` knows which searches to run, and an authority
      # record belongs to no canon — it describes people who appear across all of them.
      tradition: "reference",
      # PERSON AND PLACE. `authority_time/` and `authority_catalog/` exist in the repository
      # as README files with no data at this pin, and naming them here promised two databases
      # the upstream does not ship — the failure `Pramana.Coverage` exists to prevent, sitting
      # in the registry rather than in a result.
      name: "DILA Buddhist Studies Authority Databases (person, place)",
      upstream_url: "https://github.com/DILA-edu/Authority-Databases",
      repo: "DILA-edu/Authority-Databases",
      license: %{
        spdx: "CC-BY-SA-3.0",
        class: "cc-by-sa",
        commercial_use: true,
        redistributable: true,
        derivatives: true,
        notice:
          "Creative Commons Attribution-ShareAlike 3.0 Unported, per COPYING.rst and the " <>
            "README. Attribution: Dharma Drum Institute of Liberal Arts. ShareAlike binds " <>
            "derivatives of the authority data itself, not the corpus it is linked to."
      }
    },
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
      # A manifest that names a canon joins it; one that does not becomes its own, via
      # the same rule `tradition/1` applies to any unregistered id.
      tradition: manifest.tradition || local_id(manifest.id),
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
