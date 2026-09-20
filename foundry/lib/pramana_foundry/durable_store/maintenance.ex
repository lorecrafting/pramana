defmodule PramanaFoundry.DurableStore.Maintenance do
  @moduledoc """
  Offline verification for a durable-store database or published backup.

  This operation acquires the same OS-process owner as the live gateway. It therefore
  refuses to inspect a database with a live owner and never repairs, replaces or removes
  authority. The returned replay digest is diagnostic evidence, not a second authority.
  """

  alias PramanaFoundry.DurableStore.{Authority, Database, Encoding, Owner, PathIdentity}

  @spec verify(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify(path, opts \\ []) do
    with {:ok, identity} <- PathIdentity.existing(path),
         {:ok, owner} <- Owner.acquire(identity, opts) do
      result =
        with :ok <- PathIdentity.revalidate(owner.identity),
             {:ok, conn} <- Database.open(owner.identity) do
          try do
            with {:ok, view} <- Authority.read(conn, :all),
                 {:ok, last_seq} <- last_sequence(conn) do
              {:ok,
               %{
                 path: path,
                 last_durable_sequence: last_seq,
                 content: view.content,
                 replay: replay_evidence(view.reconstructed)
               }}
            end
          after
            _ = Database.close(conn)
          end
        end

      case {result, Owner.release(owner)} do
        {result, :ok} -> result
        {_result, {:error, reason}} -> {:error, {:maintenance_owner_release_failed, reason}}
      end
    end
  end

  defp last_sequence(conn) do
    case Database.query(conn, "SELECT coalesce(max(seq), 0) FROM events") do
      {:ok, [[sequence]]} -> {:ok, sequence}
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
    end
  end

  defp replay_evidence(state) do
    %{
      projection_count: map_size(state),
      sha256: state |> :erlang.term_to_binary([:deterministic]) |> Encoding.digest(),
      state: state
    }
  end
end
