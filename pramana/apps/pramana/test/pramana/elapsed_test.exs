defmodule Pramana.ElapsedTest do
  @moduledoc """
  Tests for `Pramana.Elapsed`.

  Verifies runtime duration formatting and throughput rate calculations.
  """
  use ExUnit.Case, async: true

  alias Pramana.Elapsed

  doctest Pramana.Elapsed

  describe "human/1" do
    test "formats durations under 10 seconds with one decimal place" do
      assert Elapsed.human(0) == "0.0s"
      assert Elapsed.human(950) == "0.9s"
      assert Elapsed.human(9_999) == "10.0s"
    end

    test "formats durations between 10 seconds and 1 minute as whole seconds" do
      assert Elapsed.human(10_000) == "10s"
      assert Elapsed.human(15_400) == "15s"
      assert Elapsed.human(59_999) == "59s"
    end

    test "formats durations between 1 minute and 1 hour as minutes and padded seconds" do
      assert Elapsed.human(60_000) == "1m00s"
      assert Elapsed.human(75_000) == "1m15s"
      assert Elapsed.human(605_000) == "10m05s"
      assert Elapsed.human(3_599_000) == "59m59s"
    end

    test "formats durations 1 hour or longer as hours and padded minutes" do
      assert Elapsed.human(3_600_000) == "1h00m"
      assert Elapsed.human(3_930_000) == "1h05m"
      assert Elapsed.human(7_500_000) == "2h05m"
      assert Elapsed.human(36_000_000) == "10h00m"
    end
  end

  describe "rate/2" do
    test "returns dash when duration in ms is 0" do
      assert Elapsed.rate(100, 0) == "—"
    end

    test "calculates items per second with one decimal place" do
      assert Elapsed.rate(1000, 4000) == "250.0"
      assert Elapsed.rate(1, 1000) == "1.0"
      assert Elapsed.rate(10, 3000) == "3.3"
      assert Elapsed.rate(0, 5000) == "0.0"
    end
  end
end
