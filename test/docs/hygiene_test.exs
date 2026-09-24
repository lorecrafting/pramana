defmodule Docs.HygieneTest do
  @moduledoc """
  Model-free checks for repository output and build-context boundaries.

  These inspect declarations and Git ignore behavior, not a live Docker build or
  the contents of an operator's local state. They create no files or processes
  other than the read-only Git command.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "generated outputs are ignored without hiding ordinary evidence inputs" do
    ignored = [
      "pramana/raw",
      "pramana/priv/models",
      "pramana/sources/local/example/text",
      "pramana/_build/test/a.beam",
      "raw/legacy.xml",
      "pramana/priv/embed/__pycache__/probe.cpython-313.pyc"
    ]

    visible = [
      "pramana/evals/gold/retrieval_translation.jsonl",
      "pramana/evals/baseline.json",
      "pramana/sources.lock.json"
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

  test "the Pramana Docker context explicitly excludes Git and native build outputs" do
    patterns =
      @root
      |> Path.join("pramana/.dockerignore")
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

    assert ".git/" in patterns
    assert "apps/pramana_native/native/**/target/" in patterns
    assert "native/quotations/target/" in patterns
  end
end
