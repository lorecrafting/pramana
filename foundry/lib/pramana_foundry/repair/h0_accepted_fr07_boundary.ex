defmodule PramanaFoundry.Repair.H0AcceptedFR07Boundary do
  @moduledoc """
  Revision-bound H0 inventory of the accepted FR-07 public boundary.

  The provider runs only public `Gateway` and `LegacyImport` operations against
  disposable stores. It reports a capability as unavailable when the accepted API
  cannot exercise the complete capability. In particular, schema presence and an
  empty table are never treated as positive lifecycle evidence.

  This is an evidence provider, not a durable-store extension. A blocked report is
  the expected H0 result and does not establish FR-08 readiness.
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
      path: "lib/pramana_foundry/durable_store/gateway.ex",
      sha256: "71742ca574ccc21806eb5cd6fb211946bad18a5049f1048bf9bde5c655723247"
    },
    %{
      path: "lib/pramana_foundry/durable_store/kernel.ex",
      sha256: "918e7efbfbaaf6f2943b1b1ce403cf08615c330b300d6e0c9e1b7b192a6406ac"
    },
    %{
      path: "lib/pramana_foundry/durable_store/legacy_import.ex",
      sha256: "158a8419cc59ee7e3998f2e497308d2a03a88871f79c1e031849cfcfef24a322"
    },
    %{
      path: "lib/pramana_foundry/durable_store/record_codec.ex",
      sha256: "8bd05827b932e00dffbeeda84383d509a61d1cbc4be3fa58943ecfbef2930131"
    }
  ]

  @doc "Immutable identity of the accepted implementation and public API under probe."
  def identity do
    %{
      accepted_revision: @accepted_revision,
      accepted_tree: @accepted_tree,
      accepted_review_revision: @accepted_review_revision,
      accepted_review_tree: @accepted_review_tree,
      public_api: @api_identity
    }
  end

  @doc "Runs the seven-capability gate against the exact accepted FR-07 revision."
  def report do
    %{
      schema: "pramana-foundry-h0-accepted-fr07-boundary/v1",
      identity: identity(),
      gate: FR08HandoffGate.run(__MODULE__, subject_revision: @accepted_revision)
    }
  end

  @impl true
  def probe(_capability, revision) when revision != @accepted_revision,
    do: {:unavailable, "h0:accepted_revision_mismatch"}

  def probe(:same_command_lookup_before_revision, @accepted_revision) do
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
               {:ok, ^result} <- Gateway.command(gateway, "H0-LOOKUP") do
            {:pass, receipt("lookup-before-revision", result)}
          end
        end)
      end
    end)
  end

  def probe(:complete_read_set_cas, @accepted_revision) do
    {:unavailable,
     "h0:no_public_evolving_policy_control_or_allocation_lifecycle;projection_cas_only"}
  end

  def probe(:atomic_authority_commit, @accepted_revision) do
    {:unavailable,
     "h0:no_public_receipt_lease_claim_issue_settlement_or_ledger_evolution_operation"}
  end

  def probe(:revision_and_inbox_facts, @accepted_revision) do
    {:unavailable, "h0:no_public_authenticated_inbox_sequence_or_seal_operation"}
  end

  def probe(:protected_field_boundary, @accepted_revision) do
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
            {:pass, receipt("protected-field-rejection", {protected_fields, counts})}
          else
            false -> {:fail, "h0:forged_protected_field_changed_public_counts"}
            other -> {:fail, failure("protected-field-boundary", other)}
          end
        end)
      end
    end)
  end

  def probe(:fail_closed_recovery, @accepted_revision) do
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
             receipt("fail-closed-recovery", {
               status.mode,
               status.reason,
               rejected,
               :path_absent
             })}
          else
            true -> {:fail, "h0:missing_store_was_created"}
            other -> {:fail, failure("fail-closed-recovery", other)}
          end
        end)
      end
    end)
  end

  def probe(:immutable_legacy_import, @accepted_revision) do
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
              source_digest: manifest["source_digest"],
              source_bytes: manifest["source_bytes"],
              line_count: manifest["line_count"],
              valid_count: manifest["valid_count"],
              invalid_count: manifest["invalid_count"]
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
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      id = "H0-FORGE-#{field}"
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
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
    "h0:#{label}:sha256:#{digest}"
  end

  defp failure(label, value) do
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
    "h0:#{label}-failed:sha256:#{digest}"
  end
end
