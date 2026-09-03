defmodule Pramana.Commentary do
  @moduledoc """
  Which line of a commentary explains which line of its root text — 科文 alignment,
  found deterministically.

  `Pramana.Relations` can say *T1789 comments on T0670*. `docs/COMMENTARY.md` calls that
  "easy and only mildly useful", and names this the highest-value piece of the feature:
  landing on a dense canonical line and being handed the layers of explanation attached to
  **that line**, each labelled with when and where it was written.

  No model is involved, which is `CLAUDE.md` invariant #5 in its strongest form. A Chinese
  commentary works by quoting a phrase of its root and then glossing it, so the alignment
  is already written down in the text — it only has to be read.

  ## The uniqueness rule

  A lemma anchors to a root position when its **8-character window occurs exactly once in
  the root**. That is the whole method, and the reason it needs no threshold to defend: a
  commentary quoting 云何為二 tells you nothing about where in the root it is looking,
  because that phrase is everywhere; a window occurring once tells you exactly. Uniqueness
  is a property of the root text, measured, not a similarity score.

  Windows are then collapsed into maximal runs where **both sides advance together**, so
  one continuous quotation is one alignment rather than thirteen overlapping windows of
  itself. The median run is about ten characters, which is what a 科文 lemma looks like.

  ## What it was measured against

  Four well-attested pairs, and the same commentaries against roots they do not explain:

  |  | asserted pairs | roots they do not explain |
  |---|---|---|
  | root printed lines carrying an anchor | 70–78% | 0.5–1.9% |
  | root quoted verbatim | 52–61% | 0.5–0.8% |
  | consecutive anchors moving forward | 88–95% | ~50%, which is chance |

  The forward figure is the one that says this is really 科文 structure and not incidental
  overlap: a commentary walks its root in order, and unrelated texts match in no order at
  all.

  ## Density decides, and root coverage does not

  **`root_pct` was also wrong until 2026-09-03**, and the figures below are the corrected
  ones. It summed span lengths, which double-counts every overlap, so it could exceed its
  own denominator — and did: 4 of 184 Chinese pairs to 125%, and 67 of 102 Tibetan pairs to
  **1102%**. `T1509`'s coverage of `T0223` was published as 83.2% and is 64.5%. Nothing
  gated on it, so no alignment decision moved; `covered_chars/1` now measures the union.

  The obvious gate — what fraction of the root is quoted — is **scale-sensitive and was
  nearly shipped**, because the denominator is the wrong object. `T1742` quotes 177 lemmas
  from T0278 at a density of 69.2, more than twice the floor, and forward order of 82.4%;
  its root coverage is **0.3%**, which is *below* what unrelated pairs score. Any
  root-coverage threshold strict enough to exclude the null band would have thrown it out.

  A first version of this doc claimed T1736 as the example — 2,536 lemmas from the
  80-fascicle Avataṃsaka at 3.9% coverage — and said the density gate rescued it. **It does
  not.** T1736's density is 20.4 and it fails this gate too, which is a fact worth keeping
  rather than a counter-example to hide: its title, 大方廣佛華嚴經隨疏演義鈔, says it
  expounds *following the 疏*, and the 疏 is T1735, Chengguan's own commentary on the sūtra.
  The `comments_on` row points at the sūtra because it was asserted by title match. A
  sub-commentary quoting its commentary sparsely from the root is the expected shape, and
  the alignment declining to fire is the method behaving correctly on a relation aimed one
  layer too far down.

  So the gate is `spans / 10k characters of the COMMENTARY` — how densely this commentary
  quotes, which does not shrink as the root grows. Measured over the 89 asserted
  `comments_on` relations and **120 null pairs**, built by giving each commentary three
  roots it does not explain:

      spans per 10k commentary chars    median     p90     max
        asserted                          28.0   175.5   250.5
        null                               0.5    11.3    28.4

      floor    asserted        null
        10       61/89       12/120
        20       51/89        4/120
        25       46/89        3/120
        30       43/89        0/120
        40       35/89        0/120

  **The floor is 30 because the null maximum is 28.4.** It was 25 for an afternoon, chosen
  when the null set was 40 pairs whose p90 was 10.8 and whose maximum nothing had looked
  at. Tripling the null set moved the observed maximum from below 11 to 28.4, and 25 turned
  out to admit three of them. The lesson is not about this number: **a threshold calibrated
  against a thin tail is calibrated against nothing**, and the way to find out is to make
  the tail bigger rather than to reason about it.

  The margin at 30 is 1.6, which is thin, and a null pair somewhere in the corpus may well
  clear it. `forward_pct` is the second signal for exactly that case — 77.1% median across
  asserted pairs against 47.1% across nulls — and it rides on every row rather than being
  folded into the gate, because two signals a caller can see beat one number it cannot.

  ## Forward order finds the translation a commentary is NOT quoting

  Over the 42 aligned pairs, forward order runs 58% to 96% — and the whole low end is one
  situation. `T1510b`, `T1511`, `T1703`, `T1704` and `T1515` each align against **four
  different translations of the same sūtra**: T0235 (Kumārajīva), T0236a and T0236b
  (Bodhiruci), T0237 (Paramārtha), all titled 金剛般若波羅蜜經. The same happens for the
  three Heart Sūtra translations and the two Nirvāṇa recensions.

  A commentary quotes **one** of them. It aligns to the others because translations of one
  Indic original share phrasing with each other, so lemmas match out of order. Every pair
  in that cluster sits at 58–70% forward; every single-root pair sits at 79–96%.

  ## What gating on it would cost, measured 2026-09-03

  Both premises of the decision below have since changed — 42 aligned pairs are now 76, and
  "the density floor already separates cleanly" is true of Chinese and false elsewhere. The
  Tibetan relations, which `mix pramana.commentary.align` excludes structurally, are a
  ready-made population where the method's premise is known false, so they price a gate:

      rule                              Chinese kept    Tibetan admitted
      forward >= 65                        74 of 76           6 of 98
      forward >= 70                        69 of 76           2 of 98
      forward >= 75 and density <= 250     58 of 76           0 of 98

  **A percentage separates; significance does not.** The null for forward order is a coin,
  so testing `z` looks principled — but every Chinese pair clears z = 2.03 and so do 55 of
  98 Tibetan ones, because `toh4025` has 8,260 spans and 67.6% is overwhelming at that n.
  With enough spans, noise is significant. Effect size is the signal here.

  **The seven Chinese pairs lost at 70 are not junk, which is why this is still not
  gated.** They are the cross-translation cluster below — `T1510b` → `T0236b` at 67.3%,
  `T1511` → `T0236b` at 67.0% — real alignments to a real work that the commentary is not
  quoting. Whether that is an alignment is a question about what the corpus should assert,
  not a threshold to tune, and the source guard already handles the case this measurement
  came from. The numbers are here so the decision can be made rather than re-derived.

  This is reported, not gated on. Forty-two pairs was not enough to place a second
  threshold, and the obvious reading — that the highest-forward root is the translation
  actually being quoted — is **not supported**: all four Diamond Sūtra commentaries peak on
  T0236a regardless of who translated them, so something about that text rather than about
  the commentaries is doing the ranking. The number rides in each row's `meta` so a caller
  can weigh it.

  ## What a pair below the floor means, and does not

  It means **no passage-level alignment**, not a refuted relation. A commentary is free to
  paraphrase its root, and several here plainly do. Nothing about the `comments_on` row is
  changed by failing this test; the row records what a catalogue or a title asserted, and
  this method has nothing to say about it either way.
  """

  import Ecto.Query

  alias Pramana.Corpus.CommentaryAlignment
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Repo
  alias Pramana.URN

  # Eight characters. Long enough that a window is almost always unique where it matches —
  # 94% of shared 6-grams already are — and short enough to catch the median 10-character
  # lemma whole rather than only its longer siblings.
  @window 8

  # Spans per 10,000 characters of commentary, and the value is measured — see the module
  # doc. It sits just above the highest density any of 120 null pairs reached.
  @min_density 30.0

  @type span :: %{
          lemma: String.t(),
          commentary_char_start: non_neg_integer(),
          commentary_char_end: non_neg_integer(),
          root_char_start: non_neg_integer(),
          root_char_end: non_neg_integer()
        }

  # `optional(:written)` and every other key written out longhand. A map typespec's
  # shorthand `key: type` means REQUIRED and EXACT, and shorthand cannot be mixed with
  # `optional/1` — so declaring the seven measured keys in shorthand made
  # `%{written: n}` unmatchable, which is exactly what dialyzer said. `Pramana.Sources`
  # carries the same comment for the same reason; this is its second occurrence.
  #
  # `written` is present only after `align/3` has actually written rows: `measure/3` and a
  # skipped pair report the same numbers and wrote nothing, and the difference between
  # "nothing qualified" and "nothing was attempted" is worth keeping in the shape.
  @type report :: %{
          :commentary_work_id => String.t(),
          :root_work_id => String.t(),
          :spans => non_neg_integer(),
          :density => float(),
          :root_pct => float(),
          :forward_pct => float(),
          :aligned => boolean(),
          optional(:written) => non_neg_integer()
        }

  @doc "The scan window, in characters."
  @spec window() :: pos_integer()
  def window, do: @window

  @doc "The density floor a pair must clear before any alignment is recorded."
  @spec min_density() :: float()
  def min_density, do: @min_density

  @doc """
  Lemma spans shared by a commentary and its root, as character offsets into each body.

  Pure: takes two strings, touches no database. Returns spans in commentary order.
  """
  @spec spans(String.t(), String.t(), keyword()) :: [span()]
  def spans(commentary, root, opts \\ []) when is_binary(commentary) and is_binary(root) do
    n = Keyword.get(opts, :window, @window)
    {c_text, c_map} = without_breaks(commentary)
    %{map: r_map, positions: root_positions, chars: r_chars} = prepared_root(root, opts)

    c_text
    |> char_windows(n)
    |> Enum.flat_map(fn {w, positions} ->
      case Map.get(root_positions, w) do
        nil -> []
        root_pos -> Enum.map(positions, &{&1, root_pos})
      end
    end)
    |> Enum.sort()
    |> collapse()
    |> Enum.map(fn {c_start, r_start, len} ->
      chars = len + n - 1
      {c_from, c_to} = original_range(c_map, c_start, chars)
      {r_from, r_to} = original_range(r_map, r_start, chars)

      %{
        # NOT `String.slice/3`. It counts graphemes from the START of the binary, so on a
        # 358k-character root it costs 34 ms at offset 300,000 against 0.006 ms from the
        # tuple — and it runs once per span. `T1509` produces 21,834 spans, and this line
        # alone was 371 of that pair's 813 seconds. `Pramana.Segment.Taisho` records the
        # same lesson about `binary_part/3`; it had not reached here. Rule 41.
        lemma: lemma_at(r_chars, r_from, r_to),
        commentary_char_start: c_from,
        commentary_char_end: c_to,
        root_char_start: r_from,
        root_char_end: r_to
      }
    end)
  end

  # THE LINE BREAK IS TYPOGRAPHIC AND MUST NOT BE MATCHED ON.
  #
  # `texts.body` joins printed lines with newlines, so an 8-character window taken raw can
  # be two newlines and six characters — and a lemma that runs across a line break, which
  # most do, fragments into one span per line instead of being found whole. The first
  # version did exactly that and stored lemmas beginning "\n\n".
  #
  # So windows are taken over the text with whitespace removed, and offsets are mapped back
  # afterwards. This is the same rule the retrieval layer already follows for a different
  # reason: classical Chinese has no whitespace, so any whitespace in the body is ours and
  # never the edition's.
  #
  # Returns the stripped text and a tuple mapping each stripped index to its index in the
  # original.
  defp without_breaks(text) do
    {stripped, indices, _all} = split_breaks(text)
    {stripped, indices}
  end

  # The same walk, also handing back the ORIGINAL graphemes as a tuple so a lemma can be
  # cut from it by index. One pass rather than two, since the graphemes are built anyway.
  defp split_breaks(text) do
    all = String.graphemes(text)

    {chars, indices} =
      all
      |> Enum.with_index()
      |> Enum.reject(fn {c, _} -> String.trim(c) == "" end)
      |> Enum.unzip()

    {Enum.join(chars), List.to_tuple(indices), List.to_tuple(all)}
  end

  defp lemma_at(chars, from, to),
    do: Enum.map_join(from..(to - 1)//1, &elem(chars, &1))

  # A run of `count` stripped characters, as a range in the ORIGINAL text. The end is the
  # last matched character's original index plus one, so a lemma that spanned a line break
  # includes the break — the span is contiguous in the text a reader sees.
  defp original_range(map, start, count) do
    {elem(map, start), elem(map, start + count - 1) + 1}
  end

  @doc """
  The half of `spans/3` that depends only on the root, computed once and reused.

  **This exists because the same root is windowed many times in one run.** The alignment
  cost is linear in characters — one map insert per position, each building an
  8-character window — and on 2026-09-03 the 155 asserted pairs covered only 60 distinct
  roots: **41.7M root characters processed to window 11.0M distinct ones.** A caller that
  walks pairs root-major and carries this forward pays the smaller number.

  It is deliberately not a cache inside this module. A prepared root is a map with one
  entry per character — `T0279` 華嚴經 is 731k of them — so holding all 60 at once is not
  possible, and the only safe policy is the caller's: hold one, in an order that makes
  one enough. See `mix pramana.commentary.align`.
  """
  @spec prepare_root(String.t(), keyword()) :: prepared_root()
  def prepare_root(root, opts \\ []) when is_binary(root) do
    n = Keyword.get(opts, :window, @window)
    {r_text, r_map, r_chars} = split_breaks(root)

    %{
      body: root,
      map: r_map,
      chars: r_chars,
      positions: unique_windows(r_text, n),
      window: n
    }
  end

  @doc """
  `prepare_root/2` for a work already in the corpus, by id.

  The caller that needs this is walking pairs root-major and has an id, not a body; making
  it load the body itself would duplicate what `align/3` and `measure/3` already do.
  """
  @spec prepare_root_by_work(String.t(), keyword()) :: {:ok, prepared_root()} | {:error, term()}
  def prepare_root_by_work(root_work_id, opts \\ []) do
    with {:ok, root} <- body(root_work_id), do: {:ok, prepare_root(root, opts)}
  end

  @typedoc "A root's unique windows and offset map. Opaque; build it with `prepare_root/2`."
  @type prepared_root :: %{
          body: String.t(),
          map: tuple(),
          chars: tuple(),
          positions: %{String.t() => non_neg_integer()},
          window: pos_integer()
        }

  # A prepared root from `opts` when the caller has one for THIS root, otherwise computed.
  # The body check is not paranoia: passing a prepared form of a different text would
  # silently align against the wrong work, and nothing downstream could detect it.
  defp prepared_root(root, opts) do
    n = Keyword.get(opts, :window, @window)

    case Keyword.get(opts, :prepared_root) do
      %{body: ^root, window: ^n} = prepared -> prepared
      _ -> prepare_root(root, opts)
    end
  end

  @doc """
  Measure a pair without writing anything.

  `aligned` says whether the pair clears the density floor. Everything else is reported
  whether it does or not, because a number withheld is a number nobody can argue with.
  """
  @spec measure(String.t(), String.t(), keyword()) :: report() | {:error, :not_found}
  def measure(commentary_work_id, root_work_id, opts \\ []) do
    with {:ok, commentary} <- body(commentary_work_id),
         {:ok, root} <- body(root_work_id) do
      report(commentary_work_id, root_work_id, commentary, root, spans(commentary, root, opts))
    end
  end

  defp report(commentary_work_id, root_work_id, commentary, root, spans) do
    c_len = String.length(commentary)
    r_len = String.length(root)
    covered = covered_chars(spans)
    density = 10_000 * length(spans) / max(1, c_len)

    %{
      commentary_work_id: commentary_work_id,
      root_work_id: root_work_id,
      spans: length(spans),
      density: Float.round(density, 1),
      root_pct: Float.round(100 * covered / max(1, r_len), 1),
      forward_pct: forward_pct(spans),
      aligned: density >= @min_density
    }
  end

  # THE UNION OF THE SPANS, NOT THE SUM OF THEIR LENGTHS.
  #
  # Summing lengths double-counts wherever two spans overlap, and `root_pct` is published as
  # a percentage of the root — so it could exceed 100%, which is not a coverage figure at
  # all. On 2026-09-03 it did: **67 of 102 Tibetan pairs, to a maximum of 1102%**, and
  # **4 of 184 Chinese pairs, to 125%**. The Tibetan numbers are the method's premise
  # failing loudly (windows that are unique nowhere match everywhere, overlapping heavily);
  # the Chinese ones are the same arithmetic in a population where it hid.
  #
  # A number that can exceed its own denominator was never measuring what it said.
  @doc """
  Characters of the root these spans cover, counting an overlap once.

  Public because the question is the caller's as often as it is this module's, and because
  a private version of it is what let `root_pct` report 1102%.
  """
  @spec covered_chars([span()]) :: non_neg_integer()
  def covered_chars(spans) do
    spans
    |> Enum.map(&{&1.root_char_start, &1.root_char_end})
    |> Enum.sort()
    |> Enum.reduce({0, nil}, fn
      {from, to}, {total, nil} -> {total + to - from, to}
      {from, to}, {total, prev} when from >= prev -> {total + to - from, to}
      {_from, to}, {total, prev} when to > prev -> {total + to - prev, to}
      _, acc -> acc
    end)
    |> elem(0)
  end

  # How often consecutive lemmas move FORWARD through the root. A commentary walks its
  # text in order; incidental matches between unrelated works land in no order, which
  # shows up as ~50%. Reported rather than gated on, because it is evidence about the
  # pair and the density floor already separates cleanly.
  defp forward_pct(spans) do
    pairs =
      spans
      |> Enum.map(& &1.root_char_start)
      |> Enum.chunk_every(2, 1, :discard)

    case pairs do
      [] -> 0.0
      _ -> Float.round(100 * Enum.count(pairs, fn [a, b] -> b >= a end) / length(pairs), 1)
    end
  end

  defp body(work_id) do
    case Repo.one(from t in Text, where: t.work_id == ^work_id, select: t.body) do
      nil -> {:error, :not_found}
      body -> {:ok, body}
    end
  end

  # Every n-window of a text, with the positions it occurs at. NOT `windows/2`, which is
  # `Ecto.Query.windows/2` in a module that imports it — the collision is a compile error
  # rather than a subtle one, but the name would still read wrongly here.
  defp char_windows(text, n) do
    chars = text |> String.graphemes() |> List.to_tuple()
    last = tuple_size(chars) - n

    if last < 0 do
      %{}
    else
      Enum.reduce(0..last, %{}, fn i, acc ->
        Map.update(acc, window_at(chars, i, n), [i], &[i | &1])
      end)
    end
  end

  # Only the windows occurring EXACTLY ONCE, mapped to that one position. A window
  # occurring twice cannot say which of the two a commentary is quoting, and guessing
  # would be inventing an alignment.
  defp unique_windows(text, n) do
    text
    |> char_windows(n)
    |> Enum.reduce(%{}, fn
      {w, [only]}, acc -> Map.put(acc, w, only)
      _, acc -> acc
    end)
  end

  defp window_at(chars, i, n), do: Enum.map_join(i..(i + n - 1), &elem(chars, &1))

  # Maximal runs where both sides advance by one together: one continuous quotation, not
  # every overlapping window of it.
  defp collapse(anchors) do
    anchors
    |> Enum.reduce([], fn {c, r}, acc ->
      case acc do
        [{c0, r0, len} | rest] when c == c0 + len and r == r0 + len -> [{c0, r0, len + 1} | rest]
        _ -> [{c, r, 1} | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Commentary passages that gloss a root passage, most specific first.

  This is the reading question — *what explains this line* — so it is asked by root URN.
  Each result carries both ends and the method that produced it; nothing here is
  presented as the root text, which is the rule `Pramana.Relations` states and this
  inherits: a commentary explaining scripture is never citable as the scripture.
  """
  @spec glosses_on(String.t(), keyword()) :: [map()]
  def glosses_on(root_urn, opts \\ []) when is_binary(root_urn) do
    limit = Keyword.get(opts, :limit, 20)

    from(a in CommentaryAlignment,
      where: a.root_urn == ^root_urn,
      order_by: [desc: a.length],
      limit: ^limit,
      preload: [commentary_text: ^Text.preload_without_body()]
    )
    |> Repo.all()
    |> Enum.map(&present/1)
  end

  @doc """
  For each commentary explaining this work, how much of it is anchored line by line.

  **The evidence existed and did not reach the reader.** Six works are recorded as
  explaining `T0262`; two of them are aligned to it lemma by lemma and four are not, and
  `get_commentaries` could not say which. That is the difference between a list of names
  and a list a person can choose from.

  **Absence here is not a verdict, and the caller must be told so.** A pair below the
  density floor is not a refuted relation — a commentary may paraphrase its root, which
  this method cannot see at all — so a missing entry means *no verbatim quotation was
  found*, never *this is the weaker commentary*. Several of the most important commentaries
  in the corpus paraphrase.
  """
  @spec alignment_counts(String.t()) :: %{
          String.t() => %{lemmas: pos_integer(), lines: pos_integer()}
        }
  def alignment_counts(root_work_id) when is_binary(root_work_id) do
    from(a in CommentaryAlignment,
      where: a.root_work_id == ^root_work_id,
      group_by: a.commentary_work_id,
      select: {a.commentary_work_id, count(a.id), count(a.root_urn, :distinct)}
    )
    |> Repo.all()
    |> Map.new(fn {work, lemmas, lines} -> {work, %{lemmas: lemmas, lines: lines}} end)
  end

  @doc """
  How many commentary lemmas anchor to this root line, ignoring any limit.

  **`glosses_on/2` truncates and cannot say so from a list.** 27 root lines carry more
  than the default 20 — `T0279_012@p0058a11` carries 109 — and a caller handed twenty of
  them has no way to learn there are eighty-nine more. Publishing the gap rather than the
  total is this project's most-repeated lesson (rules 22, 44, 54) and the API surface was
  not honouring it.

  Ordering makes truncation defensible rather than arbitrary — longest lemma first, so a
  caller keeps the most substantial glosses — but defensible is not the same as disclosed.
  """
  @spec gloss_count(String.t()) :: non_neg_integer()
  def gloss_count(root_urn) when is_binary(root_urn) do
    Repo.aggregate(from(a in CommentaryAlignment, where: a.root_urn == ^root_urn), :count)
  end

  @doc """
  Where in its root a commentary does its work, by juan, with the totals.

  ## Why an outline rather than a list

  `lemmas_of/2` returns lemmas and `T1509` has 21,834 of them; a hundred of those answers
  nothing and all of them are not an answer either. The question behind *walk me through
  what this commentary explains* is **where its attention falls** — which parts of the root
  it works over and which it passes by — and that is a shape, not a list.

  So this groups by the root's own division. `segments.juan` is a first-class column, so
  no URN is split to get it (rule 68: a prefix test on a URN is a parser).

  ## A juan with no lemmas is absent, and that is a claim

  A juan the commentary never quotes does not appear. That is real information — 科文
  alignment sees verbatim quotation, so an absent juan means *this commentary quotes
  nothing from it*, which is usually because the commentary stops partway through its root
  and occasionally because it paraphrases that stretch. It never means the juan is missing
  from the corpus. Callers that would read a gap as an absence in the canon get the totals
  beside it to check against.
  """
  @spec outline(String.t()) :: %{
          commentary_work_id: String.t(),
          lemmas: non_neg_integer(),
          roots: [map()]
        }
  def outline(commentary_work_id) when is_binary(commentary_work_id) do
    # NOT `s.urn == a.root_urn`. A lemma that crosses a printed line break is anchored to a
    # RANGE — `...@p0321b24-p0321b25` — which equals no segment's URN, and **12,697 of
    # T1509's 21,834 alignments are ranges**: an equality join reported 9,137 and dropped
    # 58% in silence. Rule 68, in the form that bites hardest, because the dropped rows are
    # the ordinary case rather than an edge one; this module's own docs say most lemmas
    # cross a break.
    #
    # So the join is on the columns that cannot be ranges: the text, and the segment whose
    # character span contains the lemma's start.
    rows =
      from(a in CommentaryAlignment,
        join: s in Segment,
        on:
          s.text_id == a.root_text_id and s.char_start <= a.root_char_start and
            s.char_end > a.root_char_start,
        where: a.commentary_work_id == ^commentary_work_id,
        group_by: [a.root_work_id, s.juan],
        order_by: [asc: a.root_work_id, asc: s.juan],
        select: %{
          root_work_id: a.root_work_id,
          juan: s.juan,
          lemmas: count(a.id),
          lines: count(s.urn, :distinct)
        }
      )
      |> Repo.all()

    roots =
      rows
      |> Enum.group_by(& &1.root_work_id)
      |> Enum.map(fn {root, spread} ->
        %{
          root_work_id: root,
          lemmas: Enum.sum(Enum.map(spread, & &1.lemmas)),
          lines: Enum.sum(Enum.map(spread, & &1.lines)),
          juan: Enum.map(spread, &Map.take(&1, [:juan, :lemmas, :lines]))
        }
      end)
      |> Enum.sort_by(&(-&1.lemmas))

    %{
      commentary_work_id: commentary_work_id,
      lemmas: Enum.sum(Enum.map(roots, & &1.lemmas)),
      roots: roots
    }
  end

  @doc """
  Every lemma a commentary quotes, in the commentary's own order.

  > #### Use `outline/1` unless you want the lemmas themselves {: .tip}
  >
  > This truncates at 100 with no disclosure, which for `T1509`'s 21,834 alignments means
  > returning 0.5% of them and saying nothing. It had no caller at all until 2026-09-03,
  > and rather than routing it, `outline/1` answers the question behind it — *where does
  > this commentary do its work* — with complete counts, because a page of lemmas is not
  > what anyone wanted from a 21,834-lemma commentary.
  >
  > Kept for the case this really is the question: a short commentary, read in order.
  > **A caller that pages through it must publish the total** (`gloss_count/1` for the
  > per-line version), which is the condition `docs/PLAN.md` item 7 attached.
  """
  @spec lemmas_of(String.t(), keyword()) :: [map()]
  def lemmas_of(commentary_work_id, opts \\ []) when is_binary(commentary_work_id) do
    limit = Keyword.get(opts, :limit, 100)

    from(a in CommentaryAlignment,
      where: a.commentary_work_id == ^commentary_work_id,
      order_by: [asc: a.commentary_char_start],
      limit: ^limit,
      preload: [commentary_text: ^Text.preload_without_body()]
    )
    |> Repo.all()
    |> Enum.map(&present/1)
  end

  defp present(%CommentaryAlignment{} = a) do
    %{
      lemma: a.lemma,
      length: a.length,
      commentary_urn: a.commentary_urn,
      commentary_work_id: a.commentary_work_id,
      commentary_title: a.commentary_text && a.commentary_text.work.title,
      commentary_author: a.commentary_text && a.commentary_text.work.attributed_author,
      composition_origin: a.commentary_text && a.commentary_text.work.composition_origin,
      root_urn: a.root_urn,
      root_work_id: a.root_work_id,
      method: a.method,
      confidence: a.confidence
    }
  end

  @doc """
  Aligns one pair and writes the result, or explains why it wrote nothing.

  Replaces this pair's rows rather than appending, so re-running converges — the same
  discipline as `Corpus.Loader`.
  """
  @spec align(String.t(), String.t(), keyword()) ::
          {:ok, report()} | {:skip, report()} | {:error, term()}
  def align(commentary_work_id, root_work_id, opts \\ []) do
    with {:ok, commentary} <- text_row(commentary_work_id),
         {:ok, root} <- text_row(root_work_id),
         true <- commentary.id != root.id do
      found = spans(commentary.body, root.body, opts)
      report = report(commentary_work_id, root_work_id, commentary.body, root.body, found)

      if report.aligned do
        {:ok, persist(commentary, root, found, report, opts)}
      else
        {:skip, report}
      end
    else
      false -> {:error, :same_text}
      error -> error
    end
  end

  defp text_row(work_id) do
    case Repo.one(from t in Text, where: t.work_id == ^work_id, limit: 1) do
      nil -> {:error, {:not_found, work_id}}
      text -> {:ok, text}
    end
  end

  defp persist(commentary, root, found, report, opts) do
    bake_id = Keyword.get(opts, :bake_id)
    now = DateTime.utc_now()
    c_segments = segments(commentary.id)
    r_segments = segments(root.id)

    # The PAIR's numbers ride on every row of it. A caller holding one alignment can then
    # weigh it without a second query, which is the same shape as `semantic_confidence`
    # on a search hit: state the fact, let the caller decide what it is worth.
    pair = %{"density" => report.density, "forward_pct" => report.forward_pct}

    rows =
      found
      |> Enum.map(&row(&1, commentary, root, c_segments, r_segments, bake_id, now, pair))
      |> Enum.reject(&is_nil/1)

    Repo.transaction(fn ->
      Repo.delete_all(
        from a in CommentaryAlignment,
          where:
            a.commentary_text_id == ^commentary.id and a.root_text_id == ^root.id and
              a.method == "lemma_match"
      )

      # Chunked because a rich pair produces thousands of rows and Postgres caps a
      # statement's parameters.
      Enum.each(Enum.chunk_every(rows, 500), &Repo.insert_all(CommentaryAlignment, &1))
    end)

    Map.put(report, :written, length(rows))
  end

  defp row(span, commentary, root, c_segments, r_segments, bake_id, now, pair) do
    with c_urn when is_binary(c_urn) <-
           range_urn(c_segments, span.commentary_char_start, span.commentary_char_end),
         r_urn when is_binary(r_urn) <-
           range_urn(r_segments, span.root_char_start, span.root_char_end) do
      %{
        lemma: span.lemma,
        lemma_sha256: :crypto.hash(:sha256, span.lemma) |> Base.encode16(case: :lower),
        length: String.length(span.lemma),
        commentary_text_id: commentary.id,
        commentary_work_id: commentary.work_id,
        commentary_urn: c_urn,
        commentary_char_start: span.commentary_char_start,
        commentary_char_end: span.commentary_char_end,
        root_text_id: root.id,
        root_work_id: root.work_id,
        root_urn: r_urn,
        root_char_start: span.root_char_start,
        root_char_end: span.root_char_end,
        method: "lemma_match",
        # Never `certain`. The lemma is certain; that this commentary is glossing THIS
        # occurrence rather than quoting the phrase in passing is an inference, and a
        # commentary can quote its root without commenting on the line it took it from.
        confidence: "probable",
        bake_id: bake_id,
        meta: pair,
        inserted_at: now,
        updated_at: now
      }
    else
      _ -> nil
    end
  end

  defp segments(text_id) do
    Repo.all(
      from s in Segment,
        where: s.text_id == ^text_id,
        order_by: s.char_start,
        select: %{urn: s.urn, char_start: s.char_start, char_end: s.char_end}
    )
  end

  # A lemma crossing a printed line break — most do, the break being typographic — becomes
  # a range URN, exactly as a chunk or a quotation does.
  defp range_urn(segments, start, finish) do
    case Enum.filter(segments, &(&1.char_start < finish and &1.char_end > start)) do
      [] -> nil
      [one] -> one.urn
      many -> URN.range(List.first(many).urn, List.last(many).urn)
    end
  end
end
