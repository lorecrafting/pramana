defmodule Pramana.Relations do
  @moduledoc """
  Typed relations between works: which text a commentary actually explains.

  `text_role` says a work *is* a commentary. This says *what of*. Without it the corpus
  can answer "show me Chinese commentary" but not "show me commentary on the Lotus
  Sūtra", and the second is the question people have. See `docs/COMMENTARY.md`.

  ## A commentary explains scripture and is not scripture

  This is the same principle as invariant #7 for generated translations: helpful,
  attributable, **never citable as the root text**. Relations exist precisely so that
  distinction survives into an answer instead of being flattened — pulling a commentary
  in because it explains a sūtra must not let it be quoted *as* the sūtra.

  ## Method and confidence are claims, not decoration

  A catalogue assertion, a source manifest, a deterministic lemma match and an LLM
  inference are four different kinds of claim. `CLAUDE.md` invariant #5 requires the
  difference to reach the answer, so every query here returns them and never averages
  them away.

  ## Relations chain

  A subcommentary explains a commentary which explains a sūtra. `resolve_root/2` walks
  that chain and returns the whole path, so a modern explanation can be traced back to
  root scripture **showing the intermediate layers** rather than collapsing them.
  """

  import Ecto.Query

  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Repo

  @relations ~w(comments_on subcommentary_of translates conflates abridges quotes parallel_of)
  @methods ~w(catalogue manifest title_match lemma_match shared_text llm)
  @confidences ~w(certain probable asserted uncertain)

  # Chain-following relations. `quotes` and `parallel_of` are deliberately excluded:
  # quoting a sūtra does not make a work a commentary on it, and a parallel is a sibling
  # rather than a parent. Including them would let `resolve_root/2` wander sideways and
  # report a root the text never claimed to explain.
  @upward ~w(comments_on subcommentary_of translates conflates abridges)

  @max_depth 10

  # What a work of each role may be found to explain. Read off `Pramana.Taisho.Divisions`
  # rather than assumed — see `may_explain/1`.
  @explains %{
    "commentary" => ~w(root),
    "subcommentary" => ~w(treatise commentary root),
    "treatise" => ~w(root)
  }

  @doc """
  The `text_role`s a work of this role may be found to explain.

  **This was one global `["root"]` in two separate linkers until 2026-09-02**, which is a
  claim about the literature — *only scripture is commented on* — and the Taishō's own
  division table contradicts it:

      1816-1850  論疏部  Śāstra exegesis  ->  subcommentary
      1536-1563  毘曇部  Abhidharma       ->  treatise
      1564-1578  中觀部  Madhyamaka       ->  treatise
      1579-1627  瑜伽部  Yogācāra         ->  treatise

  **論疏部 is a whole Taishō division whose purpose is commenting on 論**, and every 論
  division is `text_role: treatise`. So every subcommentary in the corpus was unlinkable by
  construction, and `T1830` 成唯識論述記 — whose title contains 成唯識論 literally — was found
  by nothing. Worse, `Pramana.Quotations.Roots` did not abstain for them: with the right
  answer filtered out, the runner-up looks like the answer, and it proposed the
  Mahāprajñāpāramitā at `confidence: probable`. Rule 75.

  It lives here rather than in either caller because both need the same answer and a
  second copy is how the first one went stale. A role with no entry explains nothing, which
  is why `history`, `catalogue` and `apocryphon` are absent: they are not exegesis.
  """
  @spec may_explain(String.t() | nil) :: [String.t()]
  def may_explain(role), do: Map.get(@explains, role, [])

  @doc "The roles that may explain something at all — the sources of a `comments_on`."
  @spec explanatory_roles() :: [String.t()]
  def explanatory_roles, do: @explains |> Map.keys() |> Enum.sort()

  @doc "Known relation names, for validating input before it reaches the database."
  @spec relations() :: [String.t()]
  def relations, do: @relations

  @doc """
  Known assertion methods, weakest (`llm`) to strongest (`catalogue`).

  `title_match` sits between `manifest` and `lemma_match`: deterministic, but an
  inference from a string rather than an editorial judgement.

  `shared_text` is weaker than both and is the only one that infers the relation from
  evidence that does not mention it — a commentary's dominant shared-text partner among
  root-role works (`Pramana.Quotations.Roots`). It is deliberately not filed under
  `lemma_match`, which names what `commentary_alignments` does *given* a relation already
  asserted; naming the inference after the procedure that presupposes it would make one
  value mean two things.
  """
  @spec methods() :: [String.t()]
  def methods, do: @methods

  @doc """
  Records a relation.

  Idempotent per `(source, target, relation, method)`: re-running an ingest converges
  rather than duplicating, while the *same* relation asserted by two different methods is
  kept as two rows, because corroboration is information.
  """
  @spec assert(map()) :: {:ok, WorkRelation.t()} | {:error, term()}
  def assert(attrs) do
    attrs =
      attrs
      |> Map.put_new(:scope, "whole_work")
      |> Map.put_new(:confidence, "asserted")
      |> Map.put_new(:evidence, %{})

    with :ok <- validate(attrs) do
      %WorkRelation{}
      |> WorkRelation.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:confidence, :scope, :target_urn, :evidence, :updated_at]},
        conflict_target:
          {:unsafe_fragment,
           ~s|(source_work_id, target_work_id, target_work_ref, relation, method)|}
      )
    end
  end

  defp validate(attrs) do
    cond do
      attrs[:relation] not in @relations ->
        {:error, {:unknown_relation, attrs[:relation]}}

      attrs[:method] not in @methods ->
        {:error, {:unknown_method, attrs[:method]}}

      attrs[:confidence] not in @confidences ->
        {:error, {:unknown_confidence, attrs[:confidence]}}

      true ->
        :ok
    end
  end

  @doc """
  What explains this work.

  Returns the commentaries, subcommentaries and treatises pointing AT `work_id`, each
  with the provenance of the work itself and of the assertion. Grouped by the caller —
  `docs/COMMENTARY.md` asks for origin/role/period grouping so a 7th-century gloss is
  never mistaken for a 1990s one, and that grouping belongs where the answer is shaped.
  """
  @spec commentaries_on(String.t(), keyword()) :: [map()]
  def commentaries_on(work_id, opts \\ []) do
    relations = Keyword.get(opts, :relations, @upward)

    from(r in WorkRelation,
      join: w in Work,
      on: w.id == r.source_work_id,
      where: r.target_work_id == ^work_id and r.relation in ^relations,
      order_by: [asc: w.date_start, asc: w.id],
      select: %{
        work_id: w.id,
        title: w.title,
        composition_origin: w.composition_origin,
        text_role: w.text_role,
        attributed_author: w.attributed_author,
        date_start: w.date_start,
        date_end: w.date_end,
        relation: r.relation,
        scope: r.scope,
        target_urn: r.target_urn,
        confidence: r.confidence,
        method: r.method,
        evidence: r.evidence
      }
    )
    |> Repo.all()
  end

  @doc """
  What this work explains — one step up the chain.
  """
  @spec explains(String.t()) :: [map()]
  def explains(work_id) do
    from(r in WorkRelation,
      left_join: w in Work,
      on: w.id == r.target_work_id,
      where: r.source_work_id == ^work_id,
      select: %{
        work_id: r.target_work_id,
        # A target outside the corpus keeps its manifest reference rather than vanishing.
        work_ref: r.target_work_ref,
        title: w.title,
        composition_origin: w.composition_origin,
        text_role: w.text_role,
        relation: r.relation,
        confidence: r.confidence,
        method: r.method
      }
    )
    |> Repo.all()
  end

  @doc """
  Works asserted to transmit the same material as this one.

  These are **siblings, not versions of one another**, and the distinction is load-bearing.
  A pair here may be a genuine 異譯本 — T0099 雜阿含經 and T0100 別譯雜阿含經, whose name
  says it is a separate translation, share 706 curated passages — or it may be two
  different collections that transmit related discourses, like T0099 and T0125
  (Saṃyukta and Ekottarika Āgama), where neither translates the other. **The parallel data
  cannot tell them apart**, so nothing here claims it does; `evidence` carries the passage
  counts a reader needs to judge, and `confidence` grades them.

  Ordered by confidence then by weight of evidence, so the strongest pair for a work comes
  first rather than whichever row the planner returned.
  """
  @spec parallels_of(String.t()) :: [map()]
  def parallels_of(work_id) do
    from(r in WorkRelation,
      left_join: w in Work,
      on: w.id == r.target_work_id,
      where: r.source_work_id == ^work_id and r.relation == "parallel_of",
      order_by: [
        asc:
          fragment(
            "array_position(ARRAY['certain','probable','asserted','uncertain'], ?)",
            r.confidence
          ),
        desc: fragment("COALESCE((? -> 'full_parallels')::int, 0)", r.evidence)
      ],
      select: %{
        work_id: r.target_work_id,
        work_ref: r.target_work_ref,
        title: w.title,
        composition_origin: w.composition_origin,
        text_role: w.text_role,
        attributed_author: w.attributed_author,
        relation: r.relation,
        confidence: r.confidence,
        method: r.method,
        evidence: r.evidence
      }
    )
    |> Repo.all()
  end

  @doc """
  Walks the chain from a commentary back toward root scripture.

  Returns the **path**, not just the destination: a subcommentary on a commentary on a
  sūtra yields all three, so a reader sees the intermediate layers rather than a claim
  that the subcommentary explains the sūtra directly.

  Cycles are possible in real catalogue data (two works each said to comment on the
  other), so the walk tracks visited ids and stops. Depth is capped at #{@max_depth};
  a chain longer than that is a data problem, not a text.
  """
  @spec resolve_root(String.t()) :: [map()]
  def resolve_root(work_id), do: walk(work_id, MapSet.new([work_id]), [], 0)

  defp walk(_work_id, _seen, path, depth) when depth >= @max_depth, do: Enum.reverse(path)

  defp walk(work_id, seen, path, depth) do
    case Enum.find(explains(work_id), &chain_step?(&1, seen)) do
      nil ->
        Enum.reverse(path)

      step ->
        next = step.work_id
        walk(next, MapSet.put(seen, next), [step | path], depth + 1)
    end
  end

  defp chain_step?(%{relation: relation, work_id: target}, seen) do
    relation in @upward and not is_nil(target) and not MapSet.member?(seen, target)
  end

  @doc """
  Whether a work is scripture in its own right, or explains something else.

  Used to keep a commentary from being presented as the text it comments on when
  relations pull it into an answer.
  """
  @spec explanatory?(String.t()) :: boolean()
  def explanatory?(work_id) do
    Repo.exists?(
      from r in WorkRelation,
        where: r.source_work_id == ^work_id and r.relation in ^@upward
    )
  end

  @doc "Every relation in the corpus, counted by relation and method. For the inventory."
  @spec stats() :: [map()]
  def stats do
    from(r in WorkRelation,
      group_by: [r.relation, r.method],
      select: %{relation: r.relation, method: r.method, count: count(r.id)},
      order_by: [desc: count(r.id)]
    )
    |> Repo.all()
  end
end
