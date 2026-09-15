defmodule Pramana.Coherence do
  @moduledoc """
  Do independently derived facts about the same work agree?

  The gate has two data checks and they answer different questions. `verify` re-runs the
  pipeline and byte-compares: **determinism**. `integrity` counts against the source files:
  **fidelity**. Both were green over 122 works labelled `composition_origin: japanese` that
  are Ming and Qing Chinese compositions, and correctly so — those works were faithfully and
  reproducibly *mislabelled*. Neither check can see a rule applied outside its domain.

  This is the third question: **agreement**. Two facts about one work, derived from different
  sources, compared.

      verify      same inputs, same output          the pipeline is not reproducible
      integrity   nothing printed was lost          content was dropped
      coherence   independent facts concur          a rule is applied outside its domain

  ## Every check is a rate with a floor, never a rule

  Upstream data legitimately disagrees with itself. DILA files a Yuan-era warlord under 明
  because that is the era he belongs to; Korean monks composed in literary Chinese while
  living in China. A check demanding 100% goes permanently red, and a permanently red check
  is one nobody reads — which is how `integrity` lost its audience crying wolf over 1,228 X
  texts.

  So each check reports `agreed / total`, a floor taken from the measured distribution, and
  the disagreements themselves. **A disagreement is a question for a person, never an
  instruction to a script.**

  ## And a minimum population, because a rate over five rows is not evidence

  `@min_population` guards every judgement. Before the A4 fix the birthplace check saw
  45 Japanese-origin works of which 44 had China-born authors and would have failed loudly;
  after it, the same check sees two and says so rather than passing or failing on noise.
  Reporting "too few to judge" is the same discipline that killed the byline-verb extension.

  ## What this is not

  Not a correctness proof — two independently wrong sources agree happily. And not a
  substitute for someone reading the data: every check here was *proposed* by noticing
  something odd, and no suite proposes its own checks.
  """

  import Ecto.Query

  alias Pramana.Cbeta.Byline
  alias Pramana.Corpus.Work
  alias Pramana.Repo

  @typedoc "One check's outcome. `:undecided` is a real result, not a soft pass."
  @type result :: %{
          id: String.t(),
          question: String.t(),
          agreed: non_neg_integer(),
          total: non_neg_integer(),
          rate: float() | nil,
          floor: float(),
          status: :ok | :failed | :undecided,
          detail: [String.t()]
        }

  # Below this a rate is noise. Chosen so the A4 defect (45 works) is judged and its
  # post-fix residue (2 works) is not.
  @min_population 20

  @doc """
  Runs every check and returns their results, in declaration order.

  Nothing here writes. A coherence failure is a signal to look, and the looking is a
  person's job.
  """
  @spec run() :: [result()]
  def run do
    [dynasty_lifespan(), birthplace_origin(), byline_division(), commentary_after_root()]
  end

  @doc """
  DILA's dynasty label against DILA's own dates — two fields, recorded separately.

  Measured 2026-08-28: **4,354 of 4,401 (98.9%)** within a 20-year boundary tolerance. The
  residual is upstream labelling rather than a parse error — 張士誠 (1321–1367) is filed
  under 明 because that is the era he belongs to, and 楊英風 (1926–1997) under 清. The floor
  is 0.97, which leaves room for that without leaving room for a systematic date-parsing
  break.

  The tolerance exists because people live across dynastic boundaries. Without it this
  check would report a failure every time somebody was born under one house and died under
  the next, which is not a defect in anything.
  """
  @spec dynasty_lifespan() :: result()
  def dynasty_lifespan do
    {agreed, total, examples} =
      Repo.all(
        from p in "authority_people",
          where:
            not is_nil(p.dynasty) and (not is_nil(p.birth_earliest) or not is_nil(p.death_latest)),
          select: %{
            name: p.name,
            dynasty: p.dynasty,
            born: fragment("extract(year from ?)::int", p.birth_earliest),
            died: fragment("extract(year from ?)::int", p.death_latest)
          }
      )
      |> Enum.reduce({0, 0, []}, &tally_dynasty/2)

    verdict(
      "dynasty_lifespan",
      "does a person's recorded dynasty contain their recorded dates?",
      agreed,
      total,
      0.97,
      Enum.take(examples, 5)
    )
  end

  # Only the houses whose spans are unambiguous. A dynasty this table does not name is
  # skipped rather than guessed at, because inventing a span would manufacture disagreement.
  @dynasties %{
    "東晉" => {317, 420},
    "後秦" => {384, 417},
    "隋" => {581, 618},
    "唐" => {618, 907},
    "北宋" => {960, 1127},
    "南宋" => {1127, 1279},
    "元" => {1271, 1368},
    "明" => {1368, 1644},
    "清" => {1636, 1912}
  }
  @boundary_tolerance 20

  defp dynasty_span(dynasty), do: Map.get(@dynasties, dynasty)

  # A dynasty this table does not name contributes to neither side. Skipping is not a pass:
  # it keeps the denominator honest, which is what `total` means everywhere in this module.
  defp tally_dynasty(person, {ok, n, examples}) do
    case dynasty_span(person.dynasty) do
      nil -> {ok, n, examples}
      {lo, hi} -> score_dynasty(person, lo, hi, {ok, n, examples})
    end
  end

  defp score_dynasty(person, lo, hi, {ok, n, examples}) do
    if plausible?(person, lo, hi),
      do: {ok + 1, n + 1, examples},
      else: {ok, n + 1, [describe(person) | examples]}
  end

  defp plausible?(%{born: born, died: died}, lo, hi) do
    within = fn
      nil -> false
      year -> year >= lo - @boundary_tolerance and year <= hi + @boundary_tolerance
    end

    within.(born) or within.(died)
  end

  defp describe(p), do: "#{p.name} (#{p.dynasty}) #{p.born || "?"}–#{p.died || "?"}"

  @doc """
  A locally composed work should originate where its author was born.

  **This is the check that found § A4.** `composition_origin` says where a work was
  *composed*; for a work that was composed rather than translated, that is where its author
  was. Translations are excluded outright — a Chinese monk rendering an Indian sūtra produces
  an `indic` work, and that is the multi-axis provenance working, not a disagreement.

  Judged per origin against the modal birthplace, not per work, because the exceptions are
  real: **25 `chinese` works have Korean-born authors**, and Korean monks composing in
  literary Chinese while living in China is ordinary history rather than a defect. A rule
  demanding equality would fire on all of them.

  Before the fix this saw 45 Japanese-origin works, 44 of them by China-born authors, and
  would have failed at a glance. After it, two — reported and not judged.
  """
  # Only origins that name a place of composition. `indic` is deliberately absent: it marks a
  # translated work and says nothing about where the translator was born.
  @origin_birthplace %{"chinese" => "中國", "japanese" => "日本", "korean" => "南韓"}

  @spec birthplace_origin() :: result()
  def birthplace_origin do
    rows =
      Repo.all(
        from w in Work,
          join: p in "authority_people",
          on: p.id == w.authority_id,
          join: pl in "authority_places",
          on: pl.id == p.place_id,
          where:
            w.composition_origin in ^Map.keys(@origin_birthplace) and not is_nil(pl.district),
          select: %{origin: w.composition_origin, district: pl.district, work: w.id}
      )

    by_origin = Enum.group_by(rows, & &1.origin)

    {agreed, total, detail} =
      Enum.reduce(by_origin, {0, 0, []}, fn {origin, group}, {ok, n, detail} ->
        expected = Map.fetch!(@origin_birthplace, origin)
        matching = Enum.count(group, &(country_of(&1.district) == expected))
        line = "#{origin}: #{matching}/#{length(group)} born in #{expected}"

        if length(group) < @min_population do
          {ok, n, ["#{line} — too few to judge" | detail]}
        else
          {ok + matching, n + length(group), [line | detail]}
        end
      end)

    verdict(
      "birthplace_origin",
      "is a locally composed work's origin where its author was born?",
      agreed,
      total,
      0.85,
      Enum.reverse(detail)
    )
  end

  defp country_of(district), do: district |> String.split("-") |> List.first()

  @doc """
  The byline rule against the Taishō's own 部 division table.

  `Pramana.Taisho.Divisions` states that the byline rule "agrees with this table 97.3% of the
  time on the Taishō" — **a number written into a comment that nothing re-checked**, which is
  the doc failure this project has now corrected four times. This recomputes it.

  Only Taishō works, and only where both sources speak: the division table is
  work-number-precise and the byline is a per-work inference, so this is the one place they
  can be compared at all.
  """
  @spec byline_division() :: result()
  def byline_division do
    {agreed, total, examples} =
      Repo.all(
        from w in Work,
          join: t in "texts",
          on: t.work_id == w.id,
          where:
            t.witness_id == "T" and not is_nil(w.composition_origin) and
              not is_nil(w.attributed_author),
          distinct: w.id,
          select: %{id: w.id, author: w.attributed_author, origin: w.composition_origin}
      )
      |> Enum.reduce({0, 0, []}, fn work, {ok, n, ex} ->
        case Byline.provenance(work.author)[:composition_origin] do
          nil ->
            {ok, n, ex}

          same when same == work.origin ->
            {ok + 1, n + 1, ex}

          other ->
            {ok, n + 1,
             ["#{work.id} #{work.author}: table says #{work.origin}, byline #{other}" | ex]}
        end
      end)

    verdict(
      "byline_division",
      "does the byline rule agree with the Taishō 部 table where both speak?",
      agreed,
      total,
      0.95,
      Enum.take(examples, 5)
    )
  end

  @doc """
  A commentary cannot predate the work it explains.

  Newly checkable, because dates arrived with the authority link. A violation is either a bad
  alignment or a bad date, and both are worth knowing — which is why this reports rather than
  resolves.

  Compared on the **latest possible** commentary date against the **earliest possible** root
  date, because both are lifespan bounds rather than dates. Anything tighter would
  manufacture failures out of the width of the bound.
  """
  @spec commentary_after_root() :: result()
  def commentary_after_root do
    {agreed, total, examples} =
      Repo.all(
        from a in "commentary_alignments",
          join: c in Work,
          on: c.id == a.commentary_work_id,
          join: r in Work,
          on: r.id == a.root_work_id,
          where: not is_nil(c.date_end) and not is_nil(r.date_start),
          distinct: [a.commentary_work_id, a.root_work_id],
          select: %{
            commentary: a.commentary_work_id,
            root: a.root_work_id,
            c_end: c.date_end,
            r_start: r.date_start
          }
      )
      |> Enum.reduce({0, 0, []}, fn pair, {ok, n, ex} ->
        if pair.c_end >= pair.r_start,
          do: {ok + 1, n + 1, ex},
          else:
            {ok, n + 1,
             ["#{pair.commentary} (≤#{pair.c_end}) explains #{pair.root} (≥#{pair.r_start})" | ex]}
      end)

    verdict(
      "commentary_after_root",
      "does a commentary postdate the work it explains?",
      agreed,
      total,
      0.95,
      Enum.take(examples, 5)
    )
  end

  # `:undecided` rather than `:ok` when the population is too small. A check that passes for
  # want of data is a check that reports success it has not earned.
  defp verdict(id, question, agreed, total, floor, detail) do
    {rate, status} =
      cond do
        total < @min_population -> {nil, :undecided}
        agreed / total >= floor -> {agreed / total, :ok}
        true -> {agreed / total, :failed}
      end

    %{
      id: id,
      question: question,
      agreed: agreed,
      total: total,
      rate: rate,
      floor: floor,
      status: status,
      detail: detail
    }
  end
end
