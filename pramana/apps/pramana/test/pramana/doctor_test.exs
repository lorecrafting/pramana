defmodule Mix.Tasks.Pramana.DoctorTest do
  @moduledoc """
  The command a session opens with must not be the thing that breaks.

  There is little logic here to test — `doctor` composes figures other modules compute — so
  what is pinned is that it **runs against an empty corpus without raising** and still says
  something true. A diagnostic that only works once everything is loaded is useless at
  exactly the moment it is needed.
  """
  use Pramana.DataCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pramana.Doctor

  test "runs on an empty corpus and reports the absence rather than crashing" do
    output = capture_io(fn -> Doctor.run([]) end)

    assert output =~ "bake"
    assert output =~ "no bake recorded"
    assert output =~ "corpus"
    assert output =~ "sources"
    assert output =~ "migrations"
  end

  test "names every declared source, including ones never acquired" do
    # A source declared and never acquired is a normal state — SAT has been one for phases —
    # and it is exactly what a session needs before wondering why a search returns nothing.
    output = capture_io(fn -> Doctor.run([]) end)

    for id <- Pramana.Sources.ids() do
      assert output =~ id, "#{id} is declared and absent from the report"
    end
  end

  test "leads with whether the bake still describes its inputs" do
    # It invalidates everything printed below it, so it is first. Acquisition rewrites the
    # lockfile and only a bake writes the row; that gap was real for weeks (rule 64).
    output = capture_io(fn -> Doctor.run([]) end)

    bake_at = :binary.match(output, "bake") |> elem(0)
    corpus_at = :binary.match(output, "corpus") |> elem(0)

    assert bake_at < corpus_at
  end

  test "reports current bake, release and corpus counts when data is populated" do
    now = DateTime.utc_now()

    Repo.insert!(%Pramana.Corpus.Witness{id: "T", name: "Taishō"})
    Repo.insert!(%Pramana.Corpus.Work{id: "T0001"})

    Repo.insert!(%Pramana.Corpus.Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      redistributable: false
    })

    Repo.insert!(%Pramana.Corpus.Text{
      work_id: "T0001",
      witness_id: "T",
      source_id: "cbeta",
      urn_prefix: "pramana:cbeta.T:T0001",
      body: "test text",
      body_sha256: "hash",
      char_count: 9
    })

    Repo.insert!(%Pramana.Corpus.Bake{
      id: "bake-1234567890abcdef",
      pipeline_version: "1.0.0",
      sources_lock_sha256: "test-sha",
      built_at: now,
      stats: %{"chars" => 12_345}
    })

    release =
      Repo.insert!(%Pramana.Corpus.Release{
        release_id: "rel-1234567890abcdef",
        source_bake_id: "bake-1234567890abcdef",
        translation_set_id: "tset-1",
        vector_set_id: "vset-1",
        translations_count: 0,
        vectors_count: 0,
        embedding_models: [],
        translators: [],
        stamped_at: now
      })

    Repo.insert!(%Pramana.Release.Selection{id: 1, release_id: release.id, selected_at: now})

    output = capture_io(fn -> Doctor.run([]) end)

    assert output =~ "release"
    assert output =~ "rel-1234567890ab"
    assert output =~ "stamp still describes the corpus"
    assert output =~ "bake-1234567890a"
    assert output =~ "12345 (as recorded at bake time)"
    assert output =~ "cbeta / T"
  end

  test "reports drift when the corpus has moved since the release was stamped" do
    now = DateTime.utc_now()

    release =
      Repo.insert!(%Pramana.Corpus.Release{
        release_id: "rel-1234567890abcdef",
        source_bake_id: "bake-old",
        translation_set_id: "tset-1",
        vector_set_id: "vset-1",
        translations_count: 42,
        vectors_count: 0,
        embedding_models: [],
        translators: [],
        stamped_at: now
      })

    Repo.insert!(%Pramana.Release.Selection{id: 1, release_id: release.id, selected_at: now})

    output = capture_io(fn -> Doctor.run([]) end)

    assert output =~ "STALE — the corpus moved since it was stamped"
    assert output =~ "translations_count"
    assert output =~ "42 -> 0"
  end
end
