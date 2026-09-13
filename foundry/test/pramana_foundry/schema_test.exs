defmodule PramanaFoundry.SchemaTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.{CLI, Import, Schema}

  defp assignment do
    fixture("assignment-v1.json")
    |> File.read!()
    |> :json.decode()
  end

  test "accepts an exact supported assignment and checks identity" do
    value = assignment()

    assert {:ok, ^value} =
             Schema.validate(:assignment, value,
               task_id: "T1",
               run_id: "run-1",
               role: "developer"
             )

    assert {:error, %{reason: {:identity_mismatch, "run_id"}, evidence: ^value}} =
             Schema.validate(:assignment, value, run_id: "stale")

    missing_authority = Map.delete(value, "disabled_operations")

    assert {:error,
            %{reason: {:missing_fields, ["disabled_operations"]}, evidence: ^missing_authority}} =
             Schema.validate(:assignment, missing_authority)

    broadened = put_in(value, ["ticket", "required_checks"], [["sh", ""]])

    assert {:error, %{reason: {:invalid_type, "required_checks"}, evidence: ^broadened}} =
             Schema.validate(:assignment, broadened)

    contradictory = %{
      value
      | "disabled_operations" => ["remote_push"],
        "ticket" => %{value["ticket"] | "requested_operations" => ["remote_push"]}
    }

    assert {:error,
            %{reason: {:contradictory_authority, ["remote_push"]}, evidence: ^contradictory}} =
             Schema.validate(:assignment, contradictory)
  end

  test "no-opts assignment import and CLI reject contradictory internal task identity" do
    root = Path.join(System.tmp_dir!(), "assignment-#{System.unique_integer([:positive])}")
    path = Path.join(root, "assignment.json")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    contradictory = put_in(assignment(), ["ticket", "task_id"], "other-task")
    File.write!(path, :json.encode(contradictory))

    assert {:error,
            %{
              reason: {:identity_mismatch, "ticket.task_id"},
              evidence: ^contradictory,
              source_path: ^path
            }} = Import.read(path, :assignment)

    assert {:error,
            %{
              reason: {:identity_mismatch, "ticket.task_id"},
              evidence: ^contradictory,
              source_path: ^path
            }} = CLI.validate("assignment", path)
  end

  test "accepts production-shaped Python snapshot, control, and event records" do
    assert {:ok, snapshot} = Import.read(fixture("snapshot-v1.json"), :snapshot)
    assert snapshot["scheduler"]["dirty_reasons"] == ["startup"]

    assert {:ok, control} = Import.read(fixture("control-v1.json"), :control)
    assert control["action"] == "pause"
    assert control["payload"] == %{"fixture" => true}
    assert control["evidence"]["python_wire_record"]["created_at"] == "2026-09-08T00:00:00Z"

    assert {:ok, [event]} = Import.read_jsonl(fixture("event-v1.jsonl"), :event)

    assert Map.take(event, ~w(task_id run_id role)) == %{
             "task_id" => "T1",
             "run_id" => "run-1",
             "role" => "developer"
           }

    assert event["evidence"] == %{"diagnostic" => %{"kept" => true}}
  end

  test "accepts the human-issued planning-attempt reset control and no invented action" do
    # The Python supervisor writes this control into the same inbox these
    # records are imported from; an action missing from the allowlist here is
    # a record the port would refuse to read.
    reset = %{
      "action" => "reset_pm_attempts",
      "created_at" => "2026-09-09T00:00:00Z",
      "payload" => %{
        "authority" => "human",
        "revision" => String.duplicate("a", 40),
        "issued_by" => "operator@host",
        "issued_at" => "2026-09-09T00:00:00Z"
      }
    }

    assert {:ok, control} = Schema.validate(:control, reset)
    assert control["action"] == "reset_pm_attempts"
    assert control["payload"]["authority"] == "human"

    invented = %{reset | "action" => "reset_pm_attempts_now"}

    assert {:error, %{reason: {:invalid_value, "action"}, evidence: ^invented}} =
             Schema.validate(:control, invented)
  end

  test "fails closed on unknown authority fields and versions while preserving input" do
    unknown = Map.put(assignment(), "new_unreviewed_field", %{"proof" => 7})

    assert {:error, %{reason: {:unknown_fields, ["new_unreviewed_field"]}, evidence: ^unknown}} =
             Schema.validate(:assignment, unknown)

    unsupported = %{assignment() | "schema_version" => 2}

    assert {:error, %{reason: :unsupported_version, evidence: ^unsupported}} =
             Schema.validate(:assignment, unsupported)

    versioned_control = %{
      "schema_version" => 2,
      "action" => "pause",
      "created_at" => "2026-09-08T00:00:00Z",
      "payload" => nil
    }

    assert {:error, %{reason: :unsupported_version, evidence: ^versioned_control}} =
             Schema.validate(:control, versioned_control)

    authority_event = %{
      "event" => "assignment_admitted",
      "at" => "2026-09-08T00:00:00Z",
      "attributes" => %{"effect" => "deliver"}
    }

    assert {:error,
            %{reason: {:unknown_authority_fields, ["attributes"]}, evidence: ^authority_event}} =
             Schema.validate(:event, authority_event)
  end

  test "contains malformed, non-UTF8, and oversized JSON and JSONL artifacts" do
    root = Path.join(System.tmp_dir!(), "schema-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    malformed = Path.join(root, "malformed.json")
    File.write!(malformed, "{")
    assert {:error, %{reason: :malformed_json}} = Schema.decode_file(malformed, :assignment)

    invalid_utf8 = Path.join(root, "invalid.jsonl")
    File.write!(invalid_utf8, <<255>>)
    assert {:error, %{reason: :invalid_utf8}} = Import.read_jsonl(invalid_utf8, :event)

    oversized = Path.join(root, "large.json")
    File.write!(oversized, String.duplicate("x", 17))

    assert {:error, %{reason: :oversized}} =
             Schema.decode_file(oversized, :assignment, max_bytes: 16)

    malformed_jsonl = Path.join(root, "events.jsonl")
    File.write!(malformed_jsonl, "{\"event\":\"ok\",\"at\":\"now\"}\n{\n")

    assert {:error, %{reason: :malformed_json, line: 2, source_path: ^malformed_jsonl}} =
             Import.read_jsonl(malformed_jsonl, :event)
  end

  defp fixture(name), do: Path.expand("../fixtures/python/#{name}", __DIR__)
end
