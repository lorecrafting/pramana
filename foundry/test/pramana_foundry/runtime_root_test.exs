defmodule PramanaFoundry.RuntimeRootTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.RuntimeRoot

  setup do
    configured = Application.fetch_env!(:pramana_foundry, :runtime_root)
    operator = Application.get_env(:pramana_foundry, :operator_runtime_root)
    active = Application.get_env(:pramana_foundry, :active_runtime_root)
    resolved = Application.get_env(:pramana_foundry, :runtime_root_resolved)
    override = System.get_env("PRAMANA_RUNTIME_ROOT")
    fresh = System.get_env("PRAMANA_RUNTIME_ROOT_FRESH")
    test_parent = exclusive_parent!()

    Application.delete_env(:pramana_foundry, :operator_runtime_root, persistent: true)
    Application.delete_env(:pramana_foundry, :active_runtime_root, persistent: true)
    Application.delete_env(:pramana_foundry, :runtime_root_resolved, persistent: true)

    Application.put_env(
      :pramana_foundry,
      :runtime_root,
      Path.join(test_parent, "operator-state"),
      persistent: true
    )

    on_exit(fn ->
      File.rm_rf!(test_parent)
      Application.put_env(:pramana_foundry, :runtime_root, configured, persistent: true)
      restore_app_env(:operator_runtime_root, operator)
      restore_app_env(:active_runtime_root, active)
      restore_app_env(:runtime_root_resolved, resolved)
      restore_env("PRAMANA_RUNTIME_ROOT", override)
      restore_env("PRAMANA_RUNTIME_ROOT_FRESH", fresh)
    end)

    :ok
  end

  test "test resolution exclusively creates and publishes a non-PID random root" do
    System.delete_env("PRAMANA_RUNTIME_ROOT")
    operator = RuntimeRoot.initialize_operator_root!()
    first = RuntimeRoot.resolve_and_publish!(:test, operator)
    second = RuntimeRoot.resolve_and_publish!(:test, operator)

    on_exit(fn ->
      File.rm_rf!(first)
      File.rm_rf!(second)
    end)

    assert first != second
    assert File.dir?(first)
    assert File.dir?(second)
    refute first =~ System.pid()
    assert RuntimeRoot.fetch!() == second
  end

  test "fetch fails before an active root is explicitly published" do
    assert_raise ArgumentError, ~r/not been resolved and published/, fn ->
      RuntimeRoot.fetch!()
    end
  end

  test "repeat resolution retains the immutable operator root and rejects its descendant" do
    first_parent = exclusive_parent!()
    operator = Path.join(first_parent, "operator-state")
    first = Path.join(first_parent, "first")
    on_exit(fn -> File.rm_rf!(first_parent) end)

    Application.put_env(:pramana_foundry, :runtime_root, operator, persistent: true)
    assert RuntimeRoot.initialize_operator_root!() == operator

    System.put_env("PRAMANA_RUNTIME_ROOT", first)
    RuntimeRoot.resolve_and_publish!(:test, operator)

    System.put_env("PRAMANA_RUNTIME_ROOT", Path.join(operator, "descendant"))
    assert_raise ArgumentError, fn -> RuntimeRoot.resolve_and_publish!(:test, operator) end
    assert Application.fetch_env!(:pramana_foundry, :operator_runtime_root) == operator

    assert_raise ArgumentError, ~r/not been resolved and published/, fn ->
      RuntimeRoot.fetch!()
    end
  end

  test "operator argument mismatch invalidates an earlier publication" do
    operator = RuntimeRoot.initialize_operator_root!()
    root_parent = exclusive_parent!()
    root = Path.join(root_parent, "first")
    on_exit(fn -> File.rm_rf!(root_parent) end)

    System.put_env("PRAMANA_RUNTIME_ROOT", root)
    RuntimeRoot.resolve_and_publish!(:test, operator)
    assert RuntimeRoot.fetch!() == root

    assert_raise ArgumentError, ~r/does not match/, fn ->
      RuntimeRoot.resolve_and_publish!(:test, Path.join(root_parent, "wrong-operator"))
    end

    assert_raise ArgumentError, ~r/not been resolved and published/, fn ->
      RuntimeRoot.fetch!()
    end
  end

  test "empty, relative, live, and already-existing fresh overrides fail before startup" do
    parent = exclusive_parent!()
    configured = Path.join(parent, "operator-state")
    on_exit(fn -> File.rm_rf!(parent) end)
    Application.put_env(:pramana_foundry, :runtime_root, configured, persistent: true)
    operator = RuntimeRoot.initialize_operator_root!()

    for invalid <- ["", "relative/runtime", configured, Path.join(configured, "child")] do
      System.put_env("PRAMANA_RUNTIME_ROOT", invalid)
      assert_raise ArgumentError, fn -> RuntimeRoot.resolve_and_publish!(:test, operator) end
    end

    System.delete_env("PRAMANA_RUNTIME_ROOT")
    System.put_env("PRAMANA_RUNTIME_ROOT_FRESH", "1")
    assert_raise ArgumentError, fn -> RuntimeRoot.resolve_and_publish!(:dev, operator) end

    existing = Path.join(parent, "existing")
    File.mkdir!(existing)
    System.put_env("PRAMANA_RUNTIME_ROOT", existing)
    System.put_env("PRAMANA_RUNTIME_ROOT_FRESH", "1")
    assert_raise ArgumentError, fn -> RuntimeRoot.resolve_and_publish!(:dev, operator) end
  end

  test "fresh roots cannot alias operator state through an ancestor symlink" do
    parent = exclusive_parent!()
    operator = Path.join(parent, "operator")
    alias_path = Path.join(parent, "alias")
    File.mkdir!(operator)
    File.ln_s!(operator, alias_path)
    on_exit(fn -> File.rm_rf!(parent) end)

    Application.put_env(:pramana_foundry, :runtime_root, operator, persistent: true)
    immutable_operator = RuntimeRoot.initialize_operator_root!()
    System.put_env("PRAMANA_RUNTIME_ROOT", Path.join(alias_path, "child"))

    assert_raise ArgumentError, fn ->
      RuntimeRoot.resolve_and_publish!(:test, immutable_operator)
    end
  end

  test "symlink cycles in fresh-root ancestry fail closed" do
    parent = exclusive_parent!()
    left = Path.join(parent, "left")
    right = Path.join(parent, "right")
    File.ln_s!(right, left)
    File.ln_s!(left, right)
    on_exit(fn -> File.rm_rf!(parent) end)

    operator = RuntimeRoot.initialize_operator_root!()
    System.put_env("PRAMANA_RUNTIME_ROOT", Path.join(left, "child"))

    assert_raise ArgumentError, ~r/symlink cycle/, fn ->
      RuntimeRoot.resolve_and_publish!(:test, operator)
    end
  end

  test "an explicit existing root is reusable on restart when fresh mode is disabled" do
    parent = exclusive_parent!()
    root = Path.join(parent, "restart-root")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(parent) end)

    operator = RuntimeRoot.initialize_operator_root!()
    System.put_env("PRAMANA_RUNTIME_ROOT", root)
    System.delete_env("PRAMANA_RUNTIME_ROOT_FRESH")

    # A daemon restart deliberately reuses the same explicit root. Exclusivity is
    # then enforced by RuntimeOwner's lock, not by fresh-root provisioning.
    assert RuntimeRoot.resolve_and_publish!(:dev, operator) == root
    assert RuntimeRoot.resolve_and_publish!(:dev, operator) == root
    assert RuntimeRoot.fetch!() == root
  end

  defp exclusive_parent! do
    suffix = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "fr03-root-test-#{suffix}")

    case File.mkdir(path) do
      :ok ->
        path

      {:error, :eexist} ->
        exclusive_parent!()

      {:error, reason} ->
        raise File.Error, reason: reason, action: "create test parent", path: path
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp restore_app_env(key, nil),
    do: Application.delete_env(:pramana_foundry, key, persistent: true)

  defp restore_app_env(key, value),
    do: Application.put_env(:pramana_foundry, key, value, persistent: true)
end
