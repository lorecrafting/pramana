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
