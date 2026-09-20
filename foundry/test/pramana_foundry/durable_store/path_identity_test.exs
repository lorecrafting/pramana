defmodule PramanaFoundry.DurableStore.PathIdentityTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.DurableStore.PathIdentity

  setup do
    root = Path.join(System.tmp_dir!(), "fr07-path-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "new and existing identities are stable and hardlinks are rejected", %{root: root} do
    path = Path.join(root, "authority.sqlite3")
    assert {:ok, new} = PathIdentity.new(path)
    assert :ok = PathIdentity.revalidate(new)
    File.write!(path, "db")
    assert {:ok, existing} = PathIdentity.existing(path)
    assert :ok = PathIdentity.revalidate(existing)

    alias_path = Path.join(root, "alias.sqlite3")
    File.ln!(path, alias_path)
    assert {:error, :database_hardlink_not_allowed} = PathIdentity.existing(path)
    assert {:error, :database_hardlink_not_allowed} = PathIdentity.existing(alias_path)
  end

  test "raw aliases and symlinks in any component are rejected", %{root: root} do
    path = Path.join(root, "authority.sqlite3")

    for invalid <- [path <> "/", root <> "//authority.sqlite3", root <> "/./authority.sqlite3", root <> "/child/../authority.sqlite3"] do
      assert {:error, :noncanonical_database_path} = PathIdentity.new(invalid)
    end

    real = Path.join(root, "real")
    link = Path.join(root, "link")
    File.mkdir!(real)
    File.ln_s!(real, link)

    assert {:error, :database_parent_symlink_not_allowed} =
             PathIdentity.new(Path.join(link, "authority.sqlite3"))

    assert {:error, :noncanonical_database_path} =
             PathIdentity.new(link <> "/../authority.sqlite3")
  end
end
