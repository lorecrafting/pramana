# Loaded automatically by `iex -S mix`.
#
# Dev-only conveniences. Deliberately NOT in lib/: `find/1` here is a naive SQL
# substring scan, which is fine for browsing 5k segments but is not retrieval. Real
# retrieval (segmentation, pg_bigm, embeddings, RRF) is Phase 1 — see docs/ROADMAP.md.
# Keeping this throwaway helper out of the domain means it can be deleted without
# leaving anything behind.

import Ecto.Query

alias Pramana.Corpus
alias Pramana.Corpus.Segment
alias Pramana.Corpus.Text
alias Pramana.Corpus.Work
alias Pramana.Guard
alias Pramana.Repo
alias Pramana.URN

defmodule P do
  @moduledoc "Playground helpers. `P.help()` to list them."

  import Ecto.Query

  alias Pramana.Corpus
  alias Pramana.Corpus.Segment
  alias Pramana.Guard
  alias Pramana.Repo

  def help do
    IO.puts("""

    Pramāṇa playground
    ------------------
      P.works()               list baked works
      P.stats()               corpus counts
      P.s("如是我聞")         SEARCH — real lexical retrieval (bigram index)
      P.s("空", origin: "indic")   ...with provenance filters
      P.find("空")            naive substring scan (dev only, bypasses ranking)
      P.get(urn)              resolve a URN to a span
      P.show(urn)             pretty-print a passage with provenance
      P.verify(urn, quote)    byte-compare a quotation
      P.check(text)           run the citation guard over a block of prose
      P.apparatus()           segments carrying variant readings
      P.juan(1)               first lines of a fascicle

    URNs look like: pramana:cbeta.T:T0262_001@p0001c17
    """)
  end

  def works do
    Repo.all(from w in Pramana.Corpus.Work, select: {w.id, w.title, w.attributed_author})
  end

  def stats do
    %{
      works: Repo.aggregate(Pramana.Corpus.Work, :count),
      texts: Repo.aggregate(Pramana.Corpus.Text, :count),
      segments: Repo.aggregate(Segment, :count),
      with_apparatus:
        Repo.aggregate(from(s in Segment, where: fragment("? \\? 'apparatus'", s.meta)), :count)
    }
  end

  @doc "Naive substring search. Dev browsing only — see the note at the top of .iex.exs."
  def find(needle, limit \\ 10) do
    Repo.all(
      from s in Segment,
        where: like(s.content, ^"%#{needle}%"),
        order_by: s.ordinal,
        limit: ^limit,
        select: {s.urn, s.content}
    )
    |> Enum.each(fn {urn, content} -> IO.puts("#{urn}\n  #{content}\n") end)
  end

  @doc "Lexical search. The real thing: bigram index, ranking, provenance filters."
  def s(query, opts \\ []) do
    case Pramana.Retrieval.Lexical.search(query, Keyword.put_new(opts, :limit, 5)) do
      {:ok, r} ->
        IO.puts("\n[#{r.mode}] #{r.total} hits  terms: #{inspect(Enum.take(r.terms, 6))}")

        for res <- r.results do
          sc = res.score
          IO.puts("  #{res.span.urn}  (#{sc.terms_matched} matched / #{sc.occurrences}x)")
          IO.puts("    #{res.span.content}")
        end

        :ok

      {:error, reason} ->
        IO.puts("error: #{reason}")
    end
  end

  def get(urn), do: Corpus.resolve(urn)

  def show(urn) do
    case Corpus.resolve(urn) do
      {:ok, s} ->
        p = s.provenance

        IO.puts("""

        #{s.content}

          urn        #{s.urn}
          work       #{p.work_id} — #{p.title}
          author     #{p.attributed_author}
          witness    #{p.witness} vol.#{p.volume}, juan #{p.juan}, page #{p.page}, register #{p.register}, line #{p.line}
          origin     #{p.composition_origin || "(not yet catalogued)"}
          role       #{p.text_role || "(not yet catalogued)"}
          license    #{p.license_class}   addressing: #{p.addressing}
          sha256     #{s.sha256}
          offsets    chars #{s.char_start}..#{s.char_end} / bytes #{s.byte_start}..#{s.byte_end}
          apparatus  #{inspect(s.meta["apparatus"])}
        """)

      {:error, reason} ->
        IO.puts("cannot resolve: #{reason}")
    end
  end

  def verify(urn, quote), do: Guard.verify(urn, quote)
  def check(text), do: Guard.check_output(text)

  def apparatus(limit \\ 5) do
    Repo.all(
      from s in Segment,
        where: fragment("? \\? 'apparatus'", s.meta),
        order_by: s.ordinal,
        limit: ^limit,
        select: {s.urn, s.content, s.meta}
    )
    |> Enum.each(fn {urn, content, meta} ->
      IO.puts("#{urn}\n  #{content}")

      for a <- meta["apparatus"] do
        rdgs =
          Enum.map_join(a["rdgs"], " / ", fn r ->
            if r["omitted"], do: "(omitted) #{r["wit"]}", else: "#{r["text"]} #{r["wit"]}"
          end)

        IO.puts("    #{a["lem"]}  ←→  #{rdgs}")
      end

      IO.puts("")
    end)
  end

  def juan(n, limit \\ 10) do
    Repo.all(
      from s in Segment,
        where: s.juan == ^n,
        order_by: s.ordinal,
        limit: ^limit,
        select: {s.urn, s.content}
    )
    |> Enum.each(fn {urn, content} -> IO.puts("#{urn}\n  #{content}\n") end)
  end
end

IO.puts("\nPramāṇa loaded. `P.help()` for playground commands.\n")
