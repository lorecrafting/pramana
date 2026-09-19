defmodule Mix.Tasks.Pramana.Commentary.Align do
  @shortdoc "Aligns commentaries to their root texts, lemma by lemma"

  @moduledoc """
  Passage-level 科文 alignment for every asserted `comments_on` and `subcommentary_of`
  relation.

      mix pramana.commentary.align
      mix pramana.commentary.align --work T1789
      mix pramana.commentary.align --dry-run

  Reads `work_relations`, never writes to it. A relation says which work a commentary
  explains; this says which *line*, and it has nothing to say about whether the relation
  itself is right — see `Pramana.Commentary` for why a pair below the density floor is not
  a refuted relation.

  ## Options

    * `--work` — one commentary only, by work id
    * `--dry-run` — measure and report, write nothing
    * `--min-density` — override the floor (spans per 10k commentary characters)

  ## What the report is for

  Every pair is printed with its numbers whether or not it qualified, because the
  interesting rows are the ones that did not. A commentary with thousands of spans that
  still fails the floor is a long commentary on a long root and worth looking at; one with
  four spans is a relation the text does not support in any visible way.
  """

  use Mix.Task

  alias Pramana.Bake
  alias Pramana.Commentary
  alias Pramana.Derivations

  @switches [work: :string, dry_run: :boolean, min_density: :float]

  @syllable_sources ~w(derge derge-tengyur)

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    bake_id = Bake.current_id()
    receipt = begin_receipt(opts, bake_id)
    pairs = Derivations.commentary_pairs(opts[:work])

    Mix.shell().info("""

      commentary alignment — #{length(pairs)} asserted relation(s)

      window        #{Commentary.window()} characters, unique in the root
      floor         #{opts[:min_density] || Commentary.min_density()} spans per 10k commentary characters
      #{if opts[:dry_run], do: "DRY RUN — nothing will be written", else: "bake          #{bake_id}"}
    """)

    # ROOT-MAJOR, AND THAT IS THE WHOLE OPTIMISATION.
    #
    # The cost is linear in characters and the expensive half depends only on the root, so
    # the order pairs are visited in decides how much work is repeated. On 2026-09-03 the
    # 155 asserted pairs covered 60 distinct roots: **41.7M root characters to window 11.0M
    # distinct ones**, against 21.4M on the commentary side. Sorting by root and carrying
    # one prepared root forward pays 32.4M instead of 63.1M — measured at 1,946 chars/s on
    # `T1509`, that is 4.6 hours instead of 9.0.
    #
    # One root, not all of them: a prepared root holds a map entry per character, so the 60
    # of them cannot be resident at once. Sorting is what makes holding one sufficient.
    results =
      pairs
      |> Enum.sort_by(fn {commentary, root, _} -> {root, commentary} end)
      |> Enum.reduce({[], nil}, fn {_, root, source} = pair, {acc, cached} ->
        unit = unit_for(source)
        held = prepared_for(root, cached, unit)

        result =
          align_pair(
            pair,
            opts[:dry_run],
            bake_id,
            elem(held, 1),
            unit,
            opts[:min_density]
          )

        report(result)
        {[result | acc], held}
      end)
      |> then(fn {acc, _} -> Enum.reverse(acc) end)

    stats = summarise(results)
    finish_receipt(receipt, stats)
  end

  defp begin_receipt(opts, bake_id) do
    if opts[:dry_run] do
      nil
    else
      Derivations.begin_run(
        "commentary_align",
        bake_id,
        %{"work" => opts[:work]},
        %{
          "min_density_override" => opts[:min_density],
          "grapheme_window" => Commentary.window(),
          "root_min_density" => Commentary.min_density(),
          "subcommentary_min_density" => Commentary.min_density("subcommentary"),
          "syllable_window" => Commentary.syllable_window(),
          "syllable_min_density" => Commentary.syllable_min_density(),
          "syllable_min_forward" => Commentary.syllable_min_forward()
        }
      )
    end
  end

  defp finish_receipt(nil, _stats), do: :ok
  defp finish_receipt(receipt, stats), do: Derivations.finish_run!(receipt, stats)

  # Keyed on the work id, which sorting has already made consecutive. `prepare_root/2` also
  # checks the body before trusting a prepared form, so a mistake here would be slow rather
  # than wrong.
  # The Degé prints a tsheg between syllables and CBETA prints nothing between characters,
  # so the window unit follows the source. See the note above `@alignable_sources`.
  defp unit_for(source) when source in @syllable_sources, do: :syllable
  defp unit_for(_source), do: :grapheme

  # Keyed on the work id AND the unit: the same root prepared for graphemes is useless for
  # syllables, and reusing it would silently align against the wrong tokenisation.
  defp prepared_for(root, {{root, unit}, _} = held, unit), do: held

  defp prepared_for(root, _other, unit) do
    case Commentary.prepare_root_by_work(root, unit: unit) do
      {:ok, prepared} -> {{root, unit}, prepared}
      _ -> {{root, unit}, nil}
    end
  end

  # A prepared root is an optimisation and never an input to the answer: `nil` here takes
  # the slow path to the same result, which is what makes the cache safe to get wrong.
  defp align_pair(pair, dry_run, bake_id, prepared, unit, min_density) do
    opts =
      [unit: unit]
      |> maybe_prepared(prepared)
      |> maybe_min_density(min_density)

    run_pair(pair, dry_run, bake_id, opts)
  end

  defp maybe_prepared(opts, nil), do: opts
  defp maybe_prepared(opts, prepared), do: Keyword.put(opts, :prepared_root, prepared)

  defp maybe_min_density(opts, nil), do: opts
  defp maybe_min_density(opts, min_density), do: Keyword.put(opts, :min_density, min_density)

  defp run_pair({commentary, root, _source}, true, _bake_id, opts),
    do: Commentary.measure(commentary, root, opts)

  # `{:skip, report}` is not an error: a pair below the density floor is a commentary that
  # paraphrases rather than quotes, which this method cannot see and which says nothing
  # about whether the relation is right. Both shapes carry the same numbers.
  defp run_pair({commentary, root, _source}, _dry_run, bake_id, opts) do
    case Commentary.align(commentary, root, Keyword.put(opts, :bake_id, bake_id)) do
      {:ok, report} -> report
      {:skip, report} -> report
      {:error, reason} -> {:error, commentary, root, reason}
    end
  end

  # THE METHOD IS NOT CHINESE ANY MORE, AND THAT TOOK ONE MEASUREMENT TO FIND OUT.
  #
  # This excluded Tibetan for a year on the grounds that "eight characters of Tibetan is
  # about two syllables, which recur constantly", and that is true and was the wrong
  # conclusion. In its OWN unit Tibetan discriminates better than Chinese:
  #
  #     T0223    8-grapheme windows unique   62.0%
  #     toh4210  6-syllable windows unique   99.8%
  #
  # The tsheg the Degé prints is the segmentation, so no dictionary is needed — the same
  # reasoning that refused `botok` for the lexical layer. `toh4224` -> `toh4210`, the
  # Pramāṇavārttika vṛtti against its kārikā, went from 19,499 spans at 52.1% forward order
  # — noise — to 182 spans at 97.8%.
  #
  # **Tibetan carries a second gate that Chinese does not**, and the difference is evidence
  # rather than language. Of the 40 asserted Tibetan pairs clearing the density floor, 17
  # sit at chance: `toh4220` and `toh4223` both point at `toh4224`, which is itself a
  # vṛtti, so they are sibling commentaries sharing their common root's words. Density
  # cannot see that and forward order can. In Chinese the low-forward pairs are commentaries
  # aligned to a different TRANSLATION of their root — a real alignment to a real work — so
  # gating there would discard something informative. See `Pramana.Commentary`.

  # `subcommentary_of` was excluded until 2026-09-03, when there were nine of them. There
  # are now 38, and 29 are Chinese pairs of exactly the shape this method is for: a 論疏
  # quotes a phrase of its śāstra and glosses it, the same 科文 structure as a 經疏 over a
  # sūtra. Nothing in the method cares which the target is.
  #
  # **Most of them will not clear the floor, and that was measured before including them.**
  # Of twelve, one does — `T1820` 佛遺教經論疏節要 at density 108.5. But the rest are not
  # noise: forward order runs 66–83% against ~50% for chance, which is the discriminator
  # `docs/COMMENTARY.md` uses to tell real structure from overlap. Śāstra exegesis has the
  # structure and quotes less verbatim than sūtra exegesis, and a floor calibrated on 120
  # null pairs of the latter rejects nearly all of the former. Whether that floor is right
  # for this population is a separate question needing its own null set; including the
  # pairs is what puts the numbers in front of anyone who asks it.
  defp report({:error, commentary, root, reason}),
    do: Mix.shell().error("  #{commentary} -> #{root}  #{inspect(reason)}")

  defp report({:error, reason}), do: Mix.shell().error("  #{inspect(reason)}")

  defp report(r) when is_map(r) do
    mark = if r.aligned, do: "✓", else: " "

    Mix.shell().info(
      "  #{mark} #{String.pad_trailing("#{r.commentary_work_id} -> #{r.root_work_id}", 20)}" <>
        " density #{String.pad_leading(fmt(r.density), 7)}" <>
        "  spans #{String.pad_leading("#{r.spans}", 5)}" <>
        "  root #{String.pad_leading(fmt(r.root_pct), 5)}%" <>
        "  forward #{String.pad_leading(fmt(r.forward_pct), 5)}%" <>
        written(r)
    )
  end

  defp written(%{written: n, unresolved: unresolved}) when unresolved > 0,
    do: "  wrote #{n}, #{unresolved} unresolvable"

  defp written(%{written: n}), do: "  wrote #{n}"
  defp written(_), do: ""

  defp fmt(f), do: :erlang.float_to_binary(f * 1.0, decimals: 1)

  defp summarise(results) do
    reports = Enum.filter(results, &is_map/1)
    aligned = Enum.filter(reports, & &1.aligned)
    written = reports |> Enum.map(&Map.get(&1, :written, 0)) |> Enum.sum()
    unresolved = reports |> Enum.map(&Map.get(&1, :unresolved, 0)) |> Enum.sum()
    explicit_failures = Enum.count(results, &match?({:error, _, _, _}, &1))
    failures = explicit_failures + unresolved

    forward = fn rs ->
      case Enum.map(rs, & &1.forward_pct) do
        [] -> 0.0
        vs -> Float.round(Enum.sum(vs) / length(vs), 1)
      end
    end

    Mix.shell().info("""

      aligned       #{length(aligned)} of #{length(reports)} pair(s)
      alignments    #{written}
      forward       #{forward.(aligned)}% mean over aligned pairs, #{forward.(reports -- aligned)}% over the rest

    A pair below the floor is NOT a refuted relation. A commentary may paraphrase its
    root, and several here plainly do; this method can only see verbatim quotation.
    """)

    %{
      "failures" => failures,
      "expected_output_count" => written,
      "pairs_attempted" => length(results),
      "pairs_reported" => length(reports),
      "aligned_pairs" => length(aligned),
      "alignments_written" => written,
      "unresolved_alignments" => unresolved
    }
  end
end
