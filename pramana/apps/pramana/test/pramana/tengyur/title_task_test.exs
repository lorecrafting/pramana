defmodule Pramana.Tengyur.TitleTaskTest do
  # Actual Mix task startup must not race the parallel test-file loader.
  use Pramana.DataCase, async: false

  alias Mix.Tasks.Pramana.Tengyur.Titles, as: TitlesTask
  alias Pramana.Corpus.Work
  alias Pramana.Repo

  test "dry-run preserves rows and bytes; explicit ordinary execution writes only uncurated source titles" do
    Repo.insert!(%Pramana.Corpus.Source{
      id: "derge-tengyur",
      name: "fixture",
      license_spdx: "CC-PDM-1.0",
      license_class: "public-domain",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Pramana.Corpus.Witness{id: "D", name: "Derge"})

    work =
      Repo.insert!(%Work{
        id: "toh1114",
        title: "Curated English",
        meta: %{"curator" => "preserved"}
      })

    %{text: text} =
      Pramana.CorpusFixtures.text!(
        %{
          work_id: work.id,
          source_id: "derge-tengyur",
          witness_id: "D",
          urn_prefix: "pramana:derge-tengyur.D:toh1114",
          meta: %{}
        },
        [{"pramana:derge-tengyur.D:toh1114@1.1a.1", "རྒྱ་གར་སྐད་དུ། བུདྡྷ། བོད་སྐད་དུ། སངས་རྒྱས།"}]
      )

    run(["--dry-run"])
    assert Repo.get!(Work, work.id) == work
    assert Repo.get!(Pramana.Corpus.Text, text.id) == text
    run([])
    written = Repo.get!(Work, work.id)
    assert written.title_original == "སངས་རྒྱས"
    assert written.title == "Curated English"
    assert written.meta["curator"] == "preserved"
    assert Repo.get!(Pramana.Corpus.Text, text.id) == text
    run([])
    assert Repo.get!(Work, work.id) == written
  end

  defp run(args),
    do: ExUnit.CaptureIO.capture_io(fn -> TitlesTask.run(args) end)
end
