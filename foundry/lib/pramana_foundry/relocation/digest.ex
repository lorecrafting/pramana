defmodule PramanaFoundry.Relocation.Digest do
  @moduledoc """
  Immutable SHA-256 digest preservation and verification.

  Ensures historical prompts, run logs, and artifacts remain byte-identical
  before and after workspace relocation.
  """

  @default_exclude_dirs [".git"]

  @spec hash_bytes(binary()) :: binary()
  def hash_bytes(bytes) when is_binary(bytes) do
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end

  @spec hash_file(Path.t()) :: {:ok, binary()} | {:error, term()}
  def hash_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, hash_bytes(bytes)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Computes SHA-256 digests for all files in a directory recursively or for an explicit list of files.
  """
  @spec snapshot(Path.t() | [Path.t()], keyword()) ::
          {:ok,
           %{
             root: Path.t(),
             file_count: non_neg_integer(),
             total_bytes: non_neg_integer(),
             digests: %{binary() => binary()}
           }}
          | {:error, term()}
  def snapshot(root, opts \\ [])

  def snapshot(root, opts) when is_binary(root) do
    abs_root = Path.expand(root)

    if File.dir?(abs_root) do
      exclude_dirs = Keyword.get(opts, :exclude_dirs, @default_exclude_dirs)

      case list_files_recursively(abs_root, abs_root, exclude_dirs) do
        {:ok, files} ->
          compute_digests(abs_root, files)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_a_directory}
    end
  end

  def snapshot(files, opts) when is_list(files) do
    base_dir = Keyword.get(opts, :base_dir, "/")
    abs_base = Path.expand(base_dir)

    rel_files =
      Enum.map(files, fn file ->
        abs_file = Path.expand(file)
        Path.relative_to(abs_file, abs_base)
      end)

    compute_digests(abs_base, rel_files)
  end

  @doc """
  Verifies that destination files match the expected relative-path digests byte-for-byte.
  """
  @spec verify(map(), Path.t(), keyword()) ::
          {:ok, %{matched_count: non_neg_integer(), total_bytes: non_neg_integer()}}
          | {:error,
             {:digest_verification_failed,
              %{
                missing: [binary()],
                mismatches: %{binary() => %{expected: binary(), actual: binary()}}
              }}}
  def verify(snapshot_or_digests, destination_dir, _opts \\ [])

  def verify(%{digests: digests}, destination_dir, opts) do
    verify(digests, destination_dir, opts)
  end

  def verify(digests, destination_dir, _opts) when is_map(digests) do
    abs_dest = Path.expand(destination_dir)

    {missing, mismatches, total_bytes, matched_count} =
      Enum.reduce(digests, {[], %{}, 0, 0}, fn {rel_path, expected_hash},
                                               {miss, mism, bytes, count} ->
        full_path = Path.join(abs_dest, rel_path)

        case File.read(full_path) do
          {:ok, content} ->
            actual_hash = hash_bytes(content)

            if actual_hash == expected_hash do
              {miss, mism, bytes + byte_size(content), count + 1}
            else
              mism_entry = %{expected: expected_hash, actual: actual_hash}
              {miss, Map.put(mism, rel_path, mism_entry), bytes, count}
            end

          {:error, :enoent} ->
            {[rel_path | miss], mism, bytes, count}

          {:error, _reason} ->
            {[rel_path | miss], mism, bytes, count}
        end
      end)

    if missing == [] and map_size(mismatches) == 0 do
      {:ok, %{matched_count: matched_count, total_bytes: total_bytes}}
    else
      {:error,
       {:digest_verification_failed,
        %{
          missing: Enum.reverse(missing),
          mismatches: mismatches
        }}}
    end
  end

  defp compute_digests(base_dir, rel_files) do
    result =
      Enum.reduce_while(rel_files, {:ok, %{}, 0}, fn rel_path, {:ok, digests, bytes} ->
        full_path = Path.join(base_dir, rel_path)

        case File.read(full_path) do
          {:ok, content} ->
            hash = hash_bytes(content)
            {:cont, {:ok, Map.put(digests, rel_path, hash), bytes + byte_size(content)}}

          {:error, reason} ->
            {:halt, {:error, {reason, full_path}}}
        end
      end)

    case result do
      {:ok, digests, total_bytes} ->
        {:ok,
         %{
           root: base_dir,
           file_count: map_size(digests),
           total_bytes: total_bytes,
           digests: digests
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_files_recursively(current_dir, root_dir, exclude_dirs) do
    case File.ls(current_dir) do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
          if entry in exclude_dirs do
            {:cont, {:ok, acc}}
          else
            full_path = Path.join(current_dir, entry)

            case File.lstat(full_path) do
              {:ok, %File.Stat{type: :directory}} ->
                case list_files_recursively(full_path, root_dir, exclude_dirs) do
                  {:ok, sub_files} -> {:cont, {:ok, acc ++ sub_files}}
                  {:error, reason} -> {:halt, {:error, reason}}
                end

              {:ok, %File.Stat{type: :regular}} ->
                rel_path = Path.relative_to(full_path, root_dir)
                {:cont, {:ok, [rel_path | acc]}}

              {:ok, %File.Stat{type: :symlink}} ->
                # Symlinks are skipped from content digest or treated separately
                {:cont, {:ok, acc}}

              _ ->
                {:cont, {:ok, acc}}
            end
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
