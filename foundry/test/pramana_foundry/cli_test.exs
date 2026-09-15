defmodule PramanaFoundry.CLI.ValidatorsTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.CLI.Validators

  # ── Handoff validation ──

  describe "validate_handoff/1" do
    test "accepts valid handoff" do
      handoff = %{
        "outcome" => "completed",
        "summary" => "Fixed the nil pointer in UserAuth",
        "commit" => "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0",
        "changed_files" => ["lib/user_auth.ex"],
        "checks_passed" => true,
        "evidence" => ["test output: mix test --only handoff"]
      }

      assert Validators.validate_handoff(handoff) == :ok
    end

    test "accepts minimal handoff" do
      handoff = %{
        "outcome" => "partial",
        "summary" => "In-progress changes"
      }

      assert Validators.validate_handoff(handoff) == :ok
    end

    test "rejects missing outcome" do
      handoff = %{"summary" => "test"}
      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "outcome"))
    end

    test "rejects missing summary" do
      handoff = %{"outcome" => "completed"}
      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "summary"))
    end

    test "rejects empty outcome" do
      handoff = %{"outcome" => "", "summary" => "test"}
      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "outcome"))
    end

    test "rejects empty summary" do
      handoff = %{"outcome" => "completed", "summary" => ""}
      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "summary"))
    end

    test "rejects non-map input" do
      assert {:error, _} = Validators.validate_handoff("not a map")
      assert {:error, _} = Validators.validate_handoff(nil)
    end

    test "rejects invalid commit SHA" do
      handoff = %{
        "outcome" => "completed",
        "summary" => "test",
        "commit" => "abc123"
      }

      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "40-character"))
    end

    test "rejects non-hex commit SHA" do
      handoff = %{
        "outcome" => "completed",
        "summary" => "test",
        "commit" => "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
      }

      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "hex"))
    end

    test "accepts non-string commit" do
      handoff = %{
        "outcome" => "completed",
        "summary" => "test",
        "commit" => 12345
      }

      assert {:error, _} = Validators.validate_handoff(handoff)
    end

    test "rejects non-list changed_files" do
      handoff = %{
        "outcome" => "completed",
        "summary" => "test",
        "changed_files" => "not a list"
      }

      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "changed_files"))
    end

    test "rejects non-boolean checks_passed" do
      handoff = %{
        "outcome" => "completed",
        "summary" => "test",
        "checks_passed" => "yes"
      }

      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "checks_passed"))
    end

    test "rejects non-list evidence" do
      handoff = %{
        "outcome" => "completed",
        "summary" => "test",
        "evidence" => "just one evidence string"
      }

      assert {:error, errors} = Validators.validate_handoff(handoff)
      assert Enum.any?(errors, &String.contains?(&1, "evidence"))
    end

    test "accepts missing unresolved_issues (optional)" do
      handoff = %{
        "outcome" => "completed",
        "summary" => "test"
      }

      assert Validators.validate_handoff(handoff) == :ok
    end
  end

  # ── Review validation ──

  describe "validate_review/1" do
    test "accepts valid approved review" do
      review = %{
        "verdict" => "approved",
        "findings" => ["All checks pass", "No scope violations"]
      }

      assert Validators.validate_review(review) == :ok
    end

    test "accepts valid changes_requested review" do
      review = %{
        "verdict" => "changes_requested",
        "findings" => ["Missing error handling in edge case"],
        "remaining_risks" => ["Test coverage could be better"]
      }

      assert Validators.validate_review(review) == :ok
    end

    test "accepts valid rejected review" do
      review = %{
        "verdict" => "rejected",
        "findings" => ["Scope violation: modified files outside ticket scope"],
        "checks" => %{"unit_tests" => "failed", "lint" => "passed"}
      }

      assert Validators.validate_review(review) == :ok
    end

    test "rejects missing verdict" do
      review = %{"findings" => ["test"]}
      assert {:error, errors} = Validators.validate_review(review)
      assert Enum.any?(errors, &String.contains?(&1, "verdict"))
    end

    test "rejects invalid verdict" do
      review = %{"verdict" => "maybe", "findings" => ["test"]}
      assert {:error, errors} = Validators.validate_review(review)
      assert Enum.any?(errors, &String.contains?(&1, "approved"))
      assert Enum.any?(errors, &String.contains?(&1, "rejected"))
    end

    test "rejects missing findings" do
      review = %{"verdict" => "approved"}
      assert {:error, errors} = Validators.validate_review(review)
      assert Enum.any?(errors, &String.contains?(&1, "findings"))
    end

    test "rejects non-list findings" do
      review = %{"verdict" => "approved", "findings" => "just one finding"}
      assert {:error, errors} = Validators.validate_review(review)
      assert Enum.any?(errors, &String.contains?(&1, "findings"))
    end

    test "rejects non-map checks" do
      review = %{
        "verdict" => "approved",
        "findings" => ["ok"],
        "checks" => "passed"
      }

      assert {:error, errors} = Validators.validate_review(review)
      assert Enum.any?(errors, &String.contains?(&1, "checks"))
    end

    test "accepts missing optional fields" do
      review = %{"verdict" => "approved", "findings" => ["ok"]}
      assert Validators.validate_review(review) == :ok
    end

    test "rejects non-map input" do
      assert {:error, _} = Validators.validate_review([])
      assert {:error, _} = Validators.validate_review("review text")
    end
  end

  # ── Ticket validation ──

  describe "validate_ticket/1" do
    test "accepts valid ticket" do
      ticket = %{
        "title" => "Fix nil pointer in UserAuth",
        "scope" => ["lib/user_auth.ex", "test/user_auth_test.exs"],
        "acceptance_criteria" => ["No more nil errors", "Tests pass"]
      }

      assert Validators.validate_ticket(ticket) == :ok
    end

    test "rejects missing title" do
      ticket = %{"scope" => ["."], "acceptance_criteria" => ["test"]}
      assert {:error, errors} = Validators.validate_ticket(ticket)
      assert Enum.any?(errors, &String.contains?(&1, "title"))
    end

    test "rejects missing scope" do
      ticket = %{"title" => "test", "acceptance_criteria" => ["test"]}
      assert {:error, errors} = Validators.validate_ticket(ticket)
      assert Enum.any?(errors, &String.contains?(&1, "scope"))
    end

    test "rejects missing acceptance_criteria" do
      ticket = %{"title" => "test", "scope" => ["."]}
      assert {:error, errors} = Validators.validate_ticket(ticket)
      assert Enum.any?(errors, &String.contains?(&1, "acceptance_criteria"))
    end

    test "rejects non-list scope" do
      ticket = %{
        "title" => "test",
        "scope" => ".",
        "acceptance_criteria" => ["test"]
      }

      assert {:error, errors} = Validators.validate_ticket(ticket)
      assert Enum.any?(errors, &String.contains?(&1, "scope"))
    end
  end

  # ── Individual validators ──

  describe "validate_commit_sha/1" do
    test "accepts 40-char hex" do
      assert Validators.validate_commit_sha(
               "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
             ) == :ok
    end

    test "rejects short hash" do
      assert {:error, msg} = Validators.validate_commit_sha("abc123")
      assert String.contains?(msg, "40-character")
    end

    test "rejects non-hex chars" do
      assert {:error, _} =
               Validators.validate_commit_sha(
                 "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
               )
    end

    test "accepts nil (optional commit)" do
      assert Validators.validate_commit_sha(nil) == :ok
    end
  end

  describe "validate_task_id/1" do
    test "accepts valid IDs" do
      assert Validators.validate_task_id("FIX-42") == :ok
      assert Validators.validate_task_id("IMPRV-7") == :ok
    end

    test "rejects empty string" do
      assert {:error, _} = Validators.validate_task_id("")
    end

    test "rejects whitespace-only" do
      assert {:error, _} = Validators.validate_task_id("   ")
    end

    test "rejects IDs with spaces" do
      assert {:error, _} = Validators.validate_task_id("FIX 42")
    end

    test "rejects non-string" do
      assert {:error, _} = Validators.validate_task_id(nil)
    end
  end

  describe "validate_directory/1" do
    test "accepts existing directory" do
      tmp_dir = System.tmp_dir!()
      assert Validators.validate_directory(tmp_dir) == :ok
    end

    test "rejects non-existent directory" do
      assert {:error, _} = Validators.validate_directory("/nonexistent/path/xyzzy")
    end
  end

  describe "validate_json_file/1" do
    test "reads and parses valid JSON" do
      path = write_tmp_json!(%{"outcome" => "completed"})
      assert {:ok, data} = Validators.validate_json_file(path)
      assert data["outcome"] == "completed"
    end

    test "rejects non-existent file" do
      assert {:error, msg} = Validators.validate_json_file("/tmp/nonexistent.json")
      assert String.contains?(msg, "could not be read")
    end

    test "rejects invalid JSON" do
      path = write_tmp_json_raw!("{broken: json")
      assert {:error, msg} = Validators.validate_json_file(path)
      assert String.contains?(msg, "valid JSON")
    end

    test "rejects non-object JSON" do
      path = write_tmp_json!([1, 2, 3])
      assert {:error, msg} = Validators.validate_json_file(path)
      assert String.contains?(msg, "JSON object")
    end

    test "rejects JSON string" do
      path = write_tmp_json!("just a string")
      assert {:error, _} = Validators.validate_json_file(path)
    end
  end

  # ── Test helpers ──

  defp write_tmp_json!(data) do
    path = "/tmp/pramana_cli_test_#{:erlang.unique_integer([:positive])}.json"
    json = :json.encode(data) |> IO.iodata_to_binary()
    File.write!(path, json)
    path
  end

  defp write_tmp_json_raw!(string) do
    path = "/tmp/pramana_cli_test_#{:erlang.unique_integer([:positive])}.json"
    File.write!(path, string)
    path
  end
end