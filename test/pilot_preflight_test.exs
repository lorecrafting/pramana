defmodule Strategy.PilotPreflightTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @manifest Path.join(@root, "docs/strategy/pilot_preflight.json")

  test "current preflight is structurally valid and explicitly blocked" do
    manifest = Pramana.PilotPreflight.load_manifest!(@manifest)

    assert :ok = Pramana.PilotPreflight.validate(manifest, @root)
    assert Pramana.PilotPreflight.status(manifest) == "blocked"

    revision = Pramana.PilotPreflight.git_revision!(@root)
    assert {:error, errors} = Pramana.PilotPreflight.ready(manifest, @root, revision)
    assert "one or more mandatory gates are blocked" in errors
  end

  test "a complete revision-bound ready fixture is accepted" do
    revision = Pramana.PilotPreflight.git_revision!(@root)

    manifest =
      @manifest
      |> Pramana.PilotPreflight.load_manifest!()
      |> Map.put("subject_revision", revision)
      |> Map.update!("gates", fn gates ->
        Enum.map(gates, fn gate ->
          gate
          |> Map.put("state", "ready")
          |> Map.put("reason", nil)
          |> Map.put("evidence", ["docs/strategy/PILOT_PREFLIGHT.md"])
        end)
      end)

    assert :ok = Pramana.PilotPreflight.validate(manifest, @root)
    assert Pramana.PilotPreflight.status(manifest) == "ready"
    assert :ok = Pramana.PilotPreflight.ready(manifest, @root, revision)
  end

  test "ready status is rejected when bound to a stale revision" do
    revision = Pramana.PilotPreflight.git_revision!(@root)

    manifest =
      @manifest
      |> Pramana.PilotPreflight.load_manifest!()
      |> Map.put("subject_revision", String.duplicate("a", 40))
      |> Map.update!("gates", fn gates ->
        Enum.map(gates, fn gate ->
          %{gate | "state" => "ready", "reason" => nil}
        end)
      end)

    assert :ok = Pramana.PilotPreflight.validate(manifest, @root)
    assert {:error, errors} = Pramana.PilotPreflight.ready(manifest, @root, revision)
    assert "subject_revision must equal the exact current Git revision" in errors
  end

  test "mandatory gate set cannot be weakened or duplicated" do
    manifest = Pramana.PilotPreflight.load_manifest!(@manifest)
    [first | rest] = manifest["gates"]

    for gates <- [rest, [first, first | rest]] do
      assert {:error, errors} =
               manifest
               |> Map.put("gates", gates)
               |> Pramana.PilotPreflight.validate(@root)

      assert Enum.any?(errors, &String.contains?(&1, "gate ids"))
    end
  end

  test "ready gates require evidence and blocked gates require reasons" do
    manifest = Pramana.PilotPreflight.load_manifest!(@manifest)
    [first | rest] = manifest["gates"]

    no_evidence = %{first | "state" => "ready", "reason" => nil, "evidence" => []}

    assert {:error, errors} =
             manifest
             |> Map.put("gates", [no_evidence | rest])
             |> Pramana.PilotPreflight.validate(@root)

    assert Enum.any?(errors, &String.contains?(&1, "evidence must be non-empty"))

    no_reason = %{first | "reason" => nil}

    assert {:error, errors} =
             manifest
             |> Map.put("gates", [no_reason | rest])
             |> Pramana.PilotPreflight.validate(@root)

    assert Enum.any?(errors, &String.contains?(&1, "must carry a reason"))
  end

  test "evidence references must be safe existing repository-relative files" do
    manifest = Pramana.PilotPreflight.load_manifest!(@manifest)
    [first | rest] = manifest["gates"]
    unsafe = %{first | "evidence" => ["../private.txt"]}

    assert {:error, errors} =
             manifest
             |> Map.put("gates", [unsafe | rest])
             |> Pramana.PilotPreflight.validate(@root)

    assert "invalid evidence reference \"../private.txt\"" in errors
  end

  test "untracked local files cannot satisfy an evidence reference" do
    manifest = Pramana.PilotPreflight.load_manifest!(@manifest)
    [first | rest] = manifest["gates"]
    relative = "test/.pilot-preflight-untracked-#{System.unique_integer([:positive])}"
    absolute = Path.join(@root, relative)
    File.write!(absolute, "not committed evidence")

    on_exit(fn -> File.rm(absolute) end)

    gate = %{first | "evidence" => [relative]}

    assert {:error, errors} =
             manifest
             |> Map.put("gates", [gate | rest])
             |> Pramana.PilotPreflight.validate(@root)

    assert "invalid evidence reference #{inspect(relative)}" in errors
  end

  test "top-level schema and revision are closed and validated" do
    manifest = Pramana.PilotPreflight.load_manifest!(@manifest)

    assert {:error, errors} =
             manifest
             |> Map.put("unexpected", true)
             |> Pramana.PilotPreflight.validate(@root)

    assert "manifest contains unknown top-level fields" in errors

    assert {:error, errors} =
             manifest
             |> Map.put("subject_revision", "main")
             |> Pramana.PilotPreflight.validate(@root)

    assert "subject_revision must be null or a 40-character lowercase Git SHA" in errors
  end

  test "CLI validates blocked state but refuses readiness" do
    {validated, 0} =
      System.cmd("elixir", ["bin/check_pilot_preflight.exs", "--validate"],
        cd: @root,
        stderr_to_stdout: true
      )

    assert validated =~ "manifest valid; status=blocked"

    {refused, 2} =
      System.cmd("elixir", ["bin/check_pilot_preflight.exs", "--ready"],
        cd: @root,
        stderr_to_stdout: true
      )

    assert refused =~ "one or more mandatory gates are blocked"
  end
end
