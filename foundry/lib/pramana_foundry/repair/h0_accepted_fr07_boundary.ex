defmodule PramanaFoundry.Repair.H0AcceptedFR07Boundary do
  @moduledoc """
  Revision-bound H0 inventory of the accepted FR-07 public boundary.

  The provider runs only public `Gateway` and `LegacyImport` operations against
  disposable stores. It reports a capability as unavailable when the accepted API
  cannot exercise the complete capability. In particular, schema presence and an
  empty table are never treated as positive lifecycle evidence.

  This is an evidence provider, not a durable-store extension. A blocked report is
  the expected H0 result and does not establish FR-08 readiness.

  Receipt inputs use `pramana-foundry-h0-receipt/v1`: a UTF-8 JSON object whose
  keys are sorted by byte value at every depth, with no insignificant whitespace.
  The encoder accepts only JSON strings, integers, booleans, nulls, proper lists
  and string-keyed maps. The receipt is the lowercase SHA-256 of those bytes.
  """

  @behaviour PramanaFoundry.Repair.FR08HandoffGate

  alias PramanaFoundry.DurableStore.{Gateway, LegacyImport}
  alias PramanaFoundry.Repair.FR08HandoffGate

  @accepted_revision "af0c51b4682c50080e67194dd853fbaa1eebace7"
  @accepted_tree "e4aed492d5973d185a7e772d1b764e1117df11c1"
  @accepted_review_revision "8d7223b79cb237d3406f156c7d1a06a8bcb48d81"
  @accepted_review_tree "894e47756305f1b0fb615c6471f2dfdc644f16f3"

  @api_identity [
    %{
      module: PramanaFoundry.DurableStore.Gateway,
      path: "lib/pramana_foundry/durable_store/gateway.ex",
      sha256: "71742ca574ccc21806eb5cd6fb211946bad18a5049f1048bf9bde5c655723247",
      beam_md5: "545016e2a46e4810b9c275683ca82c33"
    },
    %{
      module: PramanaFoundry.DurableStore.Kernel,
      path: "lib/pramana_foundry/durable_store/kernel.ex",
      sha256: "918e7efbfbaaf6f2943b1b1ce403cf08615c330b300d6e0c9e1b7b192a6406ac",
      beam_md5: "e43949e9a2658ebbd12afabdf2f30086"
    },
    %{
      module: PramanaFoundry.DurableStore.LegacyImport,
      path: "lib/pramana_foundry/durable_store/legacy_import.ex",
      sha256: "158a8419cc59ee7e3998f2e497308d2a03a88871f79c1e031849cfcfef24a322",
      beam_md5: "c91b85e002244d83b85410de3c2f666b"
    },
    %{
      module: PramanaFoundry.DurableStore.RecordCodec,
      path: "lib/pramana_foundry/durable_store/record_codec.ex",
      sha256: "8bd05827b932e00dffbeeda84383d509a61d1cbc4be3fa58943ecfbef2930131",
      beam_md5: "be95460c6e50de9cdb4bd85945413708"
    }
  ]

  @doc "Immutable identity of the accepted implementation and public API under probe."
  def identity do
    %{
      accepted_revision: @accepted_revision,
      accepted_tree: @accepted_tree,
      accepted_review_revision: @accepted_review_revision,
      accepted_review_tree: @accepted_review_tree,
      public_api: Enum.map(@api_identity, &Map.drop(&1, [:module]))
    }
  end

  @doc "Runs the seven-capability gate and binds the supplied adapter/probe revision."
  def report(adapter_revision) when is_binary(adapter_revision) do
    unless Regex.match?(~r/^[0-9a-f]{40}$/, adapter_revision) do
      raise ArgumentError, "adapter_revision must be a lowercase 40-character Git object ID"
    end

    binding = implementation_binding()

    %{
      schema: "pramana-foundry-h0-accepted-fr07-boundary/v1",
      identity:
        identity()
        |> Map.put(:adapter_probe_revision, adapter_revision)
        |> Map.put(:implementation_binding, binding),
      gate: FR08HandoffGate.run(__MODULE__, subject_revision: @accepted_revision)
    }
  end

  @doc "Renders the bounded report in the deterministic frozen-artifact format."
  def report_artifact(adapter_revision) do
    report = report(adapter_revision)
    identity = report.identity
    gate = report.gate

    api_lines =
      Enum.map(identity.public_api, fn api ->
        "public_api=#{api.path}|sha256:#{api.sha256}|beam_md5:#{api.beam_md5}"
      end)

    capability_lines =
      Enum.map(gate.capabilities, fn capability ->
        detail = capability.evidence || capability.reason
        "#{capability.id}=#{capability.status}|#{detail}"
      end)

    lines = [
      "schema=#{report.schema}",
      "provider=#{gate.provider}",
      "subject_revision=#{identity.accepted_revision}",
      "subject_tree=#{identity.accepted_tree}",
      "accepted_review_revision=#{identity.accepted_review_revision}",
      "accepted_review_tree=#{identity.accepted_review_tree}",
      "adapter_probe_revision=#{identity.adapter_probe_revision}",
      "implementation_binding=#{identity.implementation_binding.status}|#{identity.implementation_binding.method}"
    ]

    summary_lines = [
      "gate_schema=#{gate.schema}",
      "gate_status=#{gate.status}",
      "ready=#{FR08HandoffGate.ready?(gate)}",
      "mandatory_count=#{gate.mandatory_count}",
      "passed_count=#{gate.passed_count}",
      "failed_count=#{gate.failed_count}",
      "unavailable_count=#{gate.unavailable_count}"
    ]

    Enum.join(lines ++ api_lines ++ summary_lines ++ capability_lines, "\n") <> "\n"
  end

  @impl true
  def probe(_capability, revision) when revision != @accepted_revision,
    do: {:unavailable, "h0:accepted_revision_mismatch"}

  def probe(capability, @accepted_revision) do
    case implementation_binding() do
      %{status: "verified"} -> verified_probe(capability)
      %{status: "mismatch"} -> {:unavailable, "h0:loaded_accepted_api_identity_mismatch"}
    end
  end

  defp verified_probe(:same_command_lookup_before_revision) do
    with_fixture("lookup", fn _root, path ->
      with :ok <- initialize(path),
           {:ok, gateway} <- Gateway.start_link(path: path) do
        with_gateway(gateway, fn ->
          with {:ok, result, :committed} <-
                 Gateway.transact(
                   gateway,
                   "h0-actor",
                   command("H0-LOOKUP"),
                   bundle("H0-LOOKUP")
                 ),
               {:ok, ^result, :idempotent} <-
                 Gateway.transact(gateway, "h0-actor", command("H0-LOOKUP"), %{}),
               {:error, :idempotency_conflict} <-
                 Gateway.transact(gateway, "hostile-actor", command("H0-LOOKUP"), %{}),
               {:error, :idempotency_conflict} <-
                 Gateway.transact(
                   gateway,
                   "h0-actor",
                   put_in(command("H0-LOOKUP")["payload"], %{"changed" => true}),
                   %{}
                 ),
               {:ok, ^result} <- Gateway.command(gateway, "H0-LOOKUP") do
            {:pass, receipt("lookup-before-revision", result)}
          end
        end)
      end
    end)
  end

  defp verified_probe(:complete_read_set_cas) do
    {:unavailable,
     "h0:no_public_evolving_policy_control_or_allocation_lifecycle;projection_cas_only"}
  end

  defp verified_probe(:atomic_authority_commit) do
    {:unavailable,
     "h0:no_public_receipt_lease_claim_issue_settlement_or_ledger_evolution_operation"}
  end

  defp verified_probe(:revision_and_inbox_facts) do
    {:unavailable, "h0:no_public_authenticated_inbox_sequence_or_seal_operation"}
  end

  defp verified_probe(:protected_field_boundary) do
    with_fixture("protected-boundary", fn _root, path ->
      protected_fields = [
        :claims,
        :receipts,
        :leases,
        :ledger_generations,
        :policy_revisions,
        :control_revisions,
        :artifact_references,
        :balances,
        :accepted_refs
      ]

      with :ok <- initialize(path),
           {:ok, gateway} <- Gateway.start_link(path: path) do
        with_gateway(gateway, fn ->
          with :ok <- reject_protected_fields(gateway, protected_fields),
               {:ok, counts} <- Gateway.counts(gateway),
               true <- Enum.all?(counts, fn {_table, count} -> count == 0 end) do
            {:pass,
             receipt("protected-field-rejection", %{
               "protected_fields" => Enum.map(protected_fields, &Atom.to_string/1),
               "key_forms" => ["atom", "string"],
               "counts" => counts
             })}
          else
            false -> {:fail, "h0:forged_protected_field_changed_public_counts"}
            other -> {:fail, failure("protected-field-boundary", other)}
          end
        end)
      end
    end)
  end

  defp verified_probe(:fail_closed_recovery) do
    with_fixture("recovery", fn _root, path ->
      with {:ok, gateway} <- Gateway.start_link(path: path) do
        with_gateway(gateway, fn ->
          with %{mode: :recovery, reason: :not_initialized} = status <- Gateway.status(gateway),
               {:error, {:recovery_mode, :not_initialized}} = rejected <-
                 Gateway.transact(
                   gateway,
                   "h0-actor",
                   command("H0-RECOVERY"),
                   bundle("H0-RECOVERY")
                 ),
               {:error, {:recovery_mode, :not_initialized}} <- Gateway.counts(gateway),
               false <- File.exists?(path) do
            {:pass,
             receipt("fail-closed-recovery", %{
               "mode" => Atom.to_string(status.mode),
               "reason" => Atom.to_string(status.reason),
               "transaction" => inspect(rejected),
               "path" => "absent"
             })}
          else
            true -> {:fail, "h0:missing_store_was_created"}
            other -> {:fail, failure("fail-closed-recovery", other)}
          end
        end)
      end
    end)
  end

  defp verified_probe(:immutable_legacy_import) do
    with_fixture("legacy-import", fn root, path ->
      source = Path.join(root, "legacy.jsonl")
      archive = Path.join(root, "archive")
      bytes = legacy_fixture()

      with :ok <- initialize(path),
           :ok <- File.write(source, bytes),
           {:ok, manifest} <- LegacyImport.run(path, source, archive),
           true <- manifest["line_count"] == 2,
           true <- manifest["valid_count"] == 0,
           true <- manifest["invalid_count"] == 2,
           true <- File.read!(manifest["archived_path"]) == bytes,
           {:ok, gateway} <- Gateway.start_link(path: path) do
        with_gateway(gateway, fn ->
          with {:ok, %{"commands" => 0, "events" => 0}} <- Gateway.counts(gateway) do
            selected = %{
              "source_digest" => manifest["source_digest"],
              "source_bytes" => manifest["source_bytes"],
              "line_count" => manifest["line_count"],
              "valid_count" => manifest["valid_count"],
              "invalid_count" => manifest["invalid_count"]
            }

            {:pass, receipt("immutable-legacy-import", selected)}
          end
        end)
      else
        false -> {:fail, "h0:legacy_import_evidence_mismatch"}
        other -> {:fail, failure("immutable-legacy-import", other)}
      end
    end)
  end

  defp with_fixture(label, fun) do
    tmp_root = if File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()

    root =
      Path.join(
        tmp_root,
        "pramana-foundry-h0-#{label}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)

    try do
      fun.(root, Path.join(root, "authority.sqlite3"))
    after
      File.rm_rf!(root)
    end
  rescue
    _error -> {:fail, "h0:fixture_operation_failed"}
  catch
    :exit, _reason -> {:fail, "h0:fixture_process_exit"}
  end

  defp initialize(path) do
    Gateway.initialize(path,
      installation_id: "h0-accepted-fr07",
      repository_id: "pramana-foundry"
    )
  end

  defp reject_protected_fields(gateway, fields) do
    fields
    |> Enum.flat_map(fn field -> [{field, "atom"}, {Atom.to_string(field), "string"}] end)
    |> Enum.reduce_while(:ok, fn {field, form}, :ok ->
      id = "H0-FORGE-#{field}-#{form}"
      forged = Map.put(bundle(id), field, [%{"forged" => true}])

      case Gateway.transact(gateway, "h0-kernel", command(id), forged) do
        {:error, :unknown_field} -> {:cont, :ok}
        other -> {:halt, {:error, {field, other}}}
      end
    end)
  end

  defp stop_gateway(gateway) do
    GenServer.stop(gateway)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp with_gateway(gateway, fun) do
    try do
      fun.()
    after
      stop_gateway(gateway)
    end
  end

  defp command(id) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "legacy_event_append",
      "target_ids" => %{"ticket_id" => id},
      "payload" => %{"fixture" => "accepted-fr07-v9"}
    }
  end

  defp bundle(id) do
    event_id = "event-#{id}"

    %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
      events: [
        %{
          schema_version: 1,
          event_id: event_id,
          type: "legacy_event",
          payload: %{
            "projection" => %{
              "namespace" => "h0-v1",
              "entity_id" => "fixture-#{id}",
              "revision" => 0,
              "value" => %{"status" => "observed"}
            }
          }
        }
      ],
      projections: [
        %{
          schema_version: 1,
          namespace: "h0-v1",
          entity_id: "fixture-#{id}",
          expected_revision: -1,
          revision: 0,
          last_event_id: event_id,
          value: %{"status" => "observed"}
        }
      ],
      intents: []
    }
  end

  defp projection_key(id) do
    "projection/" <>
      Base.url_encode64("h0-v1", padding: false) <>
      "/" <> Base.url_encode64("fixture-#{id}", padding: false)
  end

  defp legacy_fixture do
    ~s({"schema_version":99,"event":"unsupported_h0_event","at":"2026-09-19T00:00:00Z","attributes":{},"evidence":{}}\n{malformed}\n)
  end

  defp receipt(label, value) do
    bytes =
      canonical_json!(%{
        "data" => value,
        "label" => label,
        "schema" => "pramana-foundry-h0-receipt/v1"
      })

    digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    "h0:#{label}:sha256:#{digest}"
  end

  defp failure(label, value) do
    _redacted = value
    "h0:#{label}-failed"
  end

  defp implementation_binding do
    if Enum.all?(@api_identity, &accepted_loaded_module?/1) do
      %{status: "verified", method: "source-sha256+beam-md5/v1"}
    else
      %{status: "mismatch", method: "source-sha256+beam-md5/v1"}
    end
  end

  defp accepted_loaded_module?(expected) do
    with {:module, module} <- Code.ensure_loaded(expected.module),
         source when is_list(source) <- module.module_info(:compile)[:source],
         {:ok, bytes} <- File.read(List.to_string(source)) do
      sha256(bytes) == expected.sha256 and
        Base.encode16(module.module_info(:md5), case: :lower) == expected.beam_md5
    else
      _other -> false
    end
  end

  defp sha256(bytes),
    do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp canonical_json!(value), do: value |> canonical_json() |> IO.iodata_to_binary()

  defp canonical_json(value) when is_binary(value) do
    unless String.valid?(value), do: raise(ArgumentError, "canonical JSON string must be UTF-8")
    :json.encode(value)
  end

  defp canonical_json(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical_json(true), do: "true"
  defp canonical_json(false), do: "false"
  defp canonical_json(nil), do: "null"

  defp canonical_json(value) when is_list(value) do
    ["[", value |> Enum.map(&canonical_json/1) |> Enum.intersperse(","), "]"]
  end

  defp canonical_json(value) when is_map(value) and not is_struct(value) do
    entries =
      value
      |> Enum.map(fn
        {key, item} when is_binary(key) -> {key, item}
        {_key, _item} -> raise ArgumentError, "canonical JSON map keys must be strings"
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} -> [canonical_json(key), ":", canonical_json(item)] end)

    ["{", Enum.intersperse(entries, ","), "}"]
  end

  defp canonical_json(_value),
    do: raise(ArgumentError, "unsupported canonical JSON value")
end
