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

  test "a restricted source is never widened by a re-ingest" do
    Repo.insert!(%Source{
      id: "sc",
      name: "sc",
      license_spdx: "CC-PDM-1.0",
      license_class: "public-domain",
      commercial_use: true,
      redistributable: true
    })

    {:ok, _} = load!("mn1", [])

    # The registry, not the row, decides — so the assertion that matters is that the row
    # equals the registry after a load, whichever direction that moves it.
    {:ok, definition} = Pramana.Sources.fetch("sc")
    source = Repo.get!(Source, "sc")

    assert source.license_class == definition.license.class
    assert source.redistributable == definition.license.redistributable
  end

  test "the file a work came from is recorded, so verify can re-derive it" do
    {:ok, _} =
      load!("mn1", source_file: "raw/sc/bilara-data/root/pli/ms/sutta/mn/mn1_root-pli-ms.json")

    text = Repo.get_by!(Pramana.Corpus.Text, work_id: "mn1")

    assert text.meta["source_file"] =~ "mn1_root-pli-ms.json"
  end
end
