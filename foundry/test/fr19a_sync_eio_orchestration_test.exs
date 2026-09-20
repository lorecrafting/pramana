Code.require_file("../ci/fr19a_sync_eio_orchestration.exs", __DIR__)

defmodule PramanaFoundry.CI.FR19ASyncEIOOrchestrationTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.CI.FR19ASyncEIOOrchestration, as: Orchestration

  test "tracked helper opens and writes its own raw descriptor" do
    path =
      Path.join(System.tmp_dir!(), "fr19a-owned-pwrite-#{System.unique_integer([:positive])}")

    block = :binary.copy("O", 4096)
    File.write!(path, block)
    on_exit(fn -> File.rm(path) end)

    {:ok, holder} = Orchestration.start_pwrite_holder(path, byte_size(block))
    :ok = Orchestration.start_pwrite(holder)

    assert_receive {:fr19a_pwrite_entered, token, worker}, 100
    assert token == holder.token
    assert worker == holder.pid
    assert_receive {:fr19a_pwrite_finished, ^token, ^worker, :ok}, 100
    assert :ok = Orchestration.stop_pwrite_holder(holder)
    assert File.read!(path) == block
  end

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
