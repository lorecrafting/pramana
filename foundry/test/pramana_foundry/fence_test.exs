defmodule PramanaFoundry.FenceTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Fence

  setup do
    root = Path.join(System.tmp_dir!(), "fence-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "integration ownership is singleton", %{root: root} do
    assert {:ok, fence} = Fence.acquire(root, "integration")
    assert {:error, :owned} = Fence.acquire(root, "integration")
    assert :ok = Fence.release(fence)
  end
end
