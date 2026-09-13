defmodule Pramana.PublishingTest do
  @moduledoc """
  What may be published is a licensing decision, and the failure mode is silent: the wrong
  answer publishes text nobody had the right to publish, or withholds text that was public
  domain all along. 66,199 rows spent two phases in the second state.

  The audit itself needs a corpus and so is not tested here; `mix pramana.public.bake`
  runs it as its last step and fails the build on an unsafe result, which is the check
  that matters.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Translation
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Publishing

  describe "publishable?/1" do
    test "reads the licence from the source registry, not from a list kept here" do
      # A second list of "the public ones" is a list that goes stale the first time a
      # source's terms are re-read. These come from `Pramana.Sources`.
      assert Publishing.publishable?("sc")
      assert Publishing.publishable?("derge")
      assert Publishing.publishable?("derge-tengyur")
    end

    test "refuses the sources whose terms forbid redistribution" do
      # CBETA is non-commercial with the header intact; 84000's translations are ND.
      refute Publishing.publishable?("cbeta")
      refute Publishing.publishable?("84000")
      refute Publishing.publishable?("bdrc-derge")
    end

    test "an unknown source is not publishable" do
      # The safe direction for a source nobody has declared terms for.
      refute Publishing.publishable?("some-source-added-tomorrow")
    end
  end

  describe "sources/0" do
    test "is exactly the publishable half of the registry" do
      publishable = Publishing.sources()

      assert "sc" in publishable
      refute "cbeta" in publishable
      assert publishable == Enum.filter(publishable, &Publishing.publishable?/1)
      assert publishable == Enum.sort(publishable)
    end
  end

  describe "total/1" do
    test "sums a bucket" do
      assert Publishing.total([%{rows: 3}, %{rows: 4}]) == 7
      assert Publishing.total([]) == 0
    end
  end

  describe "audit/0" do
    test "reports safe? true and empty buckets on an empty database" do
      assert %{safe?: true, servable: [], forbidden: [], withheld: []} = Publishing.audit()
    end

    test "classifies redistributable text rows into servable" do
      Repo.insert!(%Witness{id: "W1", name: "Witness 1"})
      Repo.insert!(%Work{id: "work1"})

      Repo.insert!(%Source{
        id: "src_cc0",
        name: "CC0 Source",
        license_spdx: "CC0-1.0",
        redistributable: true
      })

      Repo.insert!(%Text{
        work_id: "work1",
        witness_id: "W1",
        source_id: "src_cc0",
        urn_prefix: "pramana:sc:work1",
        body: "text",
        body_sha256: "abc",
        char_count: 4
      })

      audit = Publishing.audit()
      assert audit.safe?
      assert audit.forbidden == []
      assert audit.withheld == []

      assert [
               %{
                 id: "src_cc0",
                 rows: 1,
                 redistributable: true,
                 spdx: "CC0-1.0",
                 name: "CC0 Source"
               }
             ] = audit.servable
    end

    test "classifies non-redistributable non-permissive text rows into forbidden (safe? false)" do
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

      audit = Publishing.audit()
      refute audit.safe?
      assert audit.servable == []
      assert audit.withheld == []

      assert [
               %{
                 id: "cbeta",
                 rows: 1,
                 redistributable: false,
                 spdx: "LicenseRef-CBETA-NC",
                 name: "CBETA"
               }
             ] = audit.forbidden
    end

    test "classifies non-redistributable permissive text rows into withheld (safe? true)" do
      Repo.insert!(%Witness{id: "W1", name: "Witness 1"})
      Repo.insert!(%Work{id: "work1"})

      Repo.insert!(%Source{
        id: "src_uncertain",
        name: "Uncertain CC0 Source",
        license_spdx: "CC0-1.0",
        redistributable: false
      })

      Repo.insert!(%Text{
        work_id: "work1",
        witness_id: "W1",
        source_id: "src_uncertain",
        urn_prefix: "pramana:sc:work1",
        body: "text",
        body_sha256: "abc",
        char_count: 4
      })

      audit = Publishing.audit()
      assert audit.safe?
      assert audit.servable == []
      assert audit.forbidden == []

      assert [
               %{
                 id: "src_uncertain",
                 rows: 1,
                 redistributable: false,
                 spdx: "CC0-1.0",
                 name: "Uncertain CC0 Source"
               }
             ] = audit.withheld
    end

    test "audits translations table into servable, withheld, and forbidden buckets" do
      # 1. Servable translation: redistributable true
      Repo.insert!(%Translation{
        anchor_urn: "pramana:sc.ms:mn1@1.1",
        work_id: "mn1",
        lang: "en",
        translator_id: "sujato",
        tier: "t0",
        method: "human",
        text: "Thus have I heard.",
        text_sha256: "sha1",
        license_spdx: "CC0-1.0",
        redistributable: true
      })

      # 2. Withheld translation: redistributable false, but permissive licence (CC-BY-4.0)
      Repo.insert!(%Translation{
        anchor_urn: "pramana:sc.ms:mn1@1.2",
        work_id: "mn1",
        lang: "en",
        translator_id: "bodhi",
        tier: "t0",
        method: "human",
        text: "I have heard.",
        text_sha256: "sha2",
        license_spdx: "CC-BY-4.0",
        redistributable: false
      })

      # 3. Forbidden translation: redistributable false, non-permissive licence
      Repo.insert!(%Translation{
        anchor_urn: "pramana:sc.ms:mn1@1.3",
        work_id: "mn1",
        lang: "en",
        translator_id: "restricted_author",
        tier: "t0",
        method: "human",
        text: "Restricted rendering.",
        text_sha256: "sha3",
        license_spdx: "CC-BY-NC-4.0",
        redistributable: false
      })

      audit = Publishing.audit()
      refute audit.safe?
      assert [%{id: "sujato", rows: 1, name: "translation layer"}] = audit.servable
      assert [%{id: "bodhi", rows: 1, name: "translation layer"}] = audit.withheld
      assert [%{id: "restricted_author", rows: 1, name: "translation layer"}] = audit.forbidden
    end
  end

  describe "Pramana.Publishing.Guard" do
    alias Pramana.Publishing.Guard

    test "public?/0 reflects PRAMANA_PUBLIC environment variable" do
      prev = System.get_env("PRAMANA_PUBLIC")

      on_exit(fn ->
        if prev,
          do: System.put_env("PRAMANA_PUBLIC", prev),
          else: System.delete_env("PRAMANA_PUBLIC")
      end)

      System.delete_env("PRAMANA_PUBLIC")
      refute Guard.public?()
      assert is_nil(Guard.child_spec_if_public())

      System.put_env("PRAMANA_PUBLIC", "1")
      assert Guard.public?()
      assert %{id: Guard, restart: :temporary} = Guard.child_spec_if_public()
    end

    test "verify/0 and verify_and_ignore/0 succeed on empty/safe database" do
      assert Guard.verify() == :ok
      assert Guard.verify_and_ignore() == :ignore
    end

    test "verify/0 returns error tuple when forbidden content is present" do
      Repo.insert!(%Source{
        id: "cbeta",
        name: "CBETA",
        license_spdx: "LicenseRef-CBETA-NC",
        redistributable: false
      })

      Repo.insert!(%Witness{id: "T", name: "Taishō"})
      Repo.insert!(%Work{id: "T0001"})

      Repo.insert!(%Text{
        work_id: "T0001",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T0001",
        body: "text",
        body_sha256: "sha",
        meta: %{}
      })

      assert {:error, [%{id: "cbeta"}]} = Guard.verify()
    end
  end
end
