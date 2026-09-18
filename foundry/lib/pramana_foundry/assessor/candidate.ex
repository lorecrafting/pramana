defmodule PramanaFoundry.Assessor.Candidate do
  @moduledoc """
  Immutable optional-context candidate.

  The supplied SHA-256 must match the exact content bytes. Candidate contents are data,
  never instructions or authority to fetch additional material.
  """

  @id_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
  @sha_pattern ~r/\A[0-9a-f]{64}\z/
  @max_id_bytes 64
  @max_source_bytes 1_024
  @max_revision_bytes 160
  @max_content_bytes 32_768

  @enforce_keys [:id, :source, :revision, :sha256, :content]
  defstruct [:id, :source, :revision, :sha256, :content]

  @type t :: %__MODULE__{
          id: String.t(),
          source: String.t(),
          revision: String.t(),
          sha256: String.t(),
          content: String.t()
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, atom()}
  def new(attrs) do
    with {:ok, attrs} <- plain_map(attrs),
         {:ok, id} <- required_binary(attrs, :id, @max_id_bytes),
         {:ok, source} <- required_binary(attrs, :source, @max_source_bytes),
         {:ok, revision} <- required_binary(attrs, :revision, @max_revision_bytes),
         {:ok, sha256} <- required_binary(attrs, :sha256, 64),
         {:ok, content} <- required_binary(attrs, :content, @max_content_bytes),
         true <- Regex.match?(@id_pattern, id),
         true <- Regex.match?(@sha_pattern, sha256),
         true <- digest(content) == sha256 do
      {:ok,
       %__MODULE__{
         id: id,
         source: source,
         revision: revision,
         sha256: sha256,
         content: content
       }}
    else
      _ -> {:error, :invalid_candidate}
    end
  end

  @spec digest(binary()) :: String.t()
  def digest(bytes) when is_binary(bytes),
    do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @spec manifest_entry(t()) :: tuple()
  def manifest_entry(%__MODULE__{} = candidate),
    do: {candidate.id, candidate.source, candidate.revision, candidate.sha256}

  defp plain_map(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: {:ok, Map.new(attrs)}, else: {:error, :invalid_candidate}
  end

  defp plain_map(attrs) when is_map(attrs) do
    if is_struct(attrs), do: {:error, :invalid_candidate}, else: {:ok, attrs}
  end

  defp plain_map(_attrs), do: {:error, :invalid_candidate}

  defp required_binary(attrs, key, max_bytes) do
    case Map.fetch(attrs, key) do
      {:ok, value}
      when is_binary(value) and value != "" and byte_size(value) <= max_bytes ->
        if String.valid?(value) and String.trim(value) == value,
          do: {:ok, value},
          else: {:error, :invalid_candidate}

      _ ->
        {:error, :invalid_candidate}
    end
  end
end
