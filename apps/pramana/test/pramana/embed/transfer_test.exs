defmodule Pramana.Embed.TransferTest do
  @moduledoc """
  The export/import round trip is how the corpus gets embedded on rented hardware, so
  the checks that matter are the ones preventing a plausible-looking vector from being
  attached to the wrong passage. Every rejected case here would otherwise write 1024
  perfectly valid floats and look fine.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Embed
  alias Pramana.Embed.Transfer
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo

  setup do
    tmp = Path.join(System.tmp_dir!(), "pramana-transfer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    body =
      1..6
      |> Enum.map_join("\n", fn i ->
        n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
        ~s(<lb n="#{n}"/>#{String.duplicate(<<0x4E00 + i::utf8>>, 10)})
      end)

    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title><author>x</author>
    </titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>#{body}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: "T0001", canon: "T", volume: 1, number: "0001")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: %{})
    text_id = Repo.one!(from t in Text, where: t.work_id == "T0001", select: t.id)
    {:ok, _} = Builder.build_for_text(text_id, max_chars: 30)

    %{tmp: tmp, chunks: Repo.all(from c in Chunk, order_by: c.id)}
  end

  defp vector_line(chunk, opts \\ []) do
    dims = Keyword.get(opts, :dims, Embed.dims())

    %{
      "id" => Keyword.get(opts, :id, chunk.id),
      "sha256" => Keyword.get(opts, :sha256, chunk.content_sha256),
      "embedding" => List.duplicate(0.1, dims)
    }
  end

  defp write_vectors(path, rows) do
    File.write!(path, Enum.map_join(rows, "\n", &Jason.encode!/1) <> "\n")
    path
  end

  describe "export/2" do
    test "writes one JSON object per pending chunk", ctx do
      path = Path.join(ctx.tmp, "chunks.jsonl")
      {:ok, info} = Transfer.export(path)

      assert info.chunks == length(ctx.chunks)
      assert info.model == Embed.model()
      assert info.dims == Embed.dims()

      lines = path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
      assert length(lines) == length(ctx.chunks)
      assert %{"id" => _, "content" => _, "sha256" => _} = hd(lines)
    end

    test "carries the content hash, which is what makes the round trip checkable", ctx do
      path = Path.join(ctx.tmp, "chunks.jsonl")
      {:ok, _} = Transfer.export(path)

      exported =
        path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

      by_id = Map.new(exported, &{&1["id"], &1["sha256"]})

      for chunk <- ctx.chunks do
        assert by_id[chunk.id] == chunk.content_sha256
      end
    end

    test "restricts to a division when asked", ctx do
      path = Path.join(ctx.tmp, "none.jsonl")
      {:ok, info} = Transfer.export(path, division: "疑似部")
      assert info.chunks == 0
    end
  end

  describe "import/2 — the checks that matter" do
    test "writes vectors and marks the model", ctx do
      path = write_vectors(Path.join(ctx.tmp, "v.jsonl"), Enum.map(ctx.chunks, &vector_line/1))

      {:ok, r} = Transfer.import(path)

      assert r.written == length(ctx.chunks)
      reloaded = Repo.one!(from c in Chunk, where: c.id == ^hd(ctx.chunks).id)
      assert reloaded.embedding_model == Embed.model()
      assert length(Pgvector.to_list(reloaded.embedding)) == Embed.dims()
    end

    test "REJECTS a vector whose source text no longer matches", ctx do
      # The corpus was re-baked between export and embed: this vector describes text
      # that is no longer at this chunk. Writing it would attach a plausible vector to
      # the wrong passage, and nothing about the result would look wrong.
      chunk = hd(ctx.chunks)
      path = write_vectors(Path.join(ctx.tmp, "v.jsonl"), [vector_line(chunk, sha256: "stale")])

      {:ok, r} = Transfer.import(path)

      assert r.written == 0
      assert r.hash_mismatch == [chunk.id]
      assert Repo.one!(from c in Chunk, where: c.id == ^chunk.id).embedding == nil
    end

    test "rejects wrong dimensionality" do
      chunk = Repo.one!(from c in Chunk, limit: 1)
      tmp = Path.join(System.tmp_dir!(), "wrongdims-#{System.unique_integer([:positive])}.jsonl")
      on_exit(fn -> File.rm(tmp) end)
      write_vectors(tmp, [vector_line(chunk, dims: 768)])

      {:ok, r} = Transfer.import(tmp)

      assert r.written == 0
      assert r.bad_dims == [chunk.id]
    end

    test "rejects unknown chunk ids rather than creating rows", ctx do
      path =
        write_vectors(Path.join(ctx.tmp, "v.jsonl"), [
          %{"id" => 999_999, "sha256" => "x", "embedding" => List.duplicate(0.1, Embed.dims())}
        ])

      {:ok, r} = Transfer.import(path)

      assert r.written == 0
      assert r.unknown == [999_999]
    end

    test "a good row still imports alongside a rejected one", ctx do
      [good, bad | _] = ctx.chunks

      path =
        write_vectors(Path.join(ctx.tmp, "v.jsonl"), [
          vector_line(good),
          vector_line(bad, sha256: "stale")
        ])

      {:ok, r} = Transfer.import(path)

      assert r.written == 1
      assert r.hash_mismatch == [bad.id]
    end

    test "is idempotent", ctx do
      path = write_vectors(Path.join(ctx.tmp, "v.jsonl"), Enum.map(ctx.chunks, &vector_line/1))

      {:ok, first} = Transfer.import(path)
      {:ok, second} = Transfer.import(path)

      assert first.written == second.written

      assert Repo.aggregate(from(c in Chunk, where: not is_nil(c.embedding)), :count) ==
               length(ctx.chunks)
    end
  end

  describe "batched writes" do
    # Writing is batched (one UPDATE ... FROM (VALUES ...) per 1,000 rows) because a
    # statement per row made importing the corpus slower than computing it. These pin
    # the properties batching could plausibly break.

    test "a rejected row does not poison the rest of its batch", ctx do
      # Under batching the danger is an all-or-nothing statement: one bad row taking
      # its 999 neighbours with it, or worse, being written along with them.
      [good, bad | _] = ctx.chunks

      rows = [vector_line(good), vector_line(bad, sha256: "stale"), vector_line(good)]
      path = write_vectors(Path.join(ctx.tmp, "v.jsonl"), rows)

      {:ok, result} = Transfer.import(path)

      assert result.written == 2
      assert result.hash_mismatch == [bad.id]
      assert Repo.get(Chunk, good.id).embedding
      refute Repo.get(Chunk, bad.id).embedding
    end

    test "rows spanning a batch boundary all land", ctx do
      # The batch size is 1,000, so a corpus-sized import crosses the boundary hundreds
      # of times. Repeating one chunk past the boundary exercises the seam without
      # needing 1,000 fixtures.
      chunk = hd(ctx.chunks)
      rows = List.duplicate(vector_line(chunk), 1_100)
      path = write_vectors(Path.join(ctx.tmp, "v.jsonl"), rows)

      {:ok, result} = Transfer.import(path)

      assert result.written == 1_100
      assert Repo.get(Chunk, chunk.id).embedding
    end

    test "an empty batch writes nothing rather than issuing a malformed statement", ctx do
      # Every row rejected means the write list is empty; a naive VALUES builder would
      # emit `VALUES ()` and raise.
      chunk = hd(ctx.chunks)
      rows = [vector_line(chunk, sha256: "stale"), vector_line(chunk, id: 999_999)]
      path = write_vectors(Path.join(ctx.tmp, "v.jsonl"), rows)

      {:ok, result} = Transfer.import(path)

      assert result.written == 0
      refute Repo.get(Chunk, chunk.id).embedding
    end

    test "vectors survive the text round trip exactly", ctx do
      # The vector crosses as a pgvector text literal rather than 1,024 parameters, so
      # the encoding has to be lossless.
      chunk = hd(ctx.chunks)
      vector = Enum.map(1..Embed.dims(), fn i -> Float.round(:math.sin(i), 6) end)

      row = %{"id" => chunk.id, "sha256" => chunk.content_sha256, "embedding" => vector}
      path = write_vectors(Path.join(ctx.tmp, "v.jsonl"), [row])

      {:ok, %{written: 1}} = Transfer.import(path)

      stored = Repo.get(Chunk, chunk.id).embedding |> Pgvector.to_list()

      assert length(stored) == Embed.dims()

      # pgvector stores float4, so the round trip is exact only to single precision.
      # Asserting equality would be asserting something the storage never promised.
      for {a, b} <- Enum.zip(stored, vector) do
        assert_in_delta a, b, 1.0e-6
      end
    end
  end

  describe "round trip" do
    test "export then import leaves every chunk embedded", ctx do
      export_path = Path.join(ctx.tmp, "chunks.jsonl")
      {:ok, _} = Transfer.export(export_path)

      # Stand in for the GPU: echo back id and sha256 untouched, as embed_gpu.py does.
      vectors =
        export_path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(fn line ->
          row = Jason.decode!(line)

          %{
            "id" => row["id"],
            "sha256" => row["sha256"],
            "embedding" => List.duplicate(0.05, Embed.dims())
          }
        end)

      {:ok, r} = Transfer.import(write_vectors(Path.join(ctx.tmp, "v.jsonl"), vectors))

      assert r.written == length(ctx.chunks)
      assert r.hash_mismatch == []
      assert Embed.pending_count() == 0
    end
  end
end
