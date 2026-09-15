defmodule Docs.HygieneTest do
  @moduledoc """
  Model-free checks for repository output and build-context boundaries.

  These inspect declarations and Git ignore behavior, not a live Docker build or
  the contents of an operator's local state. They create no files or processes
  other than the read-only Git command.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../../../..", __DIR__)

  test "generated outputs are ignored without hiding ordinary evidence inputs" do
    ignored = [
      "pramana/_build/test/artifact.beam",
      "pramana/deps/example/mix.exs",
      "pramana/raw/example.xml",
      "pramana/priv/models/model.safetensors",
      "pramana/sources/local/example/text/page.txt",
      "raw/legacy/example.xml",
      "foundry/cover/index.html",
      "foundry/doc/index.html",
      "pramana/priv/embed/__pycache__/probe.cpython-313.pyc",
      "foundry/docs/investigation/__pycache__/probe.pyc"
    ]

    visible = [
      "foundry/docs/investigation/manifest.json",
      "foundry/test/fixtures/telemetry/records-v1.jsonl",
      "pramana/evals/gold/retrieval_translation.jsonl",
      "pramana/evals/baseline.json",
      "pramana/sources.lock.json",
      "pramana/sources/local/example/manifest.yml",
      "pramana/priv/derge/folio_images.json"
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
      |> Path.join("pramana/.dockerignore")
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

    assert "foundry/" in patterns
    assert ".git/" in patterns
  end
end
