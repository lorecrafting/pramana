Code.require_file("../../../ci/validate_fr15aa.exs", __DIR__)

defmodule PramanaFoundry.Repair.FR15aAProvisioningTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.CI.FR15aAValidator

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
    assert Enum.any?(errors, &String.contains?(&1, "missing executable categories: git_metadata"))
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
    assert Enum.any?(errors, &String.contains?(&1, "must fail closed"))
  end

  test "Pi cannot silently become governing", %{manifest: manifest} do
    changed = put_in(manifest.authority.governing_harness, "pi")
    assert {:error, errors} = FR15aAValidator.validate(changed)
    assert "OMP must remain governing" in errors
  end
end
