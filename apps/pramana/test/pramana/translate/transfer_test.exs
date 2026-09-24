defmodule Pramana.Translate.TransferTest do
  @moduledoc """
  The round trip to a generation host and back.

  Two things are load-bearing. **A rendering that no longer matches its passage is not
  stored** — the hash travels with the text precisely so that a chunk re-chunked between
  export and import cannot have someone else's English attached to it. And **what comes
  back is `t1`/`llm`**, which is invariant #8: the citation guard reads those fields
  before it will let a quote stand as canonical, so a path that stored generated text as
  `human` would defeat the guard without tripping anything.
  """
  use Pramana.DataCase, async: true

  import Ecto.Query

  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Translation
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Translate.Transfer

  setup do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      tradition: "chinese",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Witness{id: "T", name: "Taishō"})
    Repo.insert!(%Work{id: "T0026", title: "中阿含經"})

    text =
      Repo.insert!(%Text{
        work_id: "T0026",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T0026",
        body: "如是我聞一時佛遊舍衛國",
        body_sha256: "x",
        meta: %{}
      })

    chunk =
      Repo.insert!(%Chunk{
        text_id: text.id,
        urn: "pramana:cbeta.T:T0026_001@p0421b01-p0421b05",
        first_ordinal: 0,
        last_ordinal: 4,
        segment_count: 5,
        content: "如是我聞一時佛遊舍衛國",
        content_sha256: "chunkhash",
        char_start: 0,
        char_end: 11,
        byte_start: 0,
        byte_end: 33
      })

    dir = Path.join(System.tmp_dir!(), "pramana-transfer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, chunk: chunk, dir: dir}
  end

  defp write!(dir, rows) do
    path = Path.join(dir, "renderings.jsonl")
    File.write!(path, Enum.map_join(rows, "\n", &Jason.encode!/1) <> "\n")
    path
  end

  describe "export" do
    test "writes the passage with the hash that lets import check it", %{
      chunk: chunk,
      dir: dir
    } do
      path = Path.join(dir, "passages.jsonl")
      {:ok, info} = Transfer.export(path, work: "T0026")

      assert info.chunks == 1

      assert [row] =
               path
               |> File.read!()
               |> String.split("\n", trim: true)
               |> Enum.map(&Jason.decode!/1)

      assert row["id"] == chunk.id
      assert row["sha256"] == "chunkhash"
      assert row["content"] == "如是我聞一時佛遊舍衛國"
      assert row["target_lang"] == "en"
    end
  end

  describe "import" do
    test "stores a rendering as t1/llm, range-anchored to the chunk", %{
      chunk: chunk,
      dir: dir
    } do
      path =
        write!(dir, [
          %{
            id: chunk.id,
            sha256: "chunkhash",
            model: "buddhist-nlp/gemma-2-mitra-it",
            revision: "main",
            params_sha256: "abc123",
            text: "  Thus have I heard. At one time the Buddha was travelling in Śrāvastī.  "
          }
        ])

      {:ok, info} = Transfer.import(path, "model:mitra")

      assert info.read == 1
      assert info.written == 1
      assert info.mismatched == 0

      assert [stored] = Repo.all(from t in Translation, where: t.translator_id == "model:mitra")

      # Invariant #8. If either of these two ever reads "t0"/"human", generated text has
      # become citable as scripture and the guard has nothing left to catch it with.
      assert stored.tier == "t1"
      assert stored.method == "llm"

      assert stored.anchor_urn == chunk.urn
      assert stored.work_id == "T0026"
      assert stored.model_id == "buddhist-nlp/gemma-2-mitra-it"
      assert stored.prompt_version == "abc123"

      assert stored.text ==
               "Thus have I heard. At one time the Buddha was travelling in Śrāvastī."

      refute stored.redistributable

      # Range-anchored, so `Chunk.Vectors.range_renderings/2` can find it. Without these
      # the English exists and is unreachable from the passage it renders — rule 68.
      assert stored.meta["ordinal_start"] == 0
      assert stored.meta["ordinal_end"] == 4

      # The hash of the passage translated, so the rendering survives a re-chunk: every
      # other locator here — the anchor URN, the chunk id, the ordinals — belongs to one
      # particular chunking and changes with it.
      assert stored.meta["source_sha256"] == "chunkhash"
    end

    test "rejects a rendering whose passage has changed since export", %{
      chunk: chunk,
      dir: dir
    } do
      path =
        write!(dir, [
          %{
            id: chunk.id,
            sha256: "a-different-hash",
            model: "m",
            revision: "main",
            params_sha256: "abc123",
            text: "English of some text that is no longer at this id."
          }
        ])

      {:ok, info} = Transfer.import(path, "model:mitra")

      assert info.read == 1
      assert info.written == 0
      assert info.mismatched == 1

      assert Repo.aggregate(
               from(t in Translation, where: t.translator_id == "model:mitra"),
               :count
             ) ==
               0
    end

    test "counts an empty completion rather than storing a blank rendering", %{
      chunk: chunk,
      dir: dir
    } do
      path =
        write!(dir, [
          %{
            id: chunk.id,
            sha256: "chunkhash",
            model: "m",
            revision: "main",
            params_sha256: "abc123",
            text: "   "
          }
        ])

      {:ok, info} = Transfer.import(path, "model:mitra")

      assert info.written == 0
      assert info.empty == 1
    end
  end
end
