defmodule PramanaFoundry.ManualLane.Log do
  @moduledoc """
  Observation, never authority (boundary rule 9): the `lane log` trail and the operator log.

  `trail/2` reads the lane store read-only over SQLite, as `Replay` does, so it also runs
  while the Gateway is in recovery: per ticket, its committed events in commit order, the
  refused commands Core recorded under its command ids, and each effect's
  `effect_observation_page`. `operator/2` appends one JSON line per lane command to
  `operator.log.jsonl` beside the store. Nothing reads either back to decide anything.
  """

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Database, ProtectedPrimitives}

  @page %{
    "schema_version" => 1,
    "type" => "effect_observation_page",
    "limit" => 50,
    "max_bytes" => 262_144
  }

  # Core records a refused root command or bundle under its command id; every lane command
  # id begins with its ticket id and a slash.
  @refusals "SELECT command_id, actor_id, reason_code FROM atomic_bundles " <>
              "WHERE disposition != 'accepted' UNION ALL " <>
              "SELECT command_id, actor_id, reason_code FROM root_commands " <>
              "WHERE disposition != 'accepted'"

  @doc "`{:ok, %{ticket_id => trail}}` for one ticket or, with nil, every admitted one."
  def trail(path, ticket_id) do
    with {:ok, conn} <- Sqlite3.open(path, mode: :readonly) do
      try do
        read(conn, ticket_id)
      after
        Sqlite3.close(conn)
      end
    end
  end

  defp read(conn, ticket_id) do
    with {:ok, rows} <- Database.query(conn, "SELECT seq, event FROM events ORDER BY seq"),
         {:ok, refusals} <- Database.query(conn, @refusals) do
      events = for [seq, bytes] <- rows, do: event(seq, JSON.decode!(bytes))

      ids =
        if ticket_id,
          do: [ticket_id],
          else: for(%{"type" => "ticket_admitted", "ticket_id" => id} <- events, do: id)

      Enum.reduce_while(ids, {:ok, %{}}, fn id, {:ok, acc} ->
        case effects(conn, id) do
          {:ok, effects} ->
            trail = %{
              "events" => Enum.filter(events, &(&1["ticket_id"] == id)),
              "refusals" =>
                for(
                  [command_id, actor, reason] <- refusals,
                  String.starts_with?(command_id, id <> "/"),
                  do: %{"command_id" => command_id, "actor" => actor, "reason_code" => reason}
                ),
              "effects" => effects
            }

            {:cont, {:ok, Map.put(acc, id, trail)}}

          error ->
            {:halt, error}
        end
      end)
    end
  end

  # Seq, type and the payload's scalar fields; nested specs and projections are left out.
  defp event(seq, event) do
    event["payload"]
    |> Map.reject(fn {_key, value} -> is_map(value) or is_list(value) end)
    |> Map.merge(%{"seq" => seq, "type" => event["type"]})
  end

  defp effects(conn, ticket_id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT effect_id FROM root_effects WHERE ticket_id = ? ORDER BY rowid",
             [ticket_id]
           ) do
      Enum.reduce_while(rows, {:ok, []}, fn [effect_id], {:ok, acc} ->
        with {:ok, page} <- observation(conn, effect_id, nil, nil),
             {:ok, principals} <- principals(conn, page) do
          {:cont, {:ok, acc ++ [Map.put(page, "principals", principals)]}}
        else
          error -> {:halt, error}
        end
      end)
    end
  end

  # Every page of the effect's observation, its relations concatenated.
  defp observation(conn, effect_id, cursor, acc) do
    query = Map.merge(@page, %{"effect_id" => effect_id, "cursor" => cursor})

    with {:ok, page} <- ProtectedPrimitives.query(conn, query) do
      page = if acc, do: %{acc | "relations" => acc["relations"] ++ page["relations"]}, else: page

      case page["page"]["next_cursor"] do
        nil -> {:ok, Map.delete(page, "page")}
        next -> observation(conn, effect_id, next, page)
      end
    end
  end

  # The page names neither principal: the issuer is on the effect fact, the inbox's
  # authenticated actor on its row (none until an adapter streams into it).
  defp principals(conn, page) do
    query = %{
      "schema_version" => 1,
      "type" => "effect",
      "effect_id" => page["effect"]["effect_id"]
    }

    with {:ok, effect} <- ProtectedPrimitives.query(conn, query),
         {:ok, inbox} <-
           Database.query(
             conn,
             "SELECT actor_id FROM authenticated_inboxes WHERE execution_id = ?",
             [page["effect"]["execution_id"]]
           ) do
      {:ok, %{"issuer" => effect["issuer"], "inbox" => List.first(List.flatten(inbox))}}
    end
  end

  @doc "The trail as text: one line per event, refusal and effect relation."
  def text(%{"mode" => mode, "trail" => tickets}) do
    ["mode: #{mode}\n"] ++
      for {id, t} <- Enum.sort(tickets) do
        [
          "\n#{id}\n  events:\n",
          for(e <- t["events"], do: "    #{e["seq"]} #{e["type"]} #{fields(e)}\n"),
          "  refusals:\n",
          for(
            r <- t["refusals"],
            do: "    #{r["reason_code"]} #{r["command_id"]} by #{r["actor"]}\n"
          ),
          "  effects:\n",
          for(p <- t["effects"], do: effect_text(p))
        ]
      end
  end

  defp fields(event) do
    event
    |> Map.drop(~w(seq type ticket_id))
    |> Enum.sort()
    |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{if is_nil(v), do: "-", else: v}" end)
  end

  defp effect_text(page) do
    %{"issuer" => issuer, "inbox" => inbox} = page["principals"]

    [
      "    #{page["effect"]["effect_id"]} status=#{page["settlement"]["status"]} " <>
        "issuer=#{issuer} inbox=#{inbox || "-"} " <>
        "receipt_history=#{page["settlement"]["receipt_history"]}\n",
      for(r <- page["relations"], do: "      #{relation(r)}\n")
    ]
  end

  defp relation(r) do
    r
    |> Map.drop(["schema_version"])
    |> Enum.sort()
    |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{v}" end)
  end

  @doc """
  Appends one JSON line to `operator.log.jsonl` beside `store_path`. A failed write never
  changes the command's outcome; it prints a warning on stderr. Nil (no lane) writes nothing.
  """
  def operator(nil, _entry), do: :ok

  def operator(store_path, entry) do
    path = Path.join(Path.dirname(store_path), "operator.log.jsonl")

    case File.write(path, JSON.encode!(entry) <> "\n", [:append]) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "warning: operator log not written to #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
