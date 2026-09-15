defmodule PramanaFoundry.BoundaryTest do
  use ExUnit.Case, async: true

  @forbidden_apps ~w(phoenix ecto postgrex oban libcluster broadway)a
  @forbidden_packages ~w(phoenix ecto postgrex oban libcluster broadway herdr openai anthropic)

  test "project is standalone, local, and release-capable" do
    project = Mix.Project.config()
    assert project[:releases][:pramana_foundry]
    assert node() == :nonode@nohost

    applications = Application.loaded_applications() |> Enum.map(&elem(&1, 0))
    assert Enum.all?(@forbidden_apps, &(&1 not in applications))
  end

  test "dependency manifests reject forbidden runtime classes" do
    mix = File.read!(Path.expand("../../mix.exs", __DIR__))
    lock = File.read!(Path.expand("../../mix.lock", __DIR__))
    downcased = String.downcase(mix <> lock)

    assert Enum.all?(@forbidden_packages, &(not String.contains?(downcased, ":#{&1}")))
  end

  test "OTP tree exposes one bounded coordinator boundary" do
    children = Supervisor.which_children(PramanaFoundry.Supervisor)

    assert 1 ==
             Enum.count(children, fn {_id, pid, _type, _modules} ->
               pid == Process.whereis(PramanaFoundry.Coordinator)
             end)

    assert Process.whereis(PramanaFoundry.Registry)
    assert Process.whereis(PramanaFoundry.AssignmentSupervisor)
    assert Process.whereis(PramanaFoundry.TaskSupervisor)
  end
end
