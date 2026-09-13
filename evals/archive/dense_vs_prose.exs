# DOES INDEX ENGLISH NEED TO BE PROSE?
#
# `docs/TRANSLATION.md` splits generated English by purpose. The *index* tier is matched
# against and never read, so it may not want to be prose: a dense gloss — content words,
# names, doctrinal vocabulary, no connective tissue — packs more retrievable surface per
# token and wastes none on grammar. If it retrieves as well, E1's generation spec gets
# cheaper per chunk before a cent is spent.
#
# TESTED WITHOUT GENERATING ANYTHING, and without writing to the corpus. The bake already
# holds 55,326 human English translation vectors over Pāli. Stripping one to content words
# gives the dense arm from the SAME underlying text, so the only variable is form — not
# translation quality, which is what makes this a fair test of the question actually asked.
#
# ## Why similarity margin rather than a full ranking run
#
# Ranking both arms would need a second index, and `chunk_vectors.kind` is a registry with
# a check constraint — rules 11 to 13 — which an experiment has no business extending. So
# this measures the quantity ranking is made of: how much closer the correct chunk sits to
# the query than the best of N distractors. A form that preserves margin preserves rank.
#
# ## THE FIRST VERSION OF THIS WAS BROKEN, and decisively so
#
# It queried with the very text it was scoring — `embed(t)` against `embed(t)` — so the
# prose arm matched itself at cosine 1.0 by construction and "won" 150 pairs to 0. That is
# not a finding, it is an identity. Rule 62: a measurement bug reads exactly like a result,
# and this one read like a clean, decisive negative.
#
# Fixed by using a SECOND TRANSLATOR'S rendering of the same chunk as the query. 574 chunks
# carry two independent human renderings, which is a real paraphrase written by somebody
# who never saw the other — the closest thing the corpus has to a reader's own words.
import Ecto.Query

alias Pramana.Corpus.ChunkVector
alias Pramana.Embed
alias Pramana.Repo

pairs = String.to_integer(System.get_env("PAIRS") || "150")
distractors = String.to_integer(System.get_env("DISTRACTORS") || "40")
serving = Embed.Serving.name()

stop =
  ~w(a an the and or but if then than that this these those of in on at to from by for
     with without into onto upon over under about as is are was were be been being am
     do does did doing have has had having will would shall should can could may might
     must not no nor so such it its they them their there here when where while who whom
     whose which what how why all any both each few more most other some only own same
     very just also too i you he she we us our your his her him my me one two)
  |> MapSet.new()

dense = fn text ->
  text
  |> String.split(~r/[^\p{L}\p{M}'’-]+/u, trim: true)
  |> Enum.reject(&(String.downcase(&1) in stop))
  |> Enum.uniq_by(&String.downcase/1)
  |> Enum.join(" ")
end

embed = fn text -> Nx.Serving.batched_run(serving, text).embedding |> Nx.to_flat_list() end
dot = fn a, b -> Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end) end

# Ordered by a hash so the sample is the same every run — a curve whose points come from
# different draws is not a curve.
# Chunks rendered by two independent translators: one supplies the query, the other the
# thing being retrieved.
paired =
  from(v in ChunkVector,
    where: v.kind == "translation" and v.lang == "en" and not is_nil(v.embedding),
    where: fragment("length(?) > 200", v.content),
    group_by: v.chunk_id,
    having: count(fragment("distinct ?", v.translator_id)) >= 2,
    order_by: [asc: fragment("abs(hashtext(?::text))", v.chunk_id)],
    limit: ^pairs,
    select: v.chunk_id
  )
  |> Repo.all()

cases =
  from(v in ChunkVector,
    where: v.chunk_id in ^paired and v.kind == "translation" and v.lang == "en",
    order_by: [asc: v.chunk_id, asc: v.translator_id],
    select: %{chunk_id: v.chunk_id, translator_id: v.translator_id, content: v.content}
  )
  |> Repo.all()
  |> Enum.group_by(& &1.chunk_id)
  |> Enum.map(fn {_id, [a, b | _]} -> %{query: a.content, target: b.content} end)

distractor_rows =
  from(v in ChunkVector,
    where: v.kind == "translation" and v.lang == "en" and not is_nil(v.embedding),
    where: v.chunk_id not in ^paired and fragment("length(?) > 200", v.content),
    order_by: [asc: fragment("abs(hashtext(?::text))", v.chunk_id)],
    limit: ^distractors,
    select: %{chunk_id: v.chunk_id, content: v.content}
  )
  |> Repo.all()

IO.puts("embedding #{length(distractor_rows)} distractors...")
distractor_vecs = Enum.map(distractor_rows, &{&1.chunk_id, embed.(&1.content)})

IO.puts("scoring #{length(cases)} pairs...\n")

results =
  cases
  |> Enum.with_index(1)
  |> Enum.map(fn {row, i} ->
    if rem(i, 25) == 0, do: IO.write("\r  #{i}/#{length(cases)}")

    # ONE TRANSLATOR ASKS, THE OTHER ANSWERS. Both arms are scored against the same
    # independently-written query; only the indexed form differs.
    q = embed.(row.query)
    prose = dot.(q, embed.(row.target))
    dense_v = dot.(q, embed.(dense.(row.target)))
    best_distractor = distractor_vecs |> Enum.map(fn {_, v} -> dot.(q, v) end) |> Enum.max()

    %{
      prose_margin: prose - best_distractor,
      dense_margin: dense_v - best_distractor,
      prose_len: String.length(row.target),
      dense_len: String.length(dense.(row.target))
    }
  end)

mean = fn f -> Enum.sum(Enum.map(results, f)) / length(results) end
pct = fn f -> Float.round(100 * Enum.count(results, f) / length(results), 1) end

IO.puts("""
\r
dense vs prose, #{length(results)} pairs, #{length(distractor_rows)} distractors

  mean margin over best distractor
    prose  #{Float.round(mean.(& &1.prose_margin), 4)}
    dense  #{Float.round(mean.(& &1.dense_margin), 4)}

  dense margin >= prose margin   #{pct.(&(&1.dense_margin >= &1.prose_margin))}% of pairs
  dense still beats distractors  #{pct.(&(&1.dense_margin > 0))}% of pairs
  prose still beats distractors  #{pct.(&(&1.prose_margin > 0))}% of pairs

  length: #{round(mean.(& &1.prose_len))} -> #{round(mean.(& &1.dense_len))} chars \
(#{Float.round(100 * mean.(& &1.dense_len) / mean.(& &1.prose_len), 1)}%)
""")
