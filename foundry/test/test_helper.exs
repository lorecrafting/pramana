Code.require_file("support/kernel_harness.ex", __DIR__)

PramanaFoundry.Test.Harness.start()
ExUnit.after_suite(fn _results -> PramanaFoundry.Test.Harness.print_report() end)

ExUnit.start()
