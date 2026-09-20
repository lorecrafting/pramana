defmodule PramanaFoundry.Status.RuntimeLabelTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Status

  @key :pramana_runtime_implementation_revision
  @old String.duplicate("a", 40)
  @new String.duplicate("b", 40)

  setup do
    previous = Application.fetch_env(:pramana_foundry, @key)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pramana_foundry, @key, value)
        :error -> Application.delete_env(:pramana_foundry, @key)
      end
    end)

    :ok
  end

  test "updating a presentation label does not establish activation" do
    state = %{"accepted_revision" => @new}
    Status.set_runtime_implementation_revision(@old)
    refute Status.report(state)["revisions_match?"]

    assert Status.reconcile_runtime_implementation_revision(@new) == @new
    report = Status.report(state)
    assert report["revisions_match?"]
    assert report["runtime_implementation_revision"] == @new
    refute report["revision_labels_authoritative?"]
  end

  test "an explicit revision does not initialize the global fallback" do
    Application.delete_env(:pramana_foundry, @key)
    report = Status.report(%{"accepted_revision" => @old}, runtime_implementation_revision: @old)

    assert report["revisions_match?"]
    assert Application.fetch_env(:pramana_foundry, @key) == :error
  end
end
