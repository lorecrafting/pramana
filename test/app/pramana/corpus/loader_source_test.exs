defmodule Pramana.Corpus.LoaderSourceTest do
  @moduledoc """
  The source row must follow the licence registry, not the other way round.

  `redistributable_only: true` is enforced by a join on `sources.redistributable`, so a
  licence recorded in code that never reaches the database is a filter making decisions
  on stale data. This happened: bilara-data's licence was corrected from CC0 to Public
  Domain Mark in `Pramana.Sources`, and because the upsert used `on_conflict: :nothing`
  a full re-ingest of 8,442 works left the row still saying `cc0`.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Source
  alias Pramana.Normalize.Bilara
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias Pramana.Segment.SegmentId

  defp load!(work_id, opts) do
    {:ok, ir} =
      Bilara.normalize(Jason.encode!(%{"#{work_id}:1.1" => "Evaṁ me sutaṁ—"}), work_id: work_id)

    Loader.load(
      ir,
      Keyword.merge(
        [
          source: "sc",
          witness: "ms",
          segmenter: SegmentId,
          provenance: %{
            composition_origin: "indic",
            text_role: "root",
            attribution_confidence: "certain"
          },
          addressing: "canonical"
        ],
        opts
      )
    )
  end

  test "a licence correction in the registry reaches an existing row" do
    Repo.insert!(%Source{
      id: "sc",
      name: "stale name",
      license_spdx: "CC0-1.0",
      license_class: "cc0",
      commercial_use: true,
      redistributable: true
    })

    {:ok, _} = load!("mn1", [])

    source = Repo.get!(Source, "sc")

    assert source.license_spdx == "CC-PDM-1.0"
    assert source.license_class == "public-domain"
    refute source.name == "stale name"
  end

  test "re-ingest replaces stale permissive source rights with the registry's restrictions" do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "stale permissive row",
      license_spdx: "CC0-1.0",
      license_class: "cc0",
      commercial_use: true,
      redistributable: true
    })

    xml =
      "<TEI><text><body><milestone n=\"1\" unit=\"juan\"/><lb n=\"0001a01\"/>如是我聞</body></text></TEI>"

    {:ok, ir} =
      CBETA.normalize(xml,
        work_id: "T0099",
        canon: "T",
        volume: 2,
        number: "0099"
      )

    assert {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T")
    source = Repo.get!(Source, "cbeta")
    assert source.license_class == "nc"
    refute source.redistributable
    refute source.commercial_use
  end

  test "the file a work came from is recorded, so verify can re-derive it" do
    {:ok, _} =
      load!("mn1", source_file: "raw/sc/bilara-data/root/pli/ms/sutta/mn/mn1_root-pli-ms.json")

    text = Repo.get_by!(Pramana.Corpus.Text, work_id: "mn1")

    assert text.meta["source_file"] =~ "mn1_root-pli-ms.json"
  end

  describe "the derivatives axis" do
    test "84000 is recorded as no-derivatives" do
      {:ok, source} = Pramana.Sources.fetch("84000")

      # The first ND source in the corpus, and the reason the column exists. NC and ND
      # are not degrees of one restriction: NC governs who may receive the text, ND what
      # may be made from it.
      assert source.license.spdx == "CC-BY-NC-ND-3.0"
      assert source.license.derivatives == false
      assert source.license.commercial_use == false
    end

    test "the Tibetan source text is public domain and permits derivatives" do
      {:ok, source} = Pramana.Sources.fetch("derge")

      # The pair is two sources on purpose: merging them would put a rendering under the
      # same terms as the words it renders.
      assert source.license.class == "public-domain"
      assert source.license.derivatives == true
      assert source.license.redistributable == true
    end

    test "every source that predates the column still permits derivatives" do
      for id <- ~w(cbeta sat sc derge) do
        {:ok, source} = Pramana.Sources.fetch(id)
        assert Map.get(source.license, :derivatives, true) == true, "#{id} regressed"
      end
    end

    test "the flag reaches the database, where a filter could act on it" do
      # Same failure mode as the licence-class regression above: a restriction recorded
      # only in code is a restriction nothing enforces.
      {:ok, _} = load!("mn1", source: "sc")

      assert Repo.get(Source, "sc").derivatives == true
    end

    test "a local manifest may declare no-derivatives, and it is believed" do
      manifest =
        manifest(%{"spdx" => "CC-BY-NC-ND-4.0", "class" => "nc", "derivatives" => false})

      assert Pramana.Sources.from_manifest(manifest).license.derivatives == false
    end

    test "a manifest that says nothing about derivatives permits them" do
      # Absent means permitted. A column added later must not silently restrict every
      # source that predates it.
      assert Pramana.Sources.from_manifest(manifest(%{})).license.derivatives == true
    end

    defp manifest(license) do
      %Pramana.Local.Manifest{
        id: "nd-test",
        title: "x",
        title_en: "x",
        provenance: %{},
        citation: %{},
        format: "markdown",
        license: license
      }
    end
  end
end
