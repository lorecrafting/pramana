defmodule PramanaFoundry.WorkPacketTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.WorkPacket
  alias PramanaFoundry.Workflow.Kernel.Execution

  @base_revision String.duplicate("a", 40)

  # ── Fixtures ─────────────────────────────────────────────────────────────

  defp execution(execution_id, role) do
    %Execution{
      execution_id: execution_id,
      role: role,
      lifecycle: "pending",
      result: nil,
      sealed_sequence: nil
    }
  end

  defp ticket(overrides \\ %{}, attempt_overrides \\ %{}) do
    attempt =
      Map.merge(
        %{
          "attempt_id" => "ML-1/A1",
          "candidate_id" => nil,
          "executions" => %{
            "ML-1/A1/dev1" => execution("ML-1/A1/dev1", "developer")
          }
        },
        attempt_overrides
      )

    Map.merge(
      %{
        "ticket_id" => "ML-1",
        "active_attempt_id" => "ML-1/A1",
        "spec_revision_id" => "spec-1",
        "spec" => %{
          "base_revision" => @base_revision,
          "base_ref" => "main",
          "title" => "Add thing",
          "scope" => ["lib/**/*.ex"],
          "acceptance_criteria" => ["tests pass"]
        },
        "attempts" => %{"ML-1/A1" => attempt}
      },
      overrides
    )
  end

  defp effect(overrides \\ %{}) do
    Map.merge(
      %{
        "ticket_id" => "ML-1",
        "attempt_id" => "ML-1/A1",
        "execution_id" => "ML-1/A1/dev1",
        "effect_id" => "effect-1",
        "request_id" => "req-1",
        "role" => "developer",
        "issuer" => "human:raymond",
        "claims" => [
          %{"claim_id" => "claim-1", "writer_epoch" => "epoch-1", "status" => "issued"}
        ]
      },
      overrides
    )
  end

  defp policy(overrides \\ %{}, value_overrides \\ %{}) do
    Map.merge(
      %{
        "policy_id" => "manual-lane",
        "revision" => 3,
        "value" =>
          Map.merge(
            %{"check_set" => [], "independent_of_roles" => %{"reviewer" => ["developer"]}},
            value_overrides
          )
      },
      overrides
    )
  end

  defp reviewer_ticket do
    ticket(%{}, %{
      "candidate_id" => @base_revision,
      "executions" => %{
        "ML-1/A1/dev1" => execution("ML-1/A1/dev1", "developer"),
        "ML-1/A1/rev1" => execution("ML-1/A1/rev1", "reviewer")
      }
    })
  end

  defp reviewer_effect do
    effect(%{
      "execution_id" => "ML-1/A1/rev1",
      "effect_id" => "effect-2",
      "request_id" => "req-2",
      "role" => "reviewer",
      "issuer" => "human:other",
      "claims" => [%{"claim_id" => "claim-2", "writer_epoch" => "epoch-1", "status" => "issued"}]
    })
  end

  # ── Round trips ──────────────────────────────────────────────────────────

  test "a developer packet round-trips through validate/1" do
    assert {:ok, packet} = WorkPacket.build(ticket(), effect(), policy())
    assert WorkPacket.validate(packet) == :ok
    assert packet["role"] == "developer"
    assert packet["candidate"] == nil
    assert packet["return"] == %{"command" => "submit", "ticket_id" => "ML-1"}
  end

  test "a reviewer packet round-trips through validate/1" do
    assert {:ok, packet} = WorkPacket.build(reviewer_ticket(), reviewer_effect(), policy())
    assert WorkPacket.validate(packet) == :ok
    assert packet["role"] == "reviewer"

    assert packet["candidate"] == %{
             "candidate_id" => @base_revision,
             "producer_execution_ids" => ["ML-1/A1/dev1"]
           }

    assert packet["return"] == %{"command" => "review", "ticket_id" => "ML-1"}

    assert packet["independence"] == %{
             "policy_id" => "manual-lane",
             "policy_revision" => 3,
             "independent_of_roles" => ["developer"],
             "excluded_principals" => []
           }
  end

  test "encode/1 is byte-stable across key order" do
    {:ok, packet} = WorkPacket.build(ticket(), effect(), policy())

    reordered =
      packet
      |> Map.to_list()
      |> Enum.reverse()
      |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, v) end)

    assert WorkPacket.encode(packet) == WorkPacket.encode(reordered)
    assert String.ends_with?(WorkPacket.encode(packet), "\n")
    refute String.contains?(WorkPacket.encode(packet), ": ")
    refute String.contains?(WorkPacket.encode(packet), ", ")
  end

  # ── Refusal atoms ────────────────────────────────────────────────────────

  test "refuses when the ticket is not found" do
    assert WorkPacket.build(%{}, effect(), policy()) == {:error, :ticket_not_found}
  end

  test "refuses when there is no active attempt" do
    assert WorkPacket.build(ticket(%{"active_attempt_id" => nil}), effect(), policy()) ==
             {:error, :no_active_attempt}
  end

  test "refuses when the effect names a different ticket or attempt" do
    assert WorkPacket.build(ticket(), effect(%{"ticket_id" => "ML-999"}), policy()) ==
             {:error, :effect_ticket_mismatch}

    assert WorkPacket.build(ticket(), effect(%{"attempt_id" => "ML-1/A9"}), policy()) ==
             {:error, :effect_ticket_mismatch}
  end

  test "refuses an unsupported role" do
    assert WorkPacket.build(ticket(), effect(%{"role" => "pm"}), policy()) ==
             {:error, :unsupported_role}
  end

  test "refuses an execution not in the active attempt" do
    assert WorkPacket.build(ticket(), effect(%{"execution_id" => "ML-1/A1/ghost"}), policy()) ==
             {:error, :execution_not_in_attempt}
  end

  test "refuses when the effect's claim is not issued" do
    stale =
      effect(%{
        "claims" => [%{"claim_id" => "c", "writer_epoch" => "e", "status" => "succeeded"}]
      })

    assert WorkPacket.build(ticket(), stale, policy()) == {:error, :effect_not_issued}

    assert WorkPacket.build(ticket(), effect(%{"claims" => []}), policy()) ==
             {:error, :effect_not_issued}
  end

  test "red control: a spec without base_revision refuses, proving there is no default" do
    bare_spec = ticket() |> get_in(["spec"]) |> Map.delete("base_revision")
    no_revision = ticket(%{"spec" => bare_spec})

    assert WorkPacket.build(no_revision, effect(), policy()) == {:error, :base_revision_missing}
  end

  test "refuses a base_revision that is not a 40-hex sha" do
    bad_spec = Map.put(ticket()["spec"], "base_revision", "not-a-sha")

    assert WorkPacket.build(ticket(%{"spec" => bad_spec}), effect(), policy()) ==
             {:error, :base_revision_not_sha}
  end

  test "refuses a missing or empty scope" do
    empty = Map.put(ticket()["spec"], "scope", [])

    assert WorkPacket.build(ticket(%{"spec" => empty}), effect(), policy()) ==
             {:error, :scope_missing}
  end

  test "refuses missing or empty acceptance criteria" do
    empty = Map.put(ticket()["spec"], "acceptance_criteria", [])

    assert WorkPacket.build(ticket(%{"spec" => empty}), effect(), policy()) ==
             {:error, :acceptance_missing}
  end

  test "refuses a reviewer packet with no frozen candidate" do
    unfrozen =
      ticket(%{}, %{
        "candidate_id" => nil,
        "executions" => %{
          "ML-1/A1/dev1" => execution("ML-1/A1/dev1", "developer"),
          "ML-1/A1/rev1" => execution("ML-1/A1/rev1", "reviewer")
        }
      })

    assert WorkPacket.build(unfrozen, reviewer_effect(), policy()) == {:error, :candidate_missing}
  end

  test "red control: a reviewer policy without independent_of_roles refuses" do
    no_independence = policy(%{}, %{}) |> put_in(["value"], %{"check_set" => []})

    assert WorkPacket.build(reviewer_ticket(), reviewer_effect(), no_independence) ==
             {:error, :independence_policy_missing}
  end

  test "a developer packet does not require independent_of_roles" do
    no_independence = policy(%{}, %{}) |> put_in(["value"], %{"check_set" => []})
    assert {:ok, packet} = WorkPacket.build(ticket(), effect(), no_independence)
    assert packet["independence"]["independent_of_roles"] == []
  end

  test "refuses a non-empty check set" do
    non_empty = policy(%{}, %{"check_set" => ["lint"]})
    assert WorkPacket.build(ticket(), effect(), non_empty) == {:error, :check_set_not_empty}
  end

  # ── validate/1 directly ──────────────────────────────────────────────────

  test "validate/1 refuses a packet missing a field" do
    {:ok, packet} = WorkPacket.build(ticket(), effect(), policy())
    assert WorkPacket.validate(Map.delete(packet, "issuer")) == {:error, :invalid_packet}
  end

  test "validate/1 refuses a packet with an extra field" do
    {:ok, packet} = WorkPacket.build(ticket(), effect(), policy())
    assert WorkPacket.validate(Map.put(packet, "extra", true)) == {:error, :invalid_packet}
  end

  test "validate/1 refuses a packet with a wrong-typed field" do
    {:ok, packet} = WorkPacket.build(ticket(), effect(), policy())

    assert WorkPacket.validate(Map.put(packet, "scope", "not-a-list")) ==
             {:error, :invalid_packet}
  end

  test "validate/1 refuses a non-map" do
    assert WorkPacket.validate(nil) == {:error, :invalid_packet}
    assert WorkPacket.validate("packet") == {:error, :invalid_packet}
  end
end
