alias Exqlite.Sqlite3

alias PramanaFoundry.DurableStore.Gateway
alias PramanaFoundry.Observations
alias PramanaFoundry.Observations.Query

defmodule FR18AReviewProbe do
  defmodule FakeSource do
    @behaviour PramanaFoundry.Observations.Source

    @impl true
    def snapshot(source), do: {:ok, source.snapshot, source.observed_at}

    @impl true
    def fact(source, %{"type" => type} = query) do
      id = query[identity_key(type)]

      case Map.fetch(source.facts, {type, id}) do
        {:ok, fact} -> {:ok, fact, source.observed_at}
        :error -> {:error, :not_found}
      end
    end

    defp identity_key("effect"), do: "effect_id"
    defp identity_key("control"), do: "control_id"
    defp identity_key("inbox"), do: "execution_id"
  end

  def run do
    root =
      Path.join(
        if(File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()),
        "fr18a-review-probe-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(root)

    try do
      corrupt_reopen_is_collapsed_to_unavailable!(root)
      identity_secret_is_not_redacted!()
      malformed_revision_is_called_canonical!()
      reconciled_success_is_reported_as_conflicting_unknown!(root)
      IO.puts("FR-18A review probes reproduced 4 defects")
    after
      File.rm_rf!(root)
    end
  end

  defp corrupt_reopen_is_collapsed_to_unavailable!(root) do
    path = Path.join(root, "corrupt-reopen.sqlite3")
    capability = make_ref()
    :ok = Gateway.initialize(path, installation_id: "installation", repository_id: "repository")

    {:ok, conn} = Sqlite3.open(path, mode: :readwrite)

    :ok =
      Sqlite3.execute(conn, "UPDATE metadata SET value = '2' WHERE key = 'projection_version'")

    :ok = Sqlite3.close(conn)

    {:ok, gateway} =
      Gateway.start_link(
        path: path,
        protected_capability: capability,
        writer_epoch: "review-writer"
      )

    Process.unlink(gateway)

    %{mode: :recovery, reason: {:authority_corrupt, "metadata", "versions", :unsupported_version}} =
      Gateway.status(gateway)

    %{
      status: :unavailable,
      quality: :unavailable,
      error_code: :source_unavailable,
      items: []
    } = Observations.query(%Query{include_pointers: false}, gateway, capability)

    :ok = GenServer.stop(gateway)
  end

  defp identity_secret_is_not_redacted! do
    observed_at = ~U[2026-09-20 12:00:00Z]
    dummy_secret = "sk-fr18a-review-abcdef12"

    facts = %{
      {"effect", "effect-1"} => effect("effect-1", dummy_secret),
      {"control", "control-1"} => control(),
      {"inbox", "execution-1"} => inbox()
    }

    page =
      Observations.query_source(
        %Query{include_pointers: false, effect_ids: ["effect-1"]},
        {FakeSource, %{snapshot: snapshot(), facts: facts, observed_at: observed_at}},
        now: observed_at
      )

    %{status: :ok, items: [item]} = page
    ^dummy_secret = item.identity["ticket_id"]
    true = inspect(page) =~ dummy_secret
    "[REDACTED]" = item.fact["ticket_id"]
  end

  defp malformed_revision_is_called_canonical! do
    observed_at = ~U[2026-09-20 12:00:00Z]
    malformed = snapshot() |> Map.put("projection_version", nil)

    %{
      status: :ok,
      quality: :canonical,
      source: %{"projection_version" => nil}
    } =
      Observations.query_source(
        %Query{include_pointers: false},
        {FakeSource, %{snapshot: malformed, facts: %{}, observed_at: observed_at}},
        now: observed_at
      )
  end

  defp reconciled_success_is_reported_as_conflicting_unknown!(root) do
    path = Path.join(root, "reconciled.sqlite3")
    capability = make_ref()
    :ok = Gateway.initialize(path, installation_id: "installation", repository_id: "repository")

    {:ok, gateway} =
      Gateway.start_link(
        path: path,
        protected_capability: capability,
        writer_epoch: "writer-epoch"
      )

    Process.unlink(gateway)
    seed_reconciled_success!(gateway, capability)

    %{status: :ok, items: [item]} =
      Observations.query(
        %Query{include_pointers: false, effect_ids: ["effect-1"]},
        gateway,
        capability
      )

    "sk-live-review-abcdef12" = item.identity["ticket_id"]
    true = inspect(item.identity) =~ "sk-live-review-abcdef12"
    "[REDACTED]" = item.fact["ticket_id"]
    "succeeded" = item.fact["status"]
    %{"status" => "unknown", "reason" => "conflicting_receipts"} = item.fact["outcome"]
    :ok = GenServer.stop(gateway)
  end

  defp seed_reconciled_success!(gateway, capability) do
    accept!(gateway, capability, "policy", %{"policy/policy-1" => "absent"}, %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:sk-live-review-abcdef12"]
      }
    })

    accept!(gateway, capability, "control", %{"control/control-1" => "absent"}, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active"}
    })

    accept!(gateway, capability, "ledger", %{"ledger/root/0" => "absent"}, %{
      "type" => "grant_ledger",
      "ledger_id" => "root",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 1
    })

    accept!(
      gateway,
      capability,
      "reservation",
      %{"ledger/root/0" => 0, "reservation/reservation-1" => "absent"},
      %{
        "type" => "reserve",
        "reservation_id" => "reservation-1",
        "ledger_id" => "root",
        "generation" => 0,
        "owner_kind" => "effect",
        "owner_id" => "effect-1",
        "units" => 1
      }
    )

    accept!(
      gateway,
      capability,
      "effect",
      %{
        "effect/effect-1" => "absent",
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 0,
        "ledger/root/0" => 0
      },
      %{
        "type" => "create_effect",
        "effect_id" => "effect-1",
        "request" => %{
          "request_id" => "request-1",
          "role" => "developer",
          "profile" => "sol"
        },
        "operation" => "launch",
        "scope" => "ticket:sk-live-review-abcdef12",
        "ticket_id" => "sk-live-review-abcdef12",
        "attempt_id" => "A1",
        "execution_id" => "execution-1",
        "policy_id" => "policy-1",
        "policy_revision" => 0,
        "control_id" => "control-1",
        "control_revision" => 0,
        "reservation_ids" => ["reservation-1"],
        "leases" => []
      }
    )

    accept!(
      gateway,
      capability,
      "claim",
      %{
        "effect/effect-1" => 0,
        "claim/claim-1" => "absent",
        "reservation/reservation-1" => 1,
        "ledger/root/0" => 1,
        "policy/policy-1" => 0,
        "control/control-1" => 0
      },
      %{
        "type" => "claim_effect",
        "effect_id" => "effect-1",
        "claim_id" => "claim-1",
        "writer_epoch" => "writer-epoch"
      }
    )

    accept!(
      gateway,
      capability,
      "issue",
      %{
        "claim/claim-1" => 0,
        "effect/effect-1" => 1,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 2,
        "ledger/root/0" => 1
      },
      %{
        "type" => "issue_claim",
        "claim_id" => "claim-1",
        "writer_epoch" => "writer-epoch"
      }
    )

    settle!(gateway, capability, "unknown", 1, 2, "receipt-unknown", "unknown", "outcome_unknown")
    settle!(gateway, capability, "success", 2, 3, "receipt-success", "succeeded", "delivered")
  end

  defp settle!(
         gateway,
         capability,
         command_id,
         claim_revision,
         effect_revision,
         receipt_id,
         outcome,
         proof
       ) do
    accept!(
      gateway,
      capability,
      command_id,
      %{
        "claim/claim-1" => claim_revision,
        "effect/effect-1" => effect_revision,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 3,
        "ledger/root/0" => 1,
        "receipt/#{receipt_id}" => "absent"
      },
      %{
        "type" => "settle_claim",
        "claim_id" => "claim-1",
        "receipt_id" => receipt_id,
        "request_id" => "request-1",
        "outcome" => outcome,
        "proof" => proof,
        "payload" => %{"representative" => true}
      }
    )
  end

  defp accept!(gateway, capability, command_id, expected_revisions, operation) do
    request = %{
      "schema_version" => 1,
      "command_id" => command_id,
      "expected_revisions" => expected_revisions,
      "operation" => operation
    }

    {:ok, %{"disposition" => "accepted"}, :committed} =
      Gateway.protected_command(gateway, capability, "operator", request)
  end

  defp snapshot do
    %{
      "schema_version" => 1,
      "installation_id" => "installation-1",
      "repository_id" => "repository-1",
      "writer_epoch" => "writer-epoch-1",
      "last_protected_command_sequence" => 4,
      "last_domain_event_sequence" => 7,
      "protected_schema_version" => "1",
      "projection_version" => "1",
      "pointers" => %{
        "accepted_source" => pointer("accepted_source"),
        "selected_deployment" => pointer("selected_deployment"),
        "healthy_build" => pointer("healthy_build")
      }
    }
  end

  defp pointer(kind) do
    %{
      "schema_version" => 1,
      "pointer_kind" => kind,
      "producer_status" => "absent",
      "revision" => 0
    }
  end

  defp effect(id, ticket_id) do
    %{
      "schema_version" => 1,
      "effect_id" => id,
      "ticket_id" => ticket_id,
      "attempt_id" => "attempt-1",
      "execution_id" => "execution-1",
      "control_id" => "control-1",
      "policy_id" => "policy-1",
      "request_id" => "request-1",
      "assignment_id" => "assignment-1",
      "role" => "developer",
      "operation" => "launch",
      "scope" => "ticket:T1",
      "profile" => "sol",
      "channel" => "protected-gateway",
      "status" => "issued",
      "revision" => 2,
      "policy_revision" => 0,
      "control_revision" => 0,
      "phase_generation" => 0,
      "operation_ordinal" => 0,
      "predecessor_effect_id" => nil,
      "claims" => [],
      "reservations" => []
    }
  end

  defp control do
    %{
      "schema_version" => 1,
      "control_id" => "control-1",
      "revision" => 0,
      "value" => %{"status" => "active"}
    }
  end

  defp inbox do
    %{
      "schema_version" => 1,
      "execution_id" => "execution-1",
      "revision" => 0,
      "last_sequence" => 0,
      "sealed_sequence" => nil,
      "resolution" => %{"status" => "pending"}
    }
  end
end

FR18AReviewProbe.run()
