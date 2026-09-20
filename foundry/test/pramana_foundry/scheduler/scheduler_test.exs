defmodule PramanaFoundry.SchedulerTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Scheduler
  alias PramanaFoundry.Scheduler.Policy

  describe "scopes_may_overlap?/2" do
    test "proves disjoint paths do not overlap" do
      scope1 = ["workflow/lib/pramana_foundry/scheduler/**"]
      scope2 = ["workflow/lib/pramana_foundry/pm/**"]
      refute Policy.scopes_may_overlap?(scope1, scope2)
    end

    test "detects overlapping exact paths" do
      scope1 = ["workflow/lib/pramana_foundry/coordinator.ex"]
      scope2 = ["workflow/lib/pramana_foundry/coordinator.ex"]
      assert Policy.scopes_may_overlap?(scope1, scope2)
    end

    test "detects overlapping parent directory and child wildcard" do
      scope1 = ["workflow/lib/**"]
      scope2 = ["workflow/lib/pramana_foundry/scheduler/policy.ex"]
      assert Policy.scopes_may_overlap?(scope1, scope2)
    end

    test "empty scope fails safe as overlapping" do
      assert Policy.scopes_may_overlap?([], ["workflow/lib/**"])
      assert Policy.scopes_may_overlap?(["workflow/lib/**"], [])
    end
  end

  describe "parallel_conflict/2" do
    @valid_env1 %{
      "MIX_TEST_PARTITION" => "1",
      "MIX_BUILD_PATH" => "/tmp/build-1",
      "PORT" => "4001"
    }
    @valid_env2 %{
      "MIX_TEST_PARTITION" => "2",
      "MIX_BUILD_PATH" => "/tmp/build-2",
      "PORT" => "4002"
    }
    @valid_resources1 %{
      "corpus" => [],
      "database" => [],
      "gpu" => [],
      "other" => ["workflow-engine-1"],
      "service_ports" => ["4001"]
    }
    @valid_resources2 %{
      "corpus" => [],
      "database" => [],
      "gpu" => [],
      "other" => ["workflow-engine-2"],
      "service_ports" => ["4002"]
    }

    test "two isolated workers with disjoint scope and resources can run concurrently" do
      candidate = %{
        "ticket" => %{
          "task_id" => "T1",
          "base_revision" => "abc1234",
          "checkout" => "/tmp/checkout-1",
          "scope" => ["workflow/lib/pramana_foundry/scheduler/**"],
          "environment" => @valid_env1,
          "shared_resources" => @valid_resources1,
          "dependencies" => []
        }
      }

      active = %{
        "status" => "working",
        "run_id" => "run-1",
        "ticket" => %{
          "task_id" => "T2",
          "base_revision" => "abc1234",
          "checkout" => "/tmp/checkout-2",
          "scope" => ["workflow/lib/pramana_foundry/pm/**"],
          "environment" => @valid_env2,
          "shared_resources" => @valid_resources2,
          "dependencies" => []
        }
      }

      assert Policy.parallel_conflict(candidate, active) == nil
    end

    test "conflicts when base revisions differ" do
      candidate = %{
        "ticket" => %{
          "task_id" => "T1",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/checkout-1"
        }
      }

      active = %{
        "status" => "working",
        "run_id" => "run-1",
        "ticket" => %{
          "task_id" => "T2",
          "base_revision" => "rev-B",
          "checkout" => "/tmp/checkout-2"
        }
      }

      assert Policy.parallel_conflict(candidate, active) =~ "stale-base"
    end

    test "conflicts when checkouts collide" do
      candidate = %{
        "ticket" => %{
          "task_id" => "T1",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/shared-checkout"
        }
      }

      active = %{
        "status" => "working",
        "run_id" => "run-1",
        "ticket" => %{
          "task_id" => "T2",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/shared-checkout"
        }
      }

      assert Policy.parallel_conflict(candidate, active) =~
               "serialized: parallel assignments require separate checkouts"
    end

    test "conflicts when active assignment has no distinct run ID" do
      candidate = %{
        "ticket" => %{
          "task_id" => "T1",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/checkout-1"
        }
      }

      active = %{
        "status" => "working",
        "run_id" => nil,
        "ticket" => %{
          "task_id" => "T2",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/checkout-2"
        }
      }

      assert Policy.parallel_conflict(candidate, active) =~
               "serialized: active assignment has no distinct run ID"
    end

    test "conflicts when scopes overlap" do
      candidate = %{
        "ticket" => %{
          "task_id" => "T1",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/checkout-1",
          "scope" => ["workflow/lib/**"],
          "dependencies" => []
        }
      }

      active = %{
        "status" => "working",
        "run_id" => "run-1",
        "ticket" => %{
          "task_id" => "T2",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/checkout-2",
          "scope" => ["workflow/lib/pramana_foundry/**"],
          "dependencies" => []
        }
      }

      assert Policy.parallel_conflict(candidate, active) =~ "scope-conflicting"
    end

    test "conflicts on shared port or shared resource" do
      candidate = %{
        "ticket" => %{
          "task_id" => "T1",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/checkout-1",
          "scope" => ["workflow/lib/scheduler/**"],
          "environment" => @valid_env1,
          "shared_resources" => %{@valid_resources1 | "database" => ["shared_db"]},
          "dependencies" => []
        }
      }

      active = %{
        "status" => "working",
        "run_id" => "run-1",
        "ticket" => %{
          "task_id" => "T2",
          "base_revision" => "rev-A",
          "checkout" => "/tmp/checkout-2",
          "scope" => ["workflow/lib/pm/**"],
          "environment" => @valid_env2,
          "shared_resources" => %{@valid_resources2 | "database" => ["shared_db"]},
          "dependencies" => []
        }
      }

      assert Policy.parallel_conflict(candidate, active) =~
               "exclusive database resource shared_db is already in use"
    end
  end

  describe "plan_dispatch/2" do
    test "pause and stop each block a dispatchable candidate" do
      candidate = assignment("T1", "queued")
      state = %{"queue" => ["T1"], "assignments" => %{"T1" => candidate}}
      assert {:ok, [^candidate]} = Scheduler.plan_dispatch(state)
      assert {:ok, []} = Scheduler.plan_dispatch(Map.put(state, "paused", true))
      assert {:ok, []} = Scheduler.plan_dispatch(Map.put(state, "stop_requested", true))
    end

    test "the default ceiling, rather than a conflicting fixture, prevents a third assignment" do
      candidate = assignment("T3", "queued")

      state = %{
        "queue" => ["T3"],
        "assignments" => %{
          "T1" => assignment("T1", "working"),
          "T2" => assignment("T2", "working"),
          "T3" => candidate
        }
      }

      assert {:ok, [^candidate]} = Scheduler.plan_dispatch(state, max_workers: 3)
      assert {:ok, []} = Scheduler.plan_dispatch(state)
    end
  end

  defp assignment(id, status) do
    %{
      "status" => status,
      "run_id" => "run-#{id}",
      "ticket" => %{
        "task_id" => id,
        "base_revision" => "same-base",
        "checkout" => "/tmp/checkout-#{id}",
        "scope" => ["workflow/lib/#{id}/**"],
        "dependencies" => [],
        "environment" => %{
          "MIX_TEST_PARTITION" => id,
          "MIX_BUILD_PATH" => "/tmp/build-#{id}",
          "PORT" => id
        },
        "shared_resources" => %{
          "corpus" => [],
          "database" => [],
          "gpu" => [],
          "other" => [id],
          "service_ports" => [id]
        }
      }
    }
  end

  test "each exclusive resource class blocks otherwise-disjoint assignments" do
    candidate = assignment("A", "queued")
    active = assignment("B", "working")
    assert Policy.parallel_conflict(candidate, active) == nil

    for resource <- ~w(database corpus gpu other service_ports) do
      first = put_in(candidate, ["ticket", "shared_resources", resource], ["shared"])
      second = put_in(active, ["ticket", "shared_resources", resource], ["shared"])
      assert Policy.parallel_conflict(first, second) != nil, "#{resource} was ignored"
    end
  end
end
