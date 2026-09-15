defmodule Docs.HygieneTest do
  @moduledoc """
  Model-free checks for repository output and build-context boundaries.

  These inspect declarations and Git ignore behavior, not a live Docker build or
  the contents of an operator's local state. They create no files or processes
  other than the read-only Git command.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../../..", __DIR__)

  test "generated outputs are ignored without hiding ordinary evidence inputs" do
    ignored = [
      "foundry/cover/index.html",
      "foundry/doc/index.html",
      "priv/embed/__pycache__/probe.cpython-313.pyc",
      "foundry/docs/investigation/__pycache__/probe.pyc"
    ]

    visible = [
      "foundry/docs/investigation/manifest.json",
      "foundry/test/fixtures/telemetry/records-v1.jsonl",
      "evals/gold/retrieval_translation.jsonl",
      "evals/baseline.json",
      "sources.lock.json"
    ]

    for {paths, expected} <- [{ignored, 0}, {visible, 1}], path <- paths do
      {output, status} =
        System.cmd("git", ["check-ignore", "--no-index", "--quiet", "--", path],
          cd: @root,
          stderr_to_stdout: true
        )

      assert status == expected, "unexpected ignore status for #{path}: #{status} #{output}"
    end
  end

  test "the Pramana Docker context explicitly excludes the independent system and Git" do
    patterns =
      @root
      |> Path.join(".dockerignore")
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

    assert "foundry/" in patterns
    assert ".git/" in patterns
  end
end
