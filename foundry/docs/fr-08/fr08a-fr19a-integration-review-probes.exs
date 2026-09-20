# Review-only independent integration variations; reuse the public fixture helpers.
ExUnit.start(seed: 20933)
source_path = "test/pramana_foundry/durable_store/fr08a_fr19a_integration_test.exs"
base = File.read!(source_path)
base = String.replace(base, "PramanaFoundry.DurableStore.FR08AFR19AIntegrationTest", "FR08ACombinedIndependentReview")
base = Regex.replace(~r/\nend\s*\z/, base, "\n")

extra = ~S"""
  for status <- ["issued", "unknown"] do
    @review_status status
    test "independent owner death retains closed-generation #{@review_status} authority", %{root: root} do
      path = Path.join(root, "review-owner.sqlite3")
      cap = make_ref()
      parent = self()
      gateway = start_gateway(path, cap, "epoch-A", capacity_probe: fn _ ->
        send(parent, {:review_probe, self()})
        receive do: (:never -> :ok)
      end)
      commit_domain!(gateway, "REVIEW-OWNER")
      seed_claim!(gateway, cap, "epoch-A")
      accept_current!(gateway, cap, issue_operation("epoch-A"))
      if @review_status == "unknown", do: accept_current!(gateway, cap, review_receipt("unknown", "unknown", "outcome_unknown"))
      accept_current!(gateway, cap, %{"type" => "close_generation", "ledger_id" => "root", "generation" => 0})
      assert {:ok, before_view} = Authority.read(:sys.get_state(gateway).conn, :all)
      caller = spawn(fn ->
        try do
          Gateway.operational_health(gateway)
        catch
          :exit, _ -> :ok
        end
      end)
      caller_ref = Process.monitor(caller)
      assert_receive {:review_probe, probe}
      probe_ref = Process.monitor(probe)
      [request] = :sys.get_state(gateway).operational_health_requests |> Map.values()
      controller = request.pid
      controller_ref = Process.monitor(controller)
      owner_ref = Process.monitor(gateway)
      Process.exit(gateway, :kill)
      assert_receive {:DOWN, ^owner_ref, :process, ^gateway, :killed}, 1_000
      assert_receive {:DOWN, ^caller_ref, :process, ^caller, :normal}, 1_000
      assert_receive {:DOWN, ^probe_ref, :process, ^probe, :killed}, 1_000
      assert_receive {:DOWN, ^controller_ref, :process, ^controller, :normal}, 1_000
      reopened = start_recovered(path: path, protected_capability: cap, writer_epoch: "epoch-B", recovery_evidence: "independent monitored owner death")
      assert {:ok, ^before_view} = Authority.read(:sys.get_state(reopened).conn, :all)
      assert_rejected!(reopened, cap, issue_operation("epoch-B"), "claim_issue_not_permitted")
      accept_current!(reopened, cap, review_receipt("late-nonstart", "non_started", "issuer_quiescent"))
      assert {:ok, %{"held" => 0, "retired" => 5, "available" => 0, "status" => "closed"}} = Gateway.protected_query(reopened, cap, %{"schema_version" => 1, "type" => "ledger", "ledger_id" => "root", "generation" => 0})
      backup = Path.join(root, "review-owner-backup.sqlite3")
      assert {:ok, %{content: content}} = Gateway.backup(reopened, backup)
      assert :ok = GenServer.stop(reopened)
      assert {:ok, %{content: ^content}} = Maintenance.verify(backup)
    end
  end

  for point <- [:after_checkpoint, :after_backup_snapshot, :during_backup_sync] do
    @review_point point
    test "independent #{@review_point} failure preserves settled closed-generation full authority", %{root: root} do
      path = Path.join(root, "review-maintenance.sqlite3")
      cap = make_ref()
      fault = case @review_point do
        :during_backup_sync -> {:during, :during_backup_sync, fn _ -> {:error, :review_sync_error} end}
        point -> {:error, point}
      end
      gateway = start_gateway(path, cap, "epoch-A", maintenance_fault: fault)
      commit_domain!(gateway, "REVIEW-MAINTENANCE")
      seed_claim!(gateway, cap, "epoch-A")
      accept_current!(gateway, cap, issue_operation("epoch-A"))
      accept_current!(gateway, cap, %{"type" => "close_generation", "ledger_id" => "root", "generation" => 0})
      accept_current!(gateway, cap, review_receipt("late-success", "succeeded", "delivered"))
      assert {:ok, %{"held" => 0, "consumed" => 1, "retired" => 4, "available" => 0}} = Gateway.protected_query(gateway, cap, %{"schema_version" => 1, "type" => "ledger", "ledger_id" => "root", "generation" => 0})
      conn = :sys.get_state(gateway).conn
      assert {:ok, baseline} = Authority.read(conn, :all)
      target = Path.join(root, "review-failed-backup.sqlite3")
      result = if @review_point == :after_checkpoint, do: Gateway.checkpoint(gateway), else: Gateway.backup(gateway, target)
      assert {:error, {:storage_unavailable, _}} = result
      assert %{mode: :recovery} = Gateway.status(gateway)
      assert {:error, {:recovery_mode, _, _}} = Gateway.operational_health(gateway)
      assert {:error, {:recovery_mode, _}} = Gateway.protected_snapshot(gateway, cap)
      assert {:ok, ^baseline} = Authority.read(conn, :all)
      assert :ok = GenServer.stop(gateway)
      if @review_point != :after_checkpoint do
        assert File.regular?(target)
        assert {:ok, %{content: content, replay: %{state: replay}}} = Maintenance.verify(target)
        assert content == baseline.content
        assert replay == baseline.reconstructed
      end
      reopened = start_existing(path, cap, "epoch-B")
      assert {:ok, ^baseline} = Authority.read(:sys.get_state(reopened).conn, :all)
      recovered = Path.join(root, "review-recovered.sqlite3")
      assert {:ok, %{content: content, reconstruction: %{state: replay}}} = Gateway.backup(reopened, recovered)
      assert content == baseline.content
      assert replay == baseline.reconstructed
      assert :ok = GenServer.stop(reopened)
      assert {:ok, %{content: ^content, replay: %{state: ^replay}}} = Maintenance.verify(recovered)
    end
  end

  defp review_receipt(id, outcome, proof) do
    %{"type" => "settle_claim", "claim_id" => "claim-1", "receipt_id" => id,
      "request_id" => "request-1", "outcome" => outcome, "proof" => proof,
      "payload" => %{"quiescence_epoch" => "epoch-A", "diagnostic" => %{"effect_id" => "opaque", "status" => "diagnostic", "revision" => 99}}}
  end
end
"""
Code.eval_string(base <> extra, [], file: Path.expand(source_path))
