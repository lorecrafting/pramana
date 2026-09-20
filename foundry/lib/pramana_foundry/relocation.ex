defmodule PramanaFoundry.Relocation do
  @moduledoc """
  Top-level coordinator for journaled workspace relocation.

  Coordinates:
  - Dry-run inventory manifest analysis
  - Append-only journal with fsync for atomic steps
  - Immutable digest preservation and byte-for-byte verification
  - Versioned old-path mapping for historical evidence
  - Safe worktree relocation adaptation via `git worktree move`
  - Temporary original-checkout runtime root protection
  - Deterministic crash recovery (resumption and clean rollback)
  """

  alias PramanaFoundry.Relocation.{
    Digest,
    Journal,
    LocalExclude,
    Manifest,
    PathMap,
    Worktree
  }

  @doc """
  Runs a dry-run inventory analysis across `pramana-*` directories and legacy worktrees/state.
  """
  @spec inventory(keyword()) :: {:ok, Manifest.t()} | {:error, term()}
  def inventory(opts \\ []) do
    Manifest.build(opts)
  end

  @doc """
  Creates a relocation plan based on inventory and options.
  """
  @spec plan(keyword()) :: {:ok, map()} | {:error, term()}
  def plan(opts \\ []) do
    with {:ok, manifest} <- inventory(opts) do
      movable_steps =
        manifest.directories
        |> Enum.filter(fn d -> d.safety.movable and d.destination.path != nil end)
        |> Enum.with_index(1)
        |> Enum.map(fn {d, idx} ->
          %{
            step_id: "step-#{idx}",
            action: if(d.kind == :worktree, do: :move_worktree, else: :move_directory),
            source: d.path,
            destination: d.destination.path,
            kind: d.kind,
            disk_use_bytes: d.disk_use_bytes
          }
        end)

      if manifest.can_relocate or movable_steps == [] do
        {:ok,
         %{
           manifest: manifest,
           steps: movable_steps,
           total_source_bytes: manifest.total_source_bytes,
           destination_headroom_bytes: manifest.destination_headroom_bytes,
           opts: opts
         }}
      else
        reasons =
          Enum.flat_map(manifest.directories, fn d ->
            Enum.map(d.safety.reasons, fn r -> {d.name, r} end)
          end)

        reasons =
          if not manifest.sufficient_headroom do
            [{:all, :insufficient_headroom} | reasons]
          else
            reasons
          end

        {:error, {:cannot_relocate, reasons}}
      end
    end
  end

  @spec execute(map() | keyword(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(plan_or_opts, opts \\ [])

  def execute(%{steps: steps, manifest: manifest} = plan, opts) do
    merged_opts = Keyword.merge(Map.get(plan, :opts, []), opts)
    txid = Keyword.get_lazy(merged_opts, :txid, &generate_txid/0)

    journal_path =
      Keyword.get_lazy(merged_opts, :journal_path, fn ->
        Path.join(System.tmp_dir!(), "pramana-relocation-#{txid}.jsonl")
      end)

    path_map_file =
      Keyword.get_lazy(merged_opts, :path_map_file, fn ->
        Path.join(Path.dirname(journal_path), "path_map.json")
      end)

    serializable_steps =
      Enum.map(steps, fn s ->
        %{
          "step_id" => s.step_id,
          "action" => Atom.to_string(s.action),
          "source" => s.source,
          "destination" => s.destination,
          "kind" => Atom.to_string(s.kind),
          "disk_use_bytes" => s.disk_use_bytes
        }
      end)

    with :ok <- relocation_enabled(),
         {:ok, _} <-
           Journal.init(journal_path, txid,
             metadata: %{"steps_count" => length(steps), "planned_steps" => serializable_steps}
           ),
         :ok <- maybe_protect_runtime_root(merged_opts),
         {:ok, completed_steps, path_map} <- execute_steps(steps, journal_path, txid, merged_opts),
         :ok <- inject_crash(merged_opts, "all", :after_all_steps),
         :ok <- PathMap.save(path_map, path_map_file),
         :ok <- inject_crash(merged_opts, "all", :after_path_map),
         :ok <- maybe_unprotect_runtime_root(merged_opts) do
      {:ok,
       %{
         txid: txid,
         status: :completed,
         journal_path: journal_path,
         path_map: path_map,
         path_map_file: path_map_file,
         completed_steps: completed_steps,
         manifest: manifest
       }}
    end
  end

  def execute(opts, extra_opts) when is_list(opts) do
    combined = Keyword.merge(opts, extra_opts)

    with :ok <- relocation_enabled() do
      case plan(combined) do
        {:ok, p} -> execute(p, combined)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Resumes an interrupted / crashed relocation from its append-only journal.
  """
  @spec resume(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def resume(journal_path, opts \\ []) do
    with :ok <- relocation_enabled(),
         {:ok, state} <- Journal.reconstruct_state(journal_path) do
      txid = state.txid

      path_map_file =
        Keyword.get(opts, :path_map_file, Path.join(Path.dirname(journal_path), "path_map.json"))

      init_entry = Enum.find(state.entries, fn e -> e["step_id"] == "init" end)

      planned_steps =
        if init_entry, do: get_in(init_entry, ["metadata", "planned_steps"]) || [], else: []

      completed_step_ids = Enum.map(state.completed, & &1["step_id"])
      in_flight_step_ids = Enum.map(state.in_flight, & &1["step_id"])

      # 1. Resume in-flight steps
      in_flight_res =
        Enum.reduce_while(state.in_flight, {:ok, [], state.max_seq}, fn step_entry,
                                                                        {:ok, acc, cur_seq} ->
          step_id = step_entry["step_id"]
          source = step_entry["source"]
          destination = step_entry["destination"]
          metadata = step_entry["metadata"] || %{}
          next_seq = cur_seq + 1

          result =
            cond do
              File.exists?(destination) and not File.exists?(source) ->
                pre_digests = metadata["pre_move_digests"] || %{}

                case verify_or_snapshot_dest(destination, pre_digests) do
                  :ok ->
                    Journal.record(
                      journal_path,
                      txid,
                      next_seq,
                      step_id,
                      "resume_complete",
                      :completed,
                      source,
                      destination,
                      metadata
                    )

                    {:ok,
                     %{
                       source: source,
                       destination: destination,
                       kind: String.to_atom(metadata["kind"] || "directory")
                     }}

                  {:error, reason} ->
                    {:error, reason}
                end

              File.exists?(source) ->
                pre_digests = metadata["pre_move_digests"] || take_digests(source)
                updated_meta = Map.put(metadata, "pre_move_digests", pre_digests)

                with {:ok, _} <- Worktree.move(source, destination, opts),
                     :ok <- verify_or_snapshot_dest(destination, pre_digests),
                     :ok <-
                       Journal.record(
                         journal_path,
                         txid,
                         next_seq,
                         step_id,
                         "resume_complete",
                         :completed,
                         source,
                         destination,
                         updated_meta
                       ) do
                  {:ok,
                   %{
                     source: source,
                     destination: destination,
                     kind: String.to_atom(metadata["kind"] || "directory")
                   }}
                end

              true ->
                {:error, {:inconsistent_state_for_step, step_id}}
            end

          case result do
            {:ok, m} -> {:cont, {:ok, [m | acc], next_seq + 1}}
            {:error, err} -> {:halt, {:error, err}}
          end
        end)

      case in_flight_res do
        {:ok, newly_completed, seq_after_inflight} ->
          # 2. Execute any planned steps that were not yet started before crash
          unstarted_steps =
            Enum.filter(planned_steps, fn s ->
              s["step_id"] not in completed_step_ids and s["step_id"] not in in_flight_step_ids
            end)

          unstarted_res =
            Enum.reduce_while(unstarted_steps, {:ok, [], seq_after_inflight}, fn step,
                                                                                 {:ok, acc,
                                                                                  cur_seq} ->
              step_id = step["step_id"]
              source = step["source"]
              destination = step["destination"]
              kind = String.to_atom(step["kind"] || "directory")
              action = String.to_atom(step["action"] || "move_directory")

              pre_move_digests = take_digests(source)

              meta = %{
                "kind" => Atom.to_string(kind),
                "pre_move_digests" => pre_move_digests,
                "disk_use_bytes" => step["disk_use_bytes"] || 0
              }

              with :ok <-
                     Journal.record(
                       journal_path,
                       txid,
                       cur_seq,
                       step_id,
                       action,
                       :prepared,
                       source,
                       destination,
                       meta
                     ),
                   {:ok, _} <- Worktree.move(source, destination, opts),
                   :ok <- verify_or_snapshot_dest(destination, pre_move_digests),
                   :ok <-
                     Journal.record(
                       journal_path,
                       txid,
                       cur_seq + 1,
                       step_id,
                       action,
                       :completed,
                       source,
                       destination,
                       meta
                     ) do
                m = %{source: source, destination: destination, kind: kind}
                {:cont, {:ok, [m | acc], cur_seq + 2}}
              else
                {:error, reason} ->
                  {:halt, {:error, reason}}
              end
            end)

          case unstarted_res do
            {:ok, unstarted_completed, _} ->
              all_completed =
                (Enum.map(state.completed, fn e ->
                   %{
                     source: e["source"],
                     destination: e["destination"],
                     kind: String.to_atom(e["metadata"]["kind"] || "directory")
                   }
                 end) ++ newly_completed ++ unstarted_completed)
                |> Enum.uniq_by(&{&1.source, &1.destination})

              path_map = PathMap.new(txid, all_completed)
              _ = PathMap.save(path_map, path_map_file)

              {:ok,
               %{
                 txid: txid,
                 status: :completed,
                 journal_path: journal_path,
                 path_map: path_map,
                 completed_count: length(all_completed)
               }}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Deterministically rolls back in-flight and completed moves recorded in the journal.
  Reverses moves, verifies restored digests byte-for-byte, and leaves no orphaned state.
  """
  @spec rollback(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def rollback(journal_path, opts \\ []) do
    with :ok <- relocation_enabled(),
         {:ok, state} <- Journal.reconstruct_state(journal_path) do
      txid = state.txid

      # Steps to reverse: in reverse order of chronological execution
      # We reverse completed, in-flight, and failed steps that have destination on disk
      steps_to_reverse =
        (state.in_flight ++ state.completed ++ state.failed)
        |> Enum.uniq_by(fn e -> e["step_id"] end)
        |> Enum.sort_by(fn e -> e["seq"] || 0 end, :desc)

      rollback_result =
        Enum.reduce_while(steps_to_reverse, {:ok, [], state.max_seq}, fn step_entry,
                                                                         {:ok, acc, current_seq} ->
          step_id = step_entry["step_id"]
          source = step_entry["source"]
          destination = step_entry["destination"]
          metadata = step_entry["metadata"] || %{}
          next_seq = current_seq + 1

          # If destination exists on disk, roll it back to source
          if destination != nil and File.exists?(destination) do
            case Worktree.rollback_move(destination, source, opts) do
              {:ok, _} ->
                # Verify SHA-256 byte invariance of restored files
                pre_digests = metadata["pre_move_digests"]

                digest_check =
                  if is_map(pre_digests) and map_size(pre_digests) > 0 do
                    Digest.verify(pre_digests, source)
                  else
                    :ok
                  end

                case digest_check do
                  {:ok, _} ->
                    clean_empty_parent(destination)

                    Journal.record(
                      journal_path,
                      txid,
                      next_seq,
                      step_id,
                      "rollback",
                      :rolled_back,
                      source,
                      destination,
                      metadata
                    )

                    {:cont, {:ok, [step_id | acc], next_seq}}

                  :ok ->
                    clean_empty_parent(destination)

                    Journal.record(
                      journal_path,
                      txid,
                      next_seq,
                      step_id,
                      "rollback",
                      :rolled_back,
                      source,
                      destination,
                      metadata
                    )

                    {:cont, {:ok, [step_id | acc], next_seq}}

                  {:error, reason} ->
                    {:halt, {:error, {:rollback_digest_mismatch, step_id, reason}}}
                end

              {:error, reason} ->
                {:halt, {:error, {:rollback_move_failed, step_id, reason}}}
            end
          else
            # Destination not created or already moved back
            Journal.record(
              journal_path,
              txid,
              next_seq,
              step_id,
              "rollback",
              :rolled_back,
              source,
              destination,
              metadata
            )

            {:cont, {:ok, [step_id | acc], next_seq}}
          end
        end)

      case rollback_result do
        {:ok, rolled_back_steps, _} ->
          # If path_map file exists, remove it on full rollback
          path_map_file =
            Keyword.get(
              opts,
              :path_map_file,
              Path.join(Path.dirname(journal_path), "path_map.json")
            )

          File.rm(path_map_file)

          {:ok,
           %{
             txid: txid,
             status: :rolled_back,
             journal_path: journal_path,
             rolled_back_steps: rolled_back_steps
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp relocation_enabled do
    apply(__MODULE__, :relocation_status, [])
  end

  @doc false
  def relocation_status, do: {:error, {:relocation_disabled, :fr19b_required}}

  defp execute_steps(steps, journal_path, txid, opts) do
    initial_path_map = PathMap.new(txid, [])

    Enum.reduce_while(steps, {:ok, [], initial_path_map, 1}, fn step, {:ok, completed, pm, seq} ->
      step_id = step.step_id
      source = step.source
      destination = step.destination
      kind = step.kind

      # 1. Take pre-move digests
      pre_move_digests = take_digests(source)

      meta = %{
        "kind" => Atom.to_string(kind),
        "pre_move_digests" => pre_move_digests,
        "disk_use_bytes" => step.disk_use_bytes
      }

      # 2. Record :prepared before effect
      with :ok <-
             Journal.record(
               journal_path,
               txid,
               seq,
               step_id,
               step.action,
               :prepared,
               source,
               destination,
               meta
             ),
           :ok <- inject_crash(opts, step_id, :after_prepare),
           :ok <- inject_crash(opts, step_id, :before_move),
           # 3. Perform move
           {:ok, _} <- Worktree.move(source, destination, opts),
           :ok <- inject_crash(opts, step_id, :after_move),
           # 4. Verify post-move digests byte-for-byte
           :ok <- verify_or_snapshot_dest(destination, pre_move_digests),
           :ok <- inject_crash(opts, step_id, :after_digest_verify),
           # 5. Record :completed
           :ok <-
             Journal.record(
               journal_path,
               txid,
               seq + 1,
               step_id,
               step.action,
               :completed,
               source,
               destination,
               meta
             ),
           :ok <- inject_crash(opts, step_id, :after_complete) do
        updated_pm = PathMap.add_mapping(pm, source, destination, kind)
        {:cont, {:ok, [step | completed], updated_pm, seq + 2}}
      else
        {:error, {:injected_crash, _} = crash} ->
          {:halt, {:error, crash}}

        {:error, reason} ->
          _ =
            Journal.record(
              journal_path,
              txid,
              seq + 1,
              step_id,
              step.action,
              :failed,
              source,
              destination,
              Map.put(meta, "error", inspect(reason))
            )

          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, completed, pm, _} -> {:ok, Enum.reverse(completed), pm}
      {:error, reason} -> {:error, reason}
    end
  end

  defp take_digests(source) do
    if File.dir?(source) do
      case Digest.snapshot(source) do
        {:ok, %{digests: digests}} -> digests
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp verify_or_snapshot_dest(destination, pre_digests) do
    if is_map(pre_digests) and map_size(pre_digests) > 0 do
      case Digest.verify(pre_digests, destination) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp maybe_protect_runtime_root(opts) do
    case Keyword.get(opts, :original_checkout) do
      orig when is_binary(orig) ->
        if File.dir?(orig) do
          case LocalExclude.protect(orig) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp maybe_unprotect_runtime_root(opts) do
    if Keyword.get(opts, :unprotect_on_complete, false) do
      case Keyword.get(opts, :original_checkout) do
        orig when is_binary(orig) ->
          LocalExclude.unprotect(orig)

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp clean_empty_parent(path) do
    parent = Path.dirname(path)

    if File.dir?(parent) do
      case File.ls(parent) do
        {:ok, []} -> File.rmdir(parent)
        _ -> :ok
      end
    end
  end

  defp inject_crash(opts, step_id, boundary) do
    case Keyword.get(opts, :crash_at) do
      ^boundary ->
        {:error, {:injected_crash, boundary}}

      {^step_id, ^boundary} ->
        {:error, {:injected_crash, boundary}}

      _ ->
        :ok
    end
  end

  defp generate_txid do
    Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end
end
