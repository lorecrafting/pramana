Code.require_file("../../../ci/validate_fr15aa.exs", __DIR__)

defmodule PramanaFoundry.Repair.FR15aAProvisioningTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.CI.FR15aAValidator
  alias PramanaFoundry.CI.FR15aAProcedure

  setup_all do
    path = Path.expand("../../../docs/fr-15a/provisioning-manifest.exs", __DIR__)
    {manifest, _binding} = Code.eval_file(path)
    %{manifest: manifest}
  end

  test "the frozen specification covers every executable route", %{manifest: manifest} do
    assert :ok = FR15aAValidator.validate(manifest)
  end

  test "a missing executable category is rejected", %{manifest: manifest} do
    changed =
      update_in(
        manifest.routes,
        &Enum.reject(&1, fn route -> route.category == "git_metadata" end)
      )

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "route inventory differs"))
  end

  test "an incomplete route mapping is rejected", %{manifest: manifest} do
    changed =
      update_in(manifest.routes, fn [first | rest] ->
        [Map.put(first, :network_policy, "") | rest]
      end)

    assert {:error, errors} = FR15aAValidator.validate(changed)

    assert Enum.any?(
             errors,
             &String.contains?(&1, "lacks principal/channel/credential/network/probe mapping")
           )
  end

  test "unsupported routes cannot claim fail-open behavior", %{manifest: manifest} do
    changed =
      update_in(manifest.routes, fn [first | rest] ->
        [Map.put(first, :fail_closed, false) | rest]
      end)

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "fail-closed"))
  end

  test "Pi cannot silently become governing", %{manifest: manifest} do
    changed = put_in(manifest.authority.governing_harness, "pi")
    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert "OMP must remain governing" in errors
  end

  test "the distinct restricted workflow kernel and protocol are mandatory", %{
    manifest: manifest
  } do
    changed =
      manifest
      |> update_in(
        [:principals],
        &Enum.reject(&1, fn principal -> principal.id == "workflow_kernel" end)
      )
      |> update_in(
        [:routes],
        &Enum.reject(&1, fn route -> route.category == "workflow_kernel" end)
      )
      |> Map.delete(:kernel_protocol)

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "kernel"))
  end

  test "principal accounts cannot collapse into root or become login accounts", %{
    manifest: manifest
  } do
    changed =
      update_in(manifest.principals, fn principals ->
        Enum.map(principals, &Map.merge(&1, %{account: "root", login: true}))
      end)

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "principal"))
  end

  test "channel transport, path and peer grants are required", %{manifest: manifest} do
    changed =
      update_in(manifest.channels, &Enum.map(&1, fn channel -> Map.take(channel, [:id]) end))

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "channel"))
  end

  test "unimplemented routes cannot be promoted or made fail open", %{manifest: manifest} do
    changed =
      update_in(manifest.routes, fn routes ->
        Enum.map(routes, &Map.merge(&1, %{production_status: "supported", fail_closed: false}))
      end)

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "status"))
    assert Enum.any?(errors, &String.contains?(&1, "unimplemented adapter"))
  end

  test "shell cannot move into root or model-request authority", %{manifest: manifest} do
    changed =
      update_in(manifest.routes, fn routes ->
        Enum.map(routes, fn route ->
          if route.category == "shell",
            do: Map.merge(route, %{principal: "root", channel: "model-request"}),
            else: route
        end)
      end)

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "shell route"))
  end

  test "source and host provenance are mandatory", %{manifest: manifest} do
    changed =
      manifest |> Map.delete(:source) |> update_in([:authority], &Map.delete(&1, :host_profile))

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "provenance"))
    assert Enum.any?(errors, &String.contains?(&1, "host profile"))
  end

  test "zero or changed pin digests are rejected", %{manifest: manifest} do
    changed =
      update_in(manifest.pins, fn pins ->
        Enum.map(pins, fn pin ->
          if pin.status == "blocked", do: pin, else: %{pin | sha256: String.duplicate("0", 64)}
        end)
      end)

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "digest differs"))
  end

  test "package lock cannot replace executable provenance", %{manifest: manifest} do
    changed =
      update_in(
        manifest.routes,
        &Enum.map(&1, fn route -> %{route | executable_ids: ["foundry-lock"]} end)
      )

    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert Enum.any?(errors, &String.contains?(&1, "executable provenance"))
  end

  test "process and socket observation errors never mean absence" do
    assert FR15aAProcedure.process_observation("", 2) == {:error, :observer_unknown}
    assert FR15aAProcedure.process_observation("123\n", 0) == {:ok, :present}
    assert FR15aAProcedure.process_observation("", 1) == {:ok, :absent}
    assert FR15aAProcedure.socket_observation("", 1) == {:error, :observer_unknown}

    assert FR15aAProcedure.require_all_absent([{:ok, :present}, {:ok, :absent}]) ==
             {:error, :resource_present}

    assert FR15aAProcedure.require_all_absent([{:error, :observer_unknown}, {:ok, :absent}]) ==
             {:error, :observer_unknown}
  end

  test "directory-service absence is distinct from collision and observer failure" do
    assert FR15aAProcedure.directory_record_observation("record", 0) == {:ok, :present}

    assert FR15aAProcedure.directory_record_observation(
             "DS Error: -14136 (eDSRecordNotFound)",
             56
           ) == {:ok, :absent}

    assert FR15aAProcedure.directory_record_observation("transport failed", 56) ==
             {:error, :observer_unknown}
  end

  test "rollback selects only resources created by this attempt" do
    ledger = [
      %{resource_id: "new", preexisting: false, created_by_attempt: true},
      %{resource_id: "old", preexisting: true, created_by_attempt: false},
      %{resource_id: "absent-not-created", preexisting: false, created_by_attempt: false}
    ]

    assert {:ok, [%{resource_id: "new"}]} = FR15aAProcedure.rollback_targets(ledger)

    assert {:error, :ownership_unknown} =
             FR15aAProcedure.rollback_targets([
               %{resource_id: "contradiction", preexisting: true, created_by_attempt: true}
             ])
  end
end
