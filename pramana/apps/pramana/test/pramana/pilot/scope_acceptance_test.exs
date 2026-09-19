defmodule Pramana.Pilot.ScopeAcceptanceTest do
  @moduledoc """
  Database-backed acceptance for the live scope materializer boundary.

  Pure scope fixtures test ranking and traversal. This test exercises the selected-release
  check, repeatable-read materialization and drift refusal against actual PostgreSQL tables
  in a disposable schema. It does not use the research corpus.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Pramana.Bake
  alias Pramana.Corpus.Bake, as: BakeSchema
  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Pilot.Scope
  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Release
  alias Pramana.Repo

  @tables ~w(
    sources
    witnesses
    works
    texts
    bakes
    translations
    chunks
    chunk_vectors
    releases
    release_selection
    quotations
    work_relations
    commentary_alignments
  )

  setup do
    schema = "pramana_pilot_scope_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Repo.put_dynamic_repo(Repo)

      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DROP SCHEMA IF EXISTS #{schema} CASCADE")
      end)
    end)

    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("CREATE SCHEMA #{schema}")

      Enum.each(@tables, fn table ->
        Repo.query!("CREATE TABLE #{schema}.#{table} (LIKE public.#{table} INCLUDING ALL)")
      end)
    end)

    config =
      Repo.config()
      |> Keyword.merge(
        name: nil,
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        parameters: [search_path: "#{schema},public"]
      )

    repo = start_supervised!({Repo, config}, id: {:pilot_scope_acceptance, schema})
    Repo.put_dynamic_repo(repo)

    assert %{rows: [[^schema]]} = Repo.query!("SELECT current_schema()")

    seed_source_and_witness!()
    seed_bake!("a", ~U[2026-09-18 01:00:00.000000Z])
    seed_demand_graph!()

    {:ok, release} = Release.stamp()
    assert Release.current_id() == release.release_id
    assert Release.drift() == :current

    %{release: release}
  end

  test "materializes the exact selected current release and refuses mismatch or drift", %{
    release: release
  } do
    assert {:ok, artifact} = Scope.materialize(release.release_id)
    assert :ok = ScopeArtifact.validate(artifact)

    assert artifact["release"]["release_id"] == release.release_id
    assert artifact["release"]["source_bake_id"] == release.source_bake_id
    assert artifact["denominators"]["demand_seed_count"] == 10
    assert artifact["denominators"]["combined_seed_count"] == 14

    release_id = release.release_id

    assert {:error, {:release_mismatch, "wrong-release", ^release_id}} =
             Scope.materialize("wrong-release")

    newer = seed_bake!("b", ~U[2026-09-18 02:00:00.000000Z])

    assert {:error, {:release_drift, drift}} = Scope.materialize(release.release_id)

    assert drift.source_bake_id == %{
             stamped: release.source_bake_id,
             live: newer.id
           }
  end

  defp seed_source_and_witness! do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Witness{id: "T", name: "Taishō"})
  end

  defp seed_bake!(digit, built_at) do
    Repo.insert!(%BakeSchema{
      id: String.duplicate(digit, 64),
      pipeline_version: Bake.pipeline_version(),
      sources_lock_sha256: String.duplicate("c", 64),
      config: %{},
      stats: %{},
      built_at: built_at
    })
  end

  defp seed_demand_graph! do
    Enum.each(
      [
        {"T0001", "長阿含經"},
        {"T0026", "中阿含經"},
        {"T0099", "雜阿含經"},
        {"T0125", "增壹阿含經"}
      ],
      fn {work_id, title} ->
        seed_text!(work_id, "root", title, "阿含部", 100)
      end
    )

    roots =
      Enum.map(0..9, fn n ->
        work_id = "T02" <> String.pad_leading(Integer.to_string(n), 2, "0")
        {work_id, seed_text!(work_id, "root", "demand #{n}", "經集部", 100 + n)}
      end)

    citers =
      Enum.map(0..9, fn n ->
        work_id = "T17" <> String.pad_leading(Integer.to_string(n), 2, "0")
        {work_id, seed_text!(work_id, "commentary", "citer #{n}", "經疏部", 500 + n)}
      end)

    Enum.zip(citers, roots)
    |> Enum.with_index()
    |> Enum.each(fn {{{citer_work, citer_text}, {root_work, root_text}}, n} ->
      text = "abcdefghijklmnopqrst#{n}"
      digest = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

      Repo.insert!(%Quotation{
        text: text,
        text_sha256: digest,
        length: String.length(text),
        a_text_id: citer_text.id,
        a_work_id: citer_work,
        a_urn: "pramana:cbeta.T:#{citer_work}_001@p0001a01",
        a_char_start: 0,
        a_char_end: String.length(text),
        b_text_id: root_text.id,
        b_work_id: root_work,
        b_urn: "pramana:cbeta.T:#{root_work}_001@p0001a01",
        b_char_start: 0,
        b_char_end: String.length(text),
        bake_id: String.duplicate("a", 64),
        meta: %{}
      })
    end)
  end

  defp seed_text!(work_id, role, title, division, date_start) do
    Repo.insert!(%Work{
      id: work_id,
      title: title,
      composition_origin: "indic",
      text_role: role,
      division: division,
      date_start: date_start,
      date_end: date_start + 50,
      date_basis: "catalogue",
      meta: %{}
    })

    Repo.insert!(%Text{
      work_id: work_id,
      witness_id: "T",
      source_id: "cbeta",
      urn_prefix: "pramana:cbeta.T:#{work_id}",
      body: "",
      body_sha256: hash(""),
      char_count: 0,
      meta: %{},
      outline: %{}
    })
  end

  defp hash(value),
    do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
