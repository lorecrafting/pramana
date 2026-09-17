defmodule Pramana.ReleaseAcceptanceTest do
  @moduledoc """
  Real multi-connection PostgreSQL acceptance in disposable, empty schemas.

  Runs the actual release-history and selection migrations, not copied DDL/DML.
  Uses a separate pool rather than sharing a Sandbox transaction across writers.
  No production database, acquired corpus or public-schema rows are modified.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Pramana.Corpus.Bake, as: BakeSchema
  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Release
  alias Pramana.Repo
  alias Pramana.Repo.Migrations.CreateReleases
  alias Pramana.Repo.Migrations.SelectCurrentRelease

  @history_version 20_260_904_120_001
  @selection_version 20_260_916_060_759

  for {module, filename} <- [
        {CreateReleases, "20260904120001_create_releases.exs"},
        {SelectCurrentRelease, "20260916060759_select_current_release.exs"}
      ] do
    unless Code.ensure_loaded?(module) do
      Code.require_file(Path.expand("../../priv/repo/migrations/#{filename}", __DIR__))
    end
  end

  setup do
    schema = "pramana_release_acceptance_#{System.unique_integer([:positive])}"

    # on_exit executes after supervised connections have stopped; this pool remains
    # the ordinary test Repo and cannot retain a transaction into the next test.
    on_exit(fn ->
      Repo.put_dynamic_repo(Repo)
      Sandbox.unboxed_run(Repo, fn -> Repo.query!("DROP SCHEMA IF EXISTS #{schema} CASCADE") end)
    end)

    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("CREATE SCHEMA #{schema}")

      for table <- ["bakes", "translations", "chunk_vectors"] do
        Repo.query!("CREATE TABLE #{schema}.#{table} (LIKE public.#{table} INCLUDING ALL)")
      end
    end)

    config =
      Repo.config()
      |> Keyword.merge(
        name: nil,
        pool: DBConnection.ConnectionPool,
        pool_size: 4,
        parameters: [search_path: "#{schema},public"]
      )

    repo = start_supervised!({Repo, config}, id: {:release_acceptance, schema})
    Repo.put_dynamic_repo(repo)
    assert %{rows: [[^schema]]} = Repo.query!("SELECT current_schema()")
    opts = [dynamic_repo: repo, prefix: schema, log: false]
    assert :ok = Ecto.Migrator.up(Repo, @history_version, CreateReleases, opts)
    %{repo: repo, schema: schema, opts: opts}
  end

  test "legacy history upgrades to v2 without rewriting v1 rows and survives up/down/up", %{
    schema: schema,
    opts: opts
  } do
    bake!("a", ~U[2026-01-01 00:00:00.000000Z])
    a = legacy_stamp!(~U[2026-01-01 00:00:00.000000Z])
    bake_b = bake!("b", ~U[2026-01-02 00:00:00.000000Z])
    b = legacy_stamp!(~U[2026-01-02 00:00:00.000000Z])

    # The last old writer completed before migration/backfill, as the runbook requires.
    assert :ok = Ecto.Migrator.up(Repo, @selection_version, SelectCurrentRelease, opts)
    assert Release.current() == b
    assert Release.drift() == %{
             identity_version: %{stamped: "v1/coarse", live: "v2"}
           }
    Repo.delete!(bake_b)

    assert %{
             identity_version: %{stamped: "v1/coarse", live: "v2"},
             source_bake_id: %{stamped: stamped_source, live: live_source}
           } = Release.drift()

    assert stamped_source == b.source_bake_id
    assert live_source == a.source_bake_id
    assert {:ok, a_v2} = Release.stamp()
    refute a_v2.id == a.id
    assert a_v2.source_bake_id == a.source_bake_id
    assert String.starts_with?(a_v2.translation_set_id, "v2:")
    assert String.starts_with?(a_v2.vector_set_id, "v2:")
    assert Release.current() == a_v2
    assert Repo.aggregate(ReleaseSchema, :count) == 3

    assert :ok = Ecto.Migrator.down(Repo, @selection_version, SelectCurrentRelease, opts)

    assert %{rows: [[nil]]} =
             Repo.query!("SELECT to_regclass($1)", ["#{schema}.release_selection"])

    assert Repo.get!(ReleaseSchema, a.id) == a
    assert Repo.get!(ReleaseSchema, b.id) == b
    assert Repo.one(from(r in ReleaseSchema, order_by: [desc: r.stamped_at], limit: 1)) == a_v2

    assert :ok = Ecto.Migrator.up(Repo, @selection_version, SelectCurrentRelease, opts)
    assert Release.current() == a_v2
    assert Release.drift() == :current
    # Explicit stamping is idempotent once the v2 content state is selected.
    assert {:ok, ^a_v2} = Release.stamp()
    assert Release.current() == a_v2
    assert Repo.aggregate(ReleaseSchema, :count) == 3
  end

  test "empty history remains unstamped through up/down/up, and singleton/FK constraints execute",
       %{opts: opts} do
    assert :ok = Ecto.Migrator.up(Repo, @selection_version, SelectCurrentRelease, opts)
    assert Release.current() == nil
    assert :ok = Ecto.Migrator.down(Repo, @selection_version, SelectCurrentRelease, opts)
    assert :ok = Ecto.Migrator.up(Repo, @selection_version, SelectCurrentRelease, opts)
    assert Release.current() == nil
    assert Repo.aggregate(ReleaseSchema, :count) == 0
    {:ok, release} = Release.stamp()

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!("INSERT INTO release_selection VALUES (2, $1, now())", [release.id])
      end

    assert error.postgres.code == :check_violation
    Repo.query!("DELETE FROM release_selection")

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!("INSERT INTO release_selection VALUES (1, -1, now())")
      end

    assert error.postgres.code == :foreign_key_violation
  end

  test "a second stamper waits before sampling, then selects the newer committed observation", %{
    repo: repo,
    opts: opts
  } do
    assert :ok = Ecto.Migrator.up(Repo, @selection_version, SelectCurrentRelease, opts)
    a = bake!("a", ~U[2026-01-01 00:00:00.000000Z])
    supervisor = start_supervised!({Task.Supervisor, []})
    token = make_ref()
    parent = self()

    :ok =
      :telemetry.attach(
        token,
        [:pramana, :repo, :query],
        &__MODULE__.sampling_barrier/4,
        {parent, token}
      )

    on_exit(fn -> :telemetry.detach(token) end)

    first = start_stamp(supervisor, repo, parent, token, true)
    assert_receive {:backend, ^token, first_backend}, 5_000
    assert_receive {:sampled, ^token, first_worker}, 5_000
    b = bake!("b", ~U[2026-01-02 00:00:00.000000Z])
    second_token = make_ref()
    second = start_stamp(supervisor, repo, parent, second_token, false)
    assert_receive {:backend, ^second_token, second_backend}, 5_000
    refute first_backend == second_backend

    assert_waiting_before_sampling(
      second_backend,
      second_token,
      System.monotonic_time(:millisecond) + 5_000
    )

    send(first_worker, {:continue, token})
    assert {:ok, first_release} = Task.await(first, 5_000)
    assert {:ok, second_release} = Task.await(second, 5_000)
    assert first_release.source_bake_id == a.id
    assert second_release.source_bake_id == b.id
    assert Release.current() == second_release
    assert Release.drift() == :current
    assert Repo.aggregate(ReleaseSchema, :count) == 2
  end

  test "transaction rollback releases the writer lock and preserves the old selection", %{
    opts: opts
  } do
    assert :ok = Ecto.Migrator.up(Repo, @selection_version, SelectCurrentRelease, opts)
    {:ok, a} = Release.stamp()
    bake!("b", ~U[2026-01-02 00:00:00.000000Z])

    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               {:ok, _b} = Release.stamp()
               Repo.rollback(:cancelled)
             end)

    assert Release.current() == a
    assert Repo.aggregate(ReleaseSchema, :count) == 1
    assert {:ok, b} = Release.stamp()
    assert b.id != a.id
    assert Release.current() == b
  end

  @doc false
  def sampling_barrier(_event, _measurements, meta, {parent, token}) do
    if Process.get(:release_sampling_barrier) == token and
         String.contains?(meta.query, "DISTINCT") and
         String.contains?(meta.query, "translator_id") do
      Process.delete(:release_sampling_barrier)
      send(parent, {:sampled, token, self()})

      receive do
        {:continue, ^token} -> :ok
      after
        5_000 -> raise "release sampling barrier was not released"
      end
    end
  end

  defp start_stamp(supervisor, repo, parent, token, pause?) do
    Task.Supervisor.async_nolink(supervisor, fn ->
      Repo.put_dynamic_repo(repo)
      if pause?, do: Process.put(:release_sampling_barrier, token)

      result =
        Repo.transaction(fn ->
          %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:backend, token, backend})
          {:ok, release} = Release.stamp()
          release
        end)

      send(parent, {:completed, token, result})
      result
    end)
  end

  # Database-visible waiting, not a sleep-based claim that two tasks overlapped.
  defp assert_waiting_before_sampling(backend, token, deadline) do
    %{rows: [[waiting?]]} =
      Repo.query!(
        "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = $1 AND locktype = 'advisory' AND NOT granted)",
        [backend]
      )

    if waiting? do
      :ok
    else
      receive do
        {:completed, ^token, _} -> flunk("second stamper sampled without waiting for the first")
      after
        0 ->
          assert System.monotonic_time(:millisecond) < deadline,
                 "stamper did not wait on its advisory lock"

          assert_waiting_before_sampling(backend, token, deadline)
      end
    end
  end

  defp bake!(digit, time) do
    Repo.insert!(%BakeSchema{
      id: String.duplicate(digit, 64),
      pipeline_version: Pramana.Bake.pipeline_version(),
      sources_lock_sha256: String.duplicate("c", 64),
      built_at: time
    })
  end

  # Model the OLD writer independently of the current Release.ids/0 implementation.
  # Calling current code here would make this fixture silently become v2 the day the
  # identity algorithm changes, which defeats the migration test's entire purpose.
  defp legacy_stamp!(time) do
    source_bake_id = Pramana.Bake.current_id()
    translation_set_id = "legacy-translations"
    vector_set_id = "legacy-vectors"

    release_id =
      ["legacy-release", source_bake_id, translation_set_id, vector_set_id]
      |> Enum.map_join("|", &inspect/1)
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Repo.insert!(%ReleaseSchema{
      release_id: release_id,
      source_bake_id: source_bake_id,
      translation_set_id: translation_set_id,
      vector_set_id: vector_set_id,
      translations_count: 0,
      vectors_count: 0,
      embedding_models: [],
      translators: [],
      stamped_at: time
    })
  end
end
