defmodule Mix.Tasks.Pramana.Public.CheckTest do
  @moduledoc """
  Tests for `mix pramana.public.check`.

  Verifies that the public check Mix task correctly formats and presents
  the licensing audit across safe, forbidden, and withheld scenarios.
  """
  use Pramana.DataCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Pramana.Public.Check
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Translation
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work

  test "reports SAFE on an empty database" do
    output = capture_io(fn -> Check.run([]) end)

    assert output =~ "SAFE TO SERVE PUBLICLY"
    assert output =~ "(nothing)"
    assert output =~ "FORBIDDEN BY LICENCE"
    assert output =~ "WITHHELD BY UNCERTAINTY"
    assert output =~ "✓ SAFE. Nothing here is forbidden by its licence (0 rows servable)."
  end

  test "reports SAFE with servable rows when all content is redistributable" do
    Repo.insert!(%Witness{id: "W1", name: "Witness 1"})
    Repo.insert!(%Work{id: "work1"})

    Repo.insert!(%Source{
      id: "sc",
      name: "SuttaCentral",
      license_spdx: "CC0-1.0",
      redistributable: true
    })

    Repo.insert!(%Text{
      work_id: "work1",
      witness_id: "W1",
      source_id: "sc",
      urn_prefix: "pramana:sc:work1",
      body: "text",
      body_sha256: "abc",
      char_count: 4
    })

    output = capture_io(fn -> Check.run([]) end)

    assert output =~ "SAFE TO SERVE PUBLICLY"
    assert output =~ "sc"
    assert output =~ "1 row(s)"
    assert output =~ "CC0-1.0"
    assert output =~ "SuttaCentral"
    assert output =~ "✓ SAFE. Nothing here is forbidden by its licence (1 rows servable)."
    refute output =~ "further rows carry a permissive licence"
  end

  test "reports NOT SAFE TO EXPOSE when forbidden content is present" do
    Repo.insert!(%Witness{id: "W1", name: "Witness 1"})
    Repo.insert!(%Work{id: "work1"})

    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      redistributable: false
    })

    Repo.insert!(%Text{
      work_id: "work1",
      witness_id: "W1",
      source_id: "cbeta",
      urn_prefix: "pramana:cbeta.T:T0001",
      body: "text",
      body_sha256: "abc",
      char_count: 4
    })

    output = capture_io(fn -> Check.run([]) end)

    assert output =~ "FORBIDDEN BY LICENCE"
    assert output =~ "cbeta"
    assert output =~ "LicenseRef-CBETA-NC"
    assert output =~ "✗ NOT SAFE TO EXPOSE"
    assert output =~ "1 of 1 rows come from 1 source(s)"
    assert output =~ "whose licence forbids redistribution."
  end

  test "reports withheld rows with caution note when permissive text is not confirmed" do
    Repo.insert!(%Witness{id: "W1", name: "Witness 1"})
    Repo.insert!(%Work{id: "work1"})

    Repo.insert!(%Source{
      id: "sujato_unconfirmed",
      name: "Unconfirmed SC",
      license_spdx: "CC0-1.0",
      redistributable: false
    })

    Repo.insert!(%Text{
      work_id: "work1",
      witness_id: "W1",
      source_id: "sujato_unconfirmed",
      urn_prefix: "pramana:sc:work1",
      body: "text",
      body_sha256: "abc",
      char_count: 4
    })

    output = capture_io(fn -> Check.run([]) end)

    assert output =~ "WITHHELD BY UNCERTAINTY"
    assert output =~ "sujato_unconfirmed"
    assert output =~ "✓ SAFE."
    assert output =~ "1 further rows carry a permissive licence and are still withheld"
  end

  test "reports both forbidden and withheld rows together" do
    Repo.insert!(%Witness{id: "W1", name: "Witness 1"})
    Repo.insert!(%Work{id: "work1"})

    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      redistributable: false
    })

    Repo.insert!(%Text{
      work_id: "work1",
      witness_id: "W1",
      source_id: "cbeta",
      urn_prefix: "pramana:cbeta.T:T0001",
      body: "text",
      body_sha256: "abc",
      char_count: 4
    })

    Repo.insert!(%Translation{
      anchor_urn: "pramana:sc.ms:mn1@1.1",
      work_id: "work1",
      lang: "en",
      translator_id: "bodhi",
      tier: "t0",
      method: "human",
      text: "I have heard.",
      text_sha256: "sha2",
      license_spdx: "CC-BY-4.0",
      redistributable: false
    })

    output = capture_io(fn -> Check.run([]) end)

    assert output =~ "✗ NOT SAFE TO EXPOSE"
    assert output =~ "1 of 2 rows come from 1 source(s)"
    assert output =~ "1 further rows carry a permissive licence and are still withheld"
  end
end
