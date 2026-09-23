Code.require_file("support/kernel_harness.ex", __DIR__)

PramanaFoundry.Test.Harness.start()
ExUnit.after_suite(fn _results -> PramanaFoundry.Test.Harness.print_report() end)

# Tests written against TransitionPlan/RecordCodec vocabulary that FR-08B subcommit 2's
# commit 0 adds. Delete this exclusion in commit 0.
ExUnit.start(exclude: [:needs_commit0])
