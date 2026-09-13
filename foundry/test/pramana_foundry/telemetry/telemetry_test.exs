defmodule PramanaFoundry.Telemetry.TelemetryTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Exports.TelemetryExport
  alias PramanaFoundry.Telemetry.{Store, Telemetry}

  test "LLM metrics preserve unavailable values and reject sensitive bodies" do
    attrs = llm_attrs()
    assert {:ok, record} = Telemetry.llm(attrs)

    assert record["metrics"]["prompt_input_tokens"] == %{
             "value" => 120,
             "source" => "provider",
             "quality" => "exact"
           }

    assert record["metrics"]["reasoning_tokens"] == %{
             "value" => :null,
             "source" => "unavailable",
             "quality" => "unavailable"
           }

    refute Map.has_key?(record, "provider_metrics")

    for field <-
          ~w(prompt response credentials environment transcript corpus_text provider_payload) do
      assert {:error, {:sensitive_fields, [^field]}} =
               Telemetry.llm(Map.put(attrs, field, "secret corpus-shaped prompt"))
    end

    malformed =
      put_in(attrs, ["provider_metrics", "output_tokens"], %{
        "value" => "zero",
        "source" => "provider",
        "quality" => "exact",
        "unknown" => "ignored"
      })

    assert {:ok, malformed_record} = Telemetry.llm(malformed)
    assert malformed_record["metrics"]["output_tokens"]["value"] == :null

    assert {:error, {:unknown_fields, ["billing_payload"]}} =
             Telemetry.llm(Map.put(attrs, "billing_payload", %{"raw" => "excluded"}))

    assert {:error, {:unknown_metric_fields, ["provider_private_cache"]}} =
             Telemetry.llm(
               put_in(attrs, ["provider_metrics", "provider_private_cache"], %{"value" => 3})
             )

    late =
      put_in(attrs, ["provider_metrics", "output_tokens"], %{
        "value" => 9,
        "source" => "provider_late",
        "quality" => "exact"
      })

    assert {:ok, late_record} = Telemetry.llm(late)
    assert late_record["record_id"] == record["record_id"]

    assert {:error, :invalid_clock_boundary} =
             Telemetry.llm(%{attrs | "ended_at" => "2026-09-07T23:59:59Z"})

    for field <- ~w(task_id run_id role provider profile model reasoning phase outcome) do
      invalid = Map.put(attrs, field, 7)

      assert {:error, {:invalid_type, ^field}} = Telemetry.llm(invalid)
    end
  end

  test "command telemetry redacts secrets and never invents token fields" do
    assert {:ok, record} =
             Telemetry.command(%{
               "task_id" => "T1",
               "run_id" => "r1",
               "phase" => "integration_gate",
               "started_at" => "2026-09-08T00:00:00Z",
               "ended_at" => "2026-09-08T00:00:01Z",
               "duration_ms" => 1_000,
               "exit_code" => 7,
               "resource_class" => "workflow-build",
               "command" => ["tool", "--token", "secret", "api_key=also-secret"]
             })

    assert record["command"] == ["tool", "--token", "[REDACTED]", "api_key=[REDACTED]"]
    assert record["exit_code"] == 7
    refute Map.has_key?(record, "metrics")
  end

  test "instrumentation exceptions and exits do not alter or duplicate the observed action" do
    parent = self()

    assert :action_result ==
             Telemetry.observe(
               fn ->
                 send(parent, :action)
                 :action_result
               end,
               fn _ -> exit(:instrument_failed) end
             )

    assert_receive :action
    refute_receive :action

    assert_raise RuntimeError, "action failed", fn ->
      Telemetry.observe(
        fn -> raise "action failed" end,
        fn outcome -> send(parent, {:instrumented_failure, outcome}) end
      )
    end

    assert_receive {:instrumented_failure, %{"outcome" => "exception", "class" => "RuntimeError"}}

    assert catch_exit(
             Telemetry.observe(
               fn -> exit(:action_exit) end,
               fn outcome -> send(parent, {:instrumented_exit, outcome}) end
             )
           ) == :action_exit

    assert_receive {:instrumented_exit, %{"outcome" => "exit"}}
  end

  test "instrumentation emission cannot delay the observed action" do
    parent = self()
    release = make_ref()

    assert :action_result ==
             Telemetry.observe(
               fn -> :action_result end,
               fn _ ->
                 send(parent, {:emitter_started, self()})

                 receive do
                   {:release, ^release} -> :ok
                 after
                   100 -> send(parent, :emitter_delayed_action)
                 end
               end
             )

    assert_receive {:emitter_started, emitter}
    refute_receive :emitter_delayed_action
    send(emitter, {:release, release})
  end

  test "JSONL storage is durable and idempotent; exports remain sanitized" do
    root = temp_root("telemetry")
    log = Path.join(root, "records.jsonl")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, record} = Telemetry.llm(llm_attrs())

    assert :ok = Store.append(log, record)
    assert :duplicate = Store.append(log, record)
    assert {:ok, [^record]} = Store.read(log)

    jsonl = TelemetryExport.jsonl([record])
    assert [decoded] = jsonl |> String.split("\n", trim: true) |> Enum.map(&:json.decode/1)
    assert decoded == record

    {:ok, csv_record} = Telemetry.llm(%{llm_attrs() | "outcome" => "completed,verified"})
    csv = TelemetryExport.csv([csv_record])
    assert String.starts_with?(csv, "schema_version,record_id")
    assert String.contains?(csv, "\"completed,verified\"")
    assert String.contains?(csv, "prompt_input_tokens.value")
    assert String.contains?(csv, ",120,provider,exact,")
    refute String.contains?(jsonl <> csv, "secret corpus-shaped prompt")
  end

  test "invalid direct writes fail closed at read, export, and status boundaries" do
    root = temp_root("invalid-telemetry")
    log = Path.join(root, "records.jsonl")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, record} = Telemetry.llm(llm_attrs())

    invalid = Map.put(record, "unvalidated_model_output", "must not become authority")
    assert {:error, {:unknown_fields, ["unvalidated_model_output"]}} = Store.append(log, invalid)
    refute File.exists?(log)

    mixed =
      IO.iodata_to_binary([
        :json.encode(record),
        "\n",
        :json.encode(%{record | "schema_version" => 2}),
        "\n"
      ])

    File.mkdir_p!(root)
    File.write!(log, mixed)
    assert {:error, :record_digest_mismatch} = Store.read(log)

    assert_raise ArgumentError, fn -> TelemetryExport.jsonl([invalid]) end

    assert_raise ArgumentError, fn ->
      PramanaFoundry.Status.TelemetryStatus.aggregate([invalid])
    end

    malformed = IO.iodata_to_binary([:json.encode(record), "\n{\n"])
    File.write!(log, malformed)
    assert {:error, :malformed_jsonl} = Store.read(log)
  end

  test "compaction deduplicates and preserves totals across crash recovery" do
    root = temp_root("compaction")
    log = Path.join(root, "records.jsonl")
    compacted = Path.join(root, "compacted.json")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, record} = Telemetry.llm(llm_attrs())
    :ok = Store.append(log, record)
    File.write!(log, IO.iodata_to_binary(:json.encode(record)) <> "\n", [:append])

    assert {:error, {:injected_crash, :after_intent}} =
             Store.compact(log, compacted, "2027-01-01T00:00:00Z",
               crash_at: :after_intent,
               txid: "fixture"
             )

    assert :ok = PramanaFoundry.AtomicFile.recover(compacted)
    value = compacted |> File.read!() |> :json.decode()
    assert value["compacted"]["records"] == 1
    assert value["compacted"]["duration_ms"]["sum"] == 1_000
    assert value["deduplication"]["duplicate_records"] == 1
    assert value["compacted"]["metric_sources"]["prompt_input_tokens:provider"] == 1

    assert :ok =
             Store.compact(log, compacted, "2027-01-01T00:00:00Z", txid: "completed")

    assert {:ok, []} = Store.read(log)

    assert :ok =
             Store.compact(log, compacted, "2027-01-01T00:00:00Z", txid: "idempotent")

    repeated = compacted |> File.read!() |> :json.decode()
    assert repeated["compacted"]["records"] == 1
    assert repeated["compacted"]["duration_ms"]["sum"] == 1_000
    assert repeated["compacted"]["duration_ms"]["samples"] == [1_000]
    assert repeated["compacted"]["record_ids"] == [record["record_id"]]
  end

  defp llm_attrs do
    %{
      "task_id" => "T1",
      "run_id" => "r1",
      "role" => "developer",
      "phase" => "implementation",
      "provider" => "openai",
      "profile" => "sol",
      "model" => "gpt",
      "reasoning" => "medium",
      "started_at" => "2026-09-08T00:00:00Z",
      "ended_at" => "2026-09-08T00:00:01Z",
      "duration_ms" => 1_000,
      "retries" => 0,
      "cooldowns" => 0,
      "outcome" => "completed",
      "provider_metrics" => %{
        "prompt_input_tokens" => %{"value" => 120, "source" => "provider", "quality" => "exact"}
      }
    }
  end

  defp temp_root(prefix),
    do: Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
end
