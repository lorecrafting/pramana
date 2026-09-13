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
    test "pause or stop promptly blocks new dispatch" do
      state_paused = %{
        "paused" => true,
        "queue" => ["T1"],
        "assignments" => %{"T1" => %{"status" => "queued"}}
      }

      assert Scheduler.plan_dispatch(state_paused) == {:ok, []}

      state_stopped = %{
        "stop_requested" => true,
        "queue" => ["T1"],
        "assignments" => %{"T1" => %{"status" => "queued"}}
      }

      assert Scheduler.plan_dispatch(state_stopped) == {:ok, []}
    end

    test "respects default ceiling of 2 concurrent workers" do
      assignments = %{
        "T1" => %{"status" => "working", "run_id" => "r1"},
        "T2" => %{"status" => "working", "run_id" => "r2"},
        "T3" => %{"status" => "queued", "ticket" => %{"task_id" => "T3"}}
      }

      state = %{"assignments" => assignments, "queue" => ["T3"]}
      assert Scheduler.plan_dispatch(state) == {:ok, []}
    end
  end
end
