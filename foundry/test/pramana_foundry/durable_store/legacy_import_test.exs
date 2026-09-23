defmodule PramanaFoundry.DurableStore.LegacyImportTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.DurableStore.{Database, Gateway, LegacyImport}

  setup do
    root = Path.join(System.tmp_dir!(), "legacy-import-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    path = Path.join(root, "authority.sqlite3")
    assert :ok = Gateway.initialize(path)
    %{root: root, path: path, archive: Path.join(root, "archive")}
  end

  test "torn and invalid records are retained with digest/range/error evidence", ctx do
    source = Path.join(ctx.root, "legacy.jsonl")
    valid = event("one")

    bytes =
      IO.iodata_to_binary([:json.encode(valid), "\n", "{broken}\n", :json.encode(event("torn"))])

    File.write!(source, bytes)

    assert {:ok, manifest} = LegacyImport.run(ctx.path, source, ctx.archive)
    assert manifest["source_bytes"] == byte_size(bytes)
    assert manifest["byte_range"] == %{"start" => 0, "end" => byte_size(bytes)}
    assert manifest["line_count"] == 3
    assert manifest["valid_count"] == 1
    assert manifest["invalid_count"] == 2
    assert Enum.map(manifest["errors"], & &1["error"]) == ["malformed_json", "unterminated_jsonl"]
    assert File.read!(manifest["archived_path"]) == bytes

    {:ok, conn} = Database.open(ctx.path)

    assert {:ok, [[3, total_bytes]]} =
             Database.query(conn, "SELECT count(*), sum(length(raw_record)) FROM legacy_records")

    assert total_bytes == byte_size(bytes)
    assert :ok = Database.close(conn)
  end

  test "rerun is idempotent and regenerates the external manifest", ctx do
    source = Path.join(ctx.root, "legacy.jsonl")
    File.write!(source, IO.iodata_to_binary([:json.encode(event("one")), "\n"]))

    assert {:ok, first} = LegacyImport.run(ctx.path, source, ctx.archive)
    File.rm!(first["manifest_path"])
    assert {:ok, second} = LegacyImport.run(ctx.path, source, ctx.archive)
    assert first["source_digest"] == second["source_digest"]
    assert File.exists?(second["manifest_path"])

    {:ok, conn} = Database.open(ctx.path)
    assert {:ok, [[1]]} = Database.query(conn, "SELECT count(*) FROM import_runs")
    assert {:ok, [[1]]} = Database.query(conn, "SELECT count(*) FROM legacy_records")
    assert :ok = Database.close(conn)
  end

  @tag timeout: 120_000
  test "streaming import accepts history larger than the legacy eight MiB reader limit", ctx do
    source = Path.join(ctx.root, "large.jsonl")
    padding = String.duplicate("x", 16 * 1024)
    record = event("large") |> put_in(["evidence"], %{"padding" => padding})
    encoded = IO.iodata_to_binary([:json.encode(record), "\n"])
    copies = div(PramanaFoundry.Schema.max_bytes(), byte_size(encoded)) + 2

    {:ok, file} = File.open(source, [:write, :binary])
    Enum.each(1..copies, fn _ -> IO.binwrite(file, encoded) end)
    File.close(file)
    assert File.stat!(source).size > PramanaFoundry.Schema.max_bytes()

    assert {:ok, manifest} = LegacyImport.run(ctx.path, source, ctx.archive)
    assert manifest["line_count"] == copies
    assert manifest["valid_count"] == copies
    assert manifest["invalid_count"] == 0
    assert File.stat!(manifest["archived_path"]).size == File.stat!(source).size

    expected_digest =
      source
      |> File.stream!(64 * 1024, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    assert manifest["source_digest"] == expected_digest
    middle = div(copies, 2)
    {:ok, conn} = Database.open(ctx.path)

    assert {:ok, rows} =
             Database.query(
               conn,
               "SELECT line_number, raw_record FROM legacy_records WHERE line_number IN (?, ?, ?) ORDER BY line_number",
               [1, middle, copies]
             )

    assert rows == [[1, encoded], [middle, encoded], [copies, encoded]]
    assert :ok = Database.close(conn)

    gateway = start_supervised!({Gateway, path: ctx.path})
    backup = Path.join(ctx.root, "large-backup.sqlite3")
    assert {:ok, %{content: content}} = Gateway.backup(gateway, backup)
    assert content["legacy_records"].count == copies
    assert :ok = stop_supervised(Gateway)

    reopened = start_supervised!({Gateway, path: ctx.path})
    assert %{mode: :ready} = Gateway.status(reopened)

    assert {:ok, %{content: reopened_content}} =
             Gateway.backup(reopened, Path.join(ctx.root, "large-reopened-backup.sqlite3"))

    assert reopened_content["legacy_records"].count == copies
  end

  test "unknown legacy versions are reported and preserved, never imported as authority", ctx do
    source = Path.join(ctx.root, "unknown.jsonl")
    unknown = %{event("unknown") | "schema_version" => 99}
    bytes = IO.iodata_to_binary([:json.encode(unknown), "\n"])
    File.write!(source, bytes)

    assert {:ok, %{"valid_count" => 0, "invalid_count" => 1, "errors" => [error]} = manifest} =
             LegacyImport.run(ctx.path, source, ctx.archive)

    assert String.starts_with?(error["error"], "schema:")
    assert File.read!(manifest["archived_path"]) == bytes

    gateway = start_supervised!({Gateway, path: ctx.path})
    assert {:ok, %{"commands" => 0, "events" => 0}} = Gateway.counts(gateway)
  end

  test "aliases are rejected before publication and the original is unchanged", ctx do
    source = Path.join(ctx.root, "alias.jsonl")
    bytes = IO.iodata_to_binary([:json.encode(event("alias")), "\n"])
    File.write!(source, bytes)

    assert {:error, :import_path_collision} =
             LegacyImport.run(ctx.path, source, ctx.archive, manifest_path: source)

    assert File.read!(source) == bytes

    hardlink = Path.join(ctx.root, "database-hardlink")
    File.ln!(ctx.path, hardlink)

    assert {:error, :database_hardlink_not_allowed} =
             LegacyImport.run(ctx.path, source, ctx.archive, manifest_path: hardlink)

    assert File.read!(source) == bytes
  end

  test "import owns the store offline and reads the verified archive", ctx do
    source = Path.join(ctx.root, "offline.jsonl")
    original = IO.iodata_to_binary([:json.encode(event("original")), "\n"])
    File.write!(source, original)
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:error, {:store_owner_unavailable, "database is locked"}} =
             LegacyImport.run(ctx.path, source, ctx.archive)

    assert :ok = stop_supervised(Gateway)
    assert {:ok, manifest} = LegacyImport.run(ctx.path, source, ctx.archive)
    File.write!(source, IO.iodata_to_binary([:json.encode(event("changed")), "\n"]))

    {:ok, conn} = Database.open(ctx.path)
    assert {:ok, [[stored]]} = Database.query(conn, "SELECT raw_record FROM legacy_records")
    assert stored == original
    assert File.read!(manifest["archived_path"]) == original
    assert :ok = Database.close(conn)
    refute Process.alive?(gateway)
  end

  test "interrupted import rolls back and reruns, and manifest publication can rerun", ctx do
    source = Path.join(ctx.root, "interrupt.jsonl")

    bytes =
      IO.iodata_to_binary([:json.encode(event("one")), "\n", :json.encode(event("two")), "\n"])

    File.write!(source, bytes)

    assert {:error, {:injected_import_interruption, 1}} =
             LegacyImport.run(ctx.path, source, ctx.archive, fail_after_lines: 1)

    {:ok, conn} = Database.open(ctx.path)
    assert {:ok, [[0]]} = Database.query(conn, "SELECT count(*) FROM import_runs")
    assert {:ok, [[0]]} = Database.query(conn, "SELECT count(*) FROM legacy_records")
    assert :ok = Database.close(conn)

    assert {:error, {:injected_crash, :after_temp}} =
             LegacyImport.run(ctx.path, source, ctx.archive,
               manifest_write_opts: [crash_at: :after_temp, txid: "publication-failure"]
             )

    unrelated = Path.join(ctx.archive, ".import-manifest.json.unrelated.tmp")
    File.write!(unrelated, "foreign publication state")

    assert {:ok, manifest} = LegacyImport.run(ctx.path, source, ctx.archive)
    assert manifest["line_count"] == 2
    assert File.exists?(manifest["manifest_path"])
    assert File.read!(unrelated) == "foreign publication state"

    {:ok, conn} = Database.open(ctx.path)
    assert {:ok, [[1]]} = Database.query(conn, "SELECT count(*) FROM import_runs")
    assert {:ok, [[2]]} = Database.query(conn, "SELECT count(*) FROM legacy_records")
    assert :ok = Database.close(conn)
  end

  test "archive mutation during import rolls back all retained evidence", ctx do
    source = Path.join(ctx.root, "mutated-archive.jsonl")
    original = IO.iodata_to_binary([:json.encode(event("one")), "\n"])
    File.write!(source, original)

    mutate = fn archived_path ->
      File.write!(archived_path, original <> "foreign")
      :ok
    end

    digest = &Base.encode16(:crypto.hash(:sha256, &1), case: :lower)
    mutated_digest = digest.(original <> "foreign")
    original_digest = digest.(original)

    assert {:error, {:archive_digest_mismatch, ^mutated_digest, ^original_digest}} =
             LegacyImport.run(ctx.path, source, ctx.archive, after_import_lines: mutate)

    {:ok, conn} = Database.open(ctx.path)

    assert {:ok, [[0, 0]]} =
             Database.query(
               conn,
               "SELECT (SELECT count(*) FROM import_runs), (SELECT count(*) FROM legacy_records)"
             )

    assert :ok = Database.close(conn)
  end

  defp event(name) do
    %{
      "schema_version" => 1,
      "event" => name,
      "at" => "2026-09-13T00:00:00Z",
      "attributes" => %{},
      "evidence" => %{}
    }
  end
end
