defmodule Pramana.RuntimePoolTest do
  use ExUnit.Case, async: false

  setup do
    original = Application.fetch_env(:pramana, Pramana.Repo)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:pramana, Pramana.Repo, value)
        :error -> Application.delete_env(:pramana, Pramana.Repo)
      end
    end)

    :ok
  end

  test "pool sizing changes only the pool size and retains every other option" do
    original = Application.get_env(:pramana, Pramana.Repo, [])
    Pramana.Runtime.use_small_pool!(2)
    assert Application.get_env(:pramana, Pramana.Repo) == Keyword.put(original, :pool_size, 2)
  end
end
