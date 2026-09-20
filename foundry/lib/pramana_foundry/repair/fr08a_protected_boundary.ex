defmodule PramanaFoundry.Repair.FR08AProtectedBoundary do
  @moduledoc """
  Revision-bound executable acceptance provider for the FR-08A protected boundary.

  Every probe uses only the public `Gateway` or `LegacyImport` API against a disposable
  store. Evidence strings are canonical digests of bounded semantic observations, never
  table contents. The subject is the core protected-primitives revision; this provider and
  its frozen report are a separate evidence layer.
  """

  @behaviour PramanaFoundry.Repair.FR08HandoffGate

  alias PramanaFoundry.DurableStore.{Gateway, LegacyImport}
  alias PramanaFoundry.Repair.FR08HandoffGate

  @subject_revision "e491e416510894b43d292efa8944190df69b5923"
  @subject_tree "9428abfcc819cdab941ab69b7837a0c8a8a98e3b"
  @api_identity [
    {PramanaFoundry.DurableStore.Authority, "lib/pramana_foundry/durable_store/authority.ex",
     "c32088a5246c22cbbef465f3d496123d98683b6f67e22ba9787f70a5c26153db",
     "c671cf8a271c9d67ca499b2dde21666c"},
    {PramanaFoundry.DurableStore.Database, "lib/pramana_foundry/durable_store/database.ex",
     "ae81f4021a052ab935403591eeb5d72ea33e184896cfe016a74ca027c9a99015",
     "fe6458dee10d27b0c75545ae71cf197a"},
    {PramanaFoundry.DurableStore.Gateway, "lib/pramana_foundry/durable_store/gateway.ex",
     "59b08359df8de0b198026a79ab18b529421227db283de93fd670e809ae34bf7b",
     "381a2217c9fdc546c8cac102dd32676f"},
    {PramanaFoundry.DurableStore.ProtectedPrimitives,
     "lib/pramana_foundry/durable_store/protected_primitives.ex",
     "da244dbd7822b6145f25fa6c6fc4fa8e442f6905bde3b9aee622e71448d4b8e4",
     "3811eaf1ff6c419ac375f9e0602633ee"},
    {PramanaFoundry.DurableStore.Kernel, "lib/pramana_foundry/durable_store/kernel.ex",
     "918e7efbfbaaf6f2943b1b1ce403cf08615c330b300d6e0c9e1b7b192a6406ac",
     "e43949e9a2658ebbd12afabdf2f30086"},
    {PramanaFoundry.DurableStore.RecordCodec, "lib/pramana_foundry/durable_store/record_codec.ex",
     "1d22fe22e0d04ed57436d8693702c4d27133675f3248808668f9b410897b6856",
     "7df5c0fbf127754c67f73073b6267894"},
    {PramanaFoundry.DurableStore.Encoding, "lib/pramana_foundry/durable_store/encoding.ex",
     "140730a723527d3e7c9f71f0e54c209f14ce4a8b74004e553f12f14ce7c987ba",
     "5f1bff0562b0fed9407a8af02bc84241"},
    {PramanaFoundry.DurableStore.LegacyImport,
     "lib/pramana_foundry/durable_store/legacy_import.ex",
     "158a8419cc59ee7e3998f2e497308d2a03a88871f79c1e031849cfcfef24a322",
     "c91b85e002244d83b85410de3c2f666b"},
    {PramanaFoundry.Repair.FR08HandoffGate, "lib/pramana_foundry/repair/fr08_handoff_gate.ex",
     "710f42d0467e97f58540342ba1c566959d995f1d561242c275f88eab2017228b",
     "e1eef77b648eb850b9a643629982d091"}
  ]

  def identity do
    %{
      schema: "pramana-foundry-fr08a-protected-boundary/v1",
      subject_revision: @subject_revision,
      subject_tree: @subject_tree,
      exercised_api:
        Enum.map(@api_identity, fn {_module, path, sha256, beam_md5} ->
          %{path: path, sha256: sha256, beam_md5: beam_md5}
        end),
      implementation_binding: implementation_binding()
    }
  end

  def report do
    %{
      identity: identity(),
      gate: FR08HandoffGate.run(__MODULE__, subject_revision: @subject_revision)
    }
  end

  def report_artifact do
    report = report()
    gate = report.gate

    source_lines =
      Enum.map(report.identity.exercised_api, fn api ->
        "source=#{api.path}|sha256:#{api.sha256}|beam_md5:#{api.beam_md5}"
      end)

    capability_lines =
      Enum.map(gate.capabilities, fn capability ->
        "#{capability.id}=#{capability.status}|#{capability.evidence || capability.reason}"
      end)

    Enum.join(
      [
        "schema=#{report.identity.schema}",
        "provider=#{gate.provider}",
        "subject_revision=#{@subject_revision}",
        "subject_tree=#{@subject_tree}",
        "implementation_binding=#{report.identity.implementation_binding}",
        "gate_schema=#{gate.schema}",
        "gate_status=#{gate.status}",
        "ready=#{FR08HandoffGate.ready?(gate)}",
        "mandatory_count=#{gate.mandatory_count}",
        "passed_count=#{gate.passed_count}",
        "failed_count=#{gate.failed_count}",
        "unavailable_count=#{gate.unavailable_count}"
        | source_lines ++ capability_lines
      ],
      "\n"
    ) <> "\n"
  end

  @impl true
  def probe(_capability, revision) when revision != @subject_revision,
    do: {:unavailable, "fr08a:subject_revision_mismatch"}

  def probe(capability, @subject_revision) do
    if implementation_binding() == "verified:source-sha256+beam-md5/v1" do
      verified_probe(capability)
    else
      {:unavailable, "fr08a:loaded_subject_identity_mismatch"}
    end
  end

  defp verified_probe(:same_command_lookup_before_revision) do
    with_fixture("idempotency", fn gateway, capability, _root, _path ->
      operation = policy_operation()
      request = command("IDEM-1", %{"policy/policy-1" => "absent"}, operation)

      with {:ok, result, :committed} <- protected(gateway, capability, request),
           {:ok, ^result, :idempotent} <- protected(gateway, capability, request),
           {:error, :idempotency_conflict} <-
             Gateway.protected_command(gateway, capability, "other-actor", request),
           {:error, :idempotency_conflict} <-
             protected(gateway, capability, put_in(request["operation"]["value"], %{})),
           {:ok, ^result} <-
             Gateway.protected_query(
               gateway,
               capability,
               query("command", "command_id", "IDEM-1")
             ) do
        pass("same-command", %{"disposition" => result["disposition"]})
      else
        other -> fail("same-command", other)
      end
    end)
  end

  defp verified_probe(:complete_read_set_cas) do
    with_fixture("complete-cas", fn gateway, capability, _root, _path ->
      with {:ok, _, :committed} <-
             protected(
               gateway,
               capability,
               command("POLICY", %{"policy/policy-1" => "absent"}, policy_operation())
             ),
           {:ok, _, :committed} <-
             protected(
               gateway,
               capability,
               command("CONTROL", %{"control/control-1" => "absent"}, control_operation())
             ),
           {:ok, _, :committed} <-
             protected(
               gateway,
               capability,
               command("GRANT", %{"ledger/objective/0" => "absent"}, grant_operation())
             ),
           {:ok, delegated, :committed} <- protected(gateway, capability, delegate_request()),
           {:ok, _, :committed} <- protected(gateway, capability, reserve_request()),
           {:ok, incomplete, :committed} <-
             protected(
               gateway,
               capability,
               command("EFFECT-INCOMPLETE", incomplete_effect_reads(), effect_operation())
             ),
           {:ok, stale, :committed} <-
             protected(
               gateway,
               capability,
               command(
                 "DELEGATE-STALE",
                 %{"ledger/objective/0" => 0, "ledger/stale/0" => "absent"},
                 Map.put(delegate_operation(), "child_ledger_id", "stale")
               )
             ) do
        if delegated["disposition"] == "accepted" and
             incomplete["reason_code"] == "incomplete_read_set" and
             stale["reason_code"] == "stale_read_set" do
          pass("complete-cas", %{"incomplete" => true, "stale" => true, "derived" => true})
        else
          {:fail, "fr08a:complete-cas-semantic-mismatch"}
        end
      else
        other -> fail("complete-cas", other)
      end
    end)
  end

  defp verified_probe(:atomic_authority_commit) do
    with_fixture("atomic-authority", fn gateway, capability, _root, _path ->
      with :ok <- seed_authority(gateway, capability),
           {:ok, _, :committed} <- protected(gateway, capability, reserve_request()),
           {:ok, _, :committed} <- protected(gateway, capability, effect_request()),
           {:ok, _, :committed} <- protected(gateway, capability, claim_request()),
           {:ok, _, :committed} <- protected(gateway, capability, issue_request()),
           {:ok, settled, :committed} <- protected(gateway, capability, settle_request()),
           {:ok, claim} <-
             Gateway.protected_query(gateway, capability, query("claim", "claim_id", "claim-1")),
           {:ok, ledger} <- Gateway.protected_query(gateway, capability, ledger_query()),
           {:ok, lease} <-
             Gateway.protected_query(gateway, capability, query("lease", "lease_id", "lease-1")),
           {:ok, receipt} <-
             Gateway.protected_query(
               gateway,
               capability,
               query("receipt", "receipt_id", "receipt-1")
             ) do
        if settled["disposition"] == "accepted" and claim["status"] == "succeeded" and
             ledger["held"] == 0 and ledger["consumed"] == 1 and
             lease["status"] == "released" and receipt["outcome"] == "succeeded" do
          pass("atomic-authority", %{
            "claim" => claim["status"],
            "lease" => lease["status"],
            "consumed" => ledger["consumed"],
            "receipt" => receipt["outcome"]
          })
        else
          {:fail, "fr08a:atomic-authority-semantic-mismatch"}
        end
      else
        other -> fail("atomic-authority", other)
      end
    end)
  end

  defp verified_probe(:revision_and_inbox_facts) do
    with_fixture("inbox", fn gateway, capability, _root, _path ->
      result = inbox_append("result", 1, %{"candidate_id" => "accepted"})
      exit = inbox_append("exit", 2, %{"status" => 1})
      late = inbox_append("result", 3, %{"candidate_id" => "late"})

      with {:ok, _, :committed} <-
             protected(
               gateway,
               capability,
               command("I-1", %{"inbox/execution-1" => "absent"}, result)
             ),
           {:ok, _, :committed} <-
             protected(gateway, capability, command("I-2", %{"inbox/execution-1" => 0}, exit)),
           {:ok, _, :committed} <-
             protected(
               gateway,
               capability,
               command("I-SEAL", %{"inbox/execution-1" => 1}, %{
                 "type" => "seal_inbox",
                 "execution_id" => "execution-1",
                 "last_sequence" => 2
               })
             ),
           {:ok, _, :committed} <-
             protected(gateway, capability, command("I-LATE", %{"inbox/execution-1" => 2}, late)),
           {:ok, inbox} <-
             Gateway.protected_query(
               gateway,
               capability,
               query("inbox", "execution_id", "execution-1")
             ),
           {:ok, snapshot} <- Gateway.protected_snapshot(gateway, capability) do
        if inbox["resolution"]["status"] == "result" and inbox["sealed_sequence"] == 2 and
             List.last(inbox["items"])["disposition"] == "late" and
             snapshot["fact_revision_frontiers"]["inbox"] == 3 and
             snapshot["pointers"]["selected_deployment"]["producer_status"] == "absent" do
          pass("inbox", %{"resolution" => "result", "late" => true, "pointer" => "absent"})
        else
          {:fail, "fr08a:inbox-semantic-mismatch"}
        end
      else
        other -> fail("inbox", other)
      end
    end)
  end

  defp verified_probe(:protected_field_boundary) do
    with_fixture("boundary", fn gateway, capability, _root, _path ->
      domain_command = %{
        "schema_version" => 1,
        "command_id" => "FORGE-DOMAIN",
        "expected_revisions" => %{},
        "type" => "legacy_event_append",
        "target_ids" => %{},
        "payload" => %{}
      }

      forged = %{
        schema_version: 1,
        result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
        events: [],
        projections: [],
        intents: [],
        claims: [%{forged: true}]
      }

      bad_root =
        command(
          "FORGE-ROOT",
          %{"policy/policy-2" => "absent"},
          Map.put(policy_operation("policy-2"), "revision", 99)
        )

      with {:error, :unknown_field} <- Gateway.transact(gateway, "kernel", domain_command, forged),
           root_rejected <- protected(gateway, capability, bad_root),
           true <- match?({:error, _reason}, root_rejected),
           {:ok, snapshot} <- Gateway.protected_snapshot(gateway, capability) do
        if snapshot["last_domain_event_sequence"] == 0 and
             snapshot["last_protected_command_sequence"] == 0 do
          pass("protected-boundary", %{"domain" => "rejected", "root" => "rejected-before-row"})
        else
          {:fail, "fr08a:forged-state-observed"}
        end
      else
        other -> fail("protected-boundary", other)
      end
    end)
  end

  defp verified_probe(:fail_closed_recovery) do
    with_raw_fixture("recovery", fn _root, path ->
      capability = make_ref()

      with {:ok, gateway} <- Gateway.start_link(path: path, protected_capability: capability),
           %{mode: :recovery, reason: :not_initialized} <- Gateway.status(gateway),
           {:error, {:recovery_mode, :not_initialized}} <-
             Gateway.protected_command(
               gateway,
               capability,
               "operator",
               command("NO-COMMIT", %{}, policy_operation())
             ),
           false <- File.exists?(path) do
        stop_gateway(gateway)
        pass("fail-closed", %{"mode" => "recovery", "file" => "absent"})
      else
        other -> fail("fail-closed", other)
      end
    end)
  end

  defp verified_probe(:immutable_legacy_import) do
    with_raw_fixture("legacy", fn root, path ->
      source = Path.join(root, "legacy.jsonl")
      archive = Path.join(root, "archive")
      bytes = ~s({"schema_version":99,"event":"unsupported_fr08a"}\n{malformed}\n)

      with :ok <- initialize(path),
           :ok <- File.write(source, bytes),
           {:ok, manifest} <- LegacyImport.run(path, source, archive),
           true <- manifest["invalid_count"] == 2,
           true <- manifest["valid_count"] == 0,
           true <- File.read!(manifest["archived_path"]) == bytes do
        pass("legacy-import", %{
          "source_digest" => manifest["source_digest"],
          "invalid" => manifest["invalid_count"],
          "preserved" => true
        })
      else
        other -> fail("legacy-import", other)
      end
    end)
  end

  defp seed_authority(gateway, capability) do
    requests = [
      command("POLICY", %{"policy/policy-1" => "absent"}, policy_operation()),
      command("CONTROL", %{"control/control-1" => "absent"}, control_operation()),
      command("GRANT", %{"ledger/objective/0" => "absent"}, grant_operation()),
      delegate_request()
    ]

    Enum.reduce_while(requests, :ok, fn request, :ok ->
      case protected(gateway, capability, request) do
        {:ok, %{"disposition" => "accepted"}, :committed} -> {:cont, :ok}
        other -> {:halt, {:error, other}}
      end
    end)
  end

  defp delegate_request do
    command(
      "DELEGATE",
      %{"ledger/objective/0" => 0, "ledger/ticket-T1/0" => "absent"},
      delegate_operation()
    )
  end

  defp reserve_request do
    command(
      "RESERVE",
      %{"ledger/ticket-T1/0" => 0, "reservation/reservation-1" => "absent"},
      %{
        "type" => "reserve",
        "reservation_id" => "reservation-1",
        "ledger_id" => "ticket-T1",
        "generation" => 0,
        "owner_kind" => "effect",
        "owner_id" => "effect-1",
        "units" => 1
      }
    )
  end

  defp effect_request do
    command(
      "EFFECT",
      Map.put(incomplete_effect_reads(), "ledger/ticket-T1/0", 0),
      effect_operation()
    )
  end

  defp claim_request do
    command(
      "CLAIM",
      %{
        "effect/effect-1" => 0,
        "claim/claim-1" => "absent",
        "reservation/reservation-1" => 1,
        "ledger/ticket-T1/0" => 1,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "lease/lease-1" => "absent"
      },
      %{
        "type" => "claim_effect",
        "effect_id" => "effect-1",
        "claim_id" => "claim-1",
        "writer_epoch" => "fr08a-gate-epoch"
      }
    )
  end

  defp issue_request do
    command(
      "ISSUE",
      %{
        "claim/claim-1" => 0,
        "effect/effect-1" => 1,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 2,
        "ledger/ticket-T1/0" => 1,
        "lease/lease-1" => 0
      },
      %{"type" => "issue_claim", "claim_id" => "claim-1", "writer_epoch" => "fr08a-gate-epoch"}
    )
  end

  defp settle_request do
    command(
      "SETTLE",
      %{
        "claim/claim-1" => 1,
        "effect/effect-1" => 2,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 3,
        "ledger/ticket-T1/0" => 1,
        "lease/lease-1" => 0,
        "receipt/receipt-1" => "absent"
      },
      %{
        "type" => "settle_claim",
        "claim_id" => "claim-1",
        "receipt_id" => "receipt-1",
        "request_id" => "provider-request-1",
        "outcome" => "succeeded",
        "proof" => "delivered",
        "payload" => %{"provider" => "fr08a-gate"}
      }
    )
  end

  defp incomplete_effect_reads do
    %{
      "effect/effect-1" => "absent",
      "policy/policy-1" => 0,
      "control/control-1" => 0,
      "reservation/reservation-1" => 0,
      "lease/lease-1" => "absent"
    }
  end

  defp effect_operation do
    %{
      "type" => "create_effect",
      "effect_id" => "effect-1",
      "request" => %{
        "request_id" => "provider-request-1",
        "role" => "developer",
        "profile" => "sol"
      },
      "operation" => "launch",
      "scope" => "ticket:T1",
      "ticket_id" => "T1",
      "attempt_id" => "A1",
      "execution_id" => "X1",
      "policy_id" => "policy-1",
      "policy_revision" => 0,
      "control_id" => "control-1",
      "control_revision" => 0,
      "reservation_ids" => ["reservation-1"],
      "leases" => [%{"lease_id" => "lease-1", "resource_id" => "slot-1"}]
    }
  end

  defp policy_operation(id \\ "policy-1") do
    %{
      "type" => "set_policy",
      "policy_id" => id,
      "value" => %{"allowed_operations" => ["launch"], "allowed_scopes" => ["ticket:T1"]}
    }
  end

  defp control_operation do
    %{"type" => "set_control", "control_id" => "control-1", "value" => %{"status" => "active"}}
  end

  defp grant_operation do
    %{
      "type" => "grant_ledger",
      "ledger_id" => "objective",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 5
    }
  end

  defp delegate_operation do
    %{
      "type" => "delegate_allocation",
      "parent_ledger_id" => "objective",
      "parent_generation" => 0,
      "child_ledger_id" => "ticket-T1",
      "child_generation" => 0,
      "dimension" => "starts.developer",
      "units" => 3
    }
  end

  defp inbox_append(kind, sequence, payload) do
    %{
      "type" => "append_inbox",
      "execution_id" => "execution-1",
      "sequence" => sequence,
      "item_kind" => kind,
      "payload" => payload
    }
  end

  defp ledger_query,
    do: %{
      "schema_version" => 1,
      "type" => "ledger",
      "ledger_id" => "ticket-T1",
      "generation" => 0
    }

  defp query(type, key, value), do: %{"schema_version" => 1, "type" => type, key => value}

  defp command(id, reads, operation) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => operation
    }
  end

  defp protected(gateway, capability, request),
    do: Gateway.protected_command(gateway, capability, "operator", request)

  defp with_fixture(label, fun) do
    with_raw_fixture(label, fn root, path ->
      capability = make_ref()

      with :ok <- initialize(path),
           {:ok, gateway} <-
             Gateway.start_link(
               path: path,
               protected_capability: capability,
               writer_epoch: "fr08a-gate-epoch"
             ) do
        try do
          fun.(gateway, capability, root, path)
        after
          stop_gateway(gateway)
        end
      else
        other -> fail(label, other)
      end
    end)
  end

  defp with_raw_fixture(label, fun) do
    base = if File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()

    root =
      Path.join(
        base,
        "pramana-fr08a-gate-#{label}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)

    try do
      fun.(root, Path.join(root, "authority.sqlite3"))
    after
      File.rm_rf!(root)
    end
  rescue
    _error -> {:fail, "fr08a:#{label}-fixture-failed"}
  catch
    :exit, _reason -> {:fail, "fr08a:#{label}-fixture-exit"}
  end

  defp initialize(path) do
    Gateway.initialize(path, installation_id: "fr08a-gate", repository_id: "pramana-foundry")
  end

  defp stop_gateway(gateway) do
    GenServer.stop(gateway)
  catch
    :exit, _reason -> :ok
  end

  defp pass(label, data), do: {:pass, receipt(label, data)}
  defp fail(label, _value), do: {:fail, "fr08a:#{label}-failed"}

  defp receipt(label, value) do
    bytes =
      :json.encode(%{
        "schema" => "pramana-foundry-fr08a-receipt/v1",
        "label" => label,
        "data" => value
      })

    digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    "fr08a:#{label}:sha256:#{digest}"
  end

  defp implementation_binding do
    if Enum.all?(@api_identity, &loaded_api?/1) do
      "verified:source-sha256+beam-md5/v1"
    else
      "mismatch:source-sha256+beam-md5/v1"
    end
  end

  defp loaded_api?({module, _path, expected_sha256, expected_md5}) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         source when is_list(source) <- module.module_info(:compile)[:source],
         {:ok, bytes} <- File.read(List.to_string(source)) do
      sha256(bytes) == expected_sha256 and
        Base.encode16(module.module_info(:md5), case: :lower) == expected_md5
    else
      _ -> false
    end
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
