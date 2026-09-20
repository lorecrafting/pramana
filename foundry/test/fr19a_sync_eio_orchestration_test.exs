Code.require_file("../ci/fr19a_sync_eio_orchestration.exs", __DIR__)

defmodule PramanaFoundry.CI.FR19ASyncEIOOrchestrationTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.CI.FR19ASyncEIOOrchestration, as: Orchestration

  test "error resume runs before awaiting a blocked pwrite" do
    parent = self()
    token = make_ref()

    worker =
      spawn(fn ->
        send(parent, {:fr19a_pwrite_entered, token, self()})

        receive do
          {:mapping_resumed, ^token} ->
            send(parent, {:fr19a_pwrite_finished, token, self(), :ok})
        end
      end)

    resume = fn ->
      send(parent, :resume_invoked)
      send(worker, {:mapping_resumed, token})
      :ok
    end

    assert {:ok, :ok} =
             Orchestration.resume_before_await(worker, token, resume,
               observation_ms: 10,
               completion_timeout: 100
             )

    assert_received :resume_invoked
  end

  test "a pwrite that completes while suspended is rejected only after resume" do
    parent = self()
    token = make_ref()

    worker =
      spawn(fn ->
        send(parent, {:fr19a_pwrite_entered, token, self()})
        send(parent, {:fr19a_pwrite_finished, token, self(), :ok})

        receive do
          :stop -> :ok
        end
      end)

    resume = fn ->
      send(parent, :resume_invoked)
      :ok
    end

    assert {:error, {:completed_while_suspended, :ok}} =
             Orchestration.resume_before_await(worker, token, resume, observation_ms: 100)

    assert_received :resume_invoked
    send(worker, :stop)
  end
end
