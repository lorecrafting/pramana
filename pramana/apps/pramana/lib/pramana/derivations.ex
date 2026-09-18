defmodule Pramana.Derivations do
  @moduledoc """
  Durable run receipts for deterministic derived-data commands.

  A receipt proves that one implementation enumerated its declared input scope, reached
  the end of the write path, and observed a specific derived output state. It does not
  prove that the scholarly claim encoded by a relation is correct.

  Receipts are deliberately separate from source/release identity. Quotations,
  work-relations and commentary alignments are mutable derived tables whose completion
  previously existed only in terminal output.
  """

  import Ecto.Query

  alias Pramana.Commentary
  alias Pramana.Corpus.CommentaryAlignment
  alias Pramana.Corpus.DerivationRun
  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Quotations.Roots
  alias Pramana.Relations
  alias Pramana.Repo

  @kinds ~w(
    quotations_scan
    relations_title
    relations_shared_text
    commentary_align
  )

  @versions %{
    "quotations_scan" => "quotations_scan/v1",
    "relations_title" => "relations_title/v1",
    "relations_shared_text" => "relations_shared_text/v1",
    "commentary_align" => "commentary_align/v1"
  }

  @alignable_sources ~w(cbeta sat local-huang-nianzu-jie derge derge-tengyur)
  @alignable_relations ~w(comments_on subcommentary_of)

  @type token :: %{
          derivation: String.t(),
          source_bake_id: String.t() | nil,
          implementation_version: String.t(),
          scope: map(),
          parameters: map(),
          input_digest: String.t(),
          started_at: DateTime.t()
        }

  @doc "Known derivation receipt kinds."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "Current implementation/rule version for one derivation kind."
  @spec version(String.t()) :: String.t()
  def version(kind), do: Map.fetch!(@versions, kind)

  @doc """
  Captures the input identity immediately before a derivation begins.

  The command should retain this token until its write path finishes and call
  `finish_run!/2`. If the input digest changes in between, the receipt is recorded as
  partial rather than clean.
  """
  @spec begin_run(String.t(), String.t() | nil, map(), map()) :: token()
  def begin_run(kind, source_bake_id, scope, parameters) when kind in @kinds do
    scope = stringify_keys(scope)
    parameters = stringify_keys(parameters)

    %{
      derivation: kind,
      source_bake_id: source_bake_id,
      implementation_version: version(kind),
      scope: scope,
      parameters: parameters,
      input_digest: current_input_digest(kind, source_bake_id, scope, parameters),
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Records the immutable receipt after a derivation write path finishes.

  `stats["failures"]` is the command's explicit per-item failure count. A run is
  `complete` only when that count is zero and its input digest stayed stable.
  """
  @spec finish_run!(token(), map()) :: DerivationRun.t()
  def finish_run!(token, stats) do
    stats = stringify_keys(stats)
    post_input = current_input_digest(token)
    {output_digest, output_count} = current_output_snapshot(token)
    failures = integer_stat(stats, "failures")

    status =
      if post_input == token.input_digest and failures == 0,
        do: "complete",
        else: "partial"

    attrs = %{
      derivation: token.derivation,
      status: status,
      source_bake_id: token.source_bake_id,
      implementation_version: token.implementation_version,
      scope: token.scope,
      parameters: token.parameters,
      input_digest: token.input_digest,
      output_digest: output_digest,
      stats:
        Map.merge(stats, %{
          "input_changed_during_run" => post_input != token.input_digest,
          "post_input_digest" => post_input,
          "output_count" => output_count
        }),
      started_at: token.started_at,
      completed_at: DateTime.utc_now()
    }

    %DerivationRun{}
    |> DerivationRun.changeset(attrs)
    |> Repo.insert!()
  end

  @doc "Stable SHA-256 for receipt inputs/outputs."
  @spec digest(term()) :: String.t()
  def digest(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Recomputes the current input digest represented by a receipt/token."
  @spec current_input_digest(DerivationRun.t() | token()) :: String.t()
  def current_input_digest(run) do
    current_input_digest(
      run.derivation,
      run.source_bake_id,
      run.scope,
      run.parameters
    )
  end

  @doc "Recomputes the current derived-output digest represented by a receipt/token."
  @spec current_output_snapshot(DerivationRun.t() | token()) :: {String.t(), non_neg_integer()}
  def current_output_snapshot(run) do
    current_output_snapshot(
      run.derivation,
      run.source_bake_id,
      run.scope,
      run.parameters
    )
  end

  @doc "True only when a receipt still matches the current implementation, input and output."
  @spec current?(DerivationRun.t()) :: boolean()
  def current?(%DerivationRun{} = run) do
    {output_digest, _count} = current_output_snapshot(run)

    run.implementation_version == version(run.derivation) and
      run.input_digest == current_input_digest(run) and
      run.output_digest == output_digest
  end

  @doc "All receipts for one bake and derivation, newest first."
  @spec for_bake(String.t(), String.t()) :: [DerivationRun.t()]
  def for_bake(source_bake_id, derivation) do
    Repo.all(
      from r in DerivationRun,
        where: r.source_bake_id == ^source_bake_id and r.derivation == ^derivation,
        order_by: [desc: r.completed_at, desc: r.id]
    )
  end

  @doc false
  def current_input_digest("quotations_scan", bake_id, scope, parameters) do
    digest(%{
      bake_id: bake_id,
      scope: scope,
      parameters: parameters,
      texts: quotation_text_facts(scope)
    })
  end

  def current_input_digest("relations_title", bake_id, scope, parameters) do
    digest(%{
      bake_id: bake_id,
      scope: scope,
      parameters: parameters,
      works: relation_title_work_facts()
    })
  end

  def current_input_digest("relations_shared_text", bake_id, scope, parameters) do
    min_passages = integer_parameter(parameters, "min_passages", 1)

    digest(%{
      bake_id: bake_id,
      scope: scope,
      parameters: parameters,
      candidates: shared_text_candidates(min_passages)
    })
  end

  def current_input_digest("commentary_align", bake_id, scope, parameters) do
    digest(%{
      bake_id: bake_id,
      scope: scope,
      parameters: parameters,
      pairs: commentary_pair_facts(scope)
    })
  end

  @doc false
  def current_output_snapshot("quotations_scan", bake_id, scope, parameters) do
    min_length = integer_parameter(parameters, "min_length", 20)
    rows = quotation_output_rows(bake_id, scope, min_length)
    {digest(rows), length(rows)}
  end

  def current_output_snapshot("relations_title", _bake_id, _scope, _parameters) do
    rows = relation_output_rows("title_match")
    {digest(rows), length(rows)}
  end

  def current_output_snapshot("relations_shared_text", _bake_id, _scope, _parameters) do
    rows = relation_output_rows("shared_text")
    {digest(rows), length(rows)}
  end

  def current_output_snapshot("commentary_align", bake_id, scope, _parameters) do
    rows = alignment_output_rows(bake_id, scope)
    {digest(rows), length(rows)}
  end

  @doc """
  The exact relation/text pairs the alignment command enumerates, with text identities.

  This is public so the task and the receipt verifier share one definition of alignment
  coverage rather than maintaining parallel SQL.
  """
  @spec commentary_pairs(String.t() | nil) :: [{String.t(), String.t(), String.t()}]
  def commentary_pairs(work_id) do
    commentary_pair_query(work_id)
    |> select([r, cs, _rt], {r.source_work_id, r.target_work_id, cs.source_id})
    |> Repo.all()
  end

  defp quotation_text_facts(scope) do
    scope
    |> quotation_text_query()
    |> select([t, w], %{
      id: t.id,
      work_id: t.work_id,
      source_id: t.source_id,
      witness_id: t.witness_id,
      body_sha256: t.body_sha256,
      char_count: t.char_count,
      division: w.division
    })
    |> order_by([t, _w], asc: t.id)
    |> Repo.all()
  end

  defp quotation_text_query(scope) do
    from(t in Text,
      join: w in Work,
      on: w.id == t.work_id,
      where: not is_nil(t.body) and t.body != ""
    )
    |> maybe_where(:source, scope["source"])
    |> maybe_where(:work, scope["work"])
    |> maybe_division(scope["division"])
  end

  defp maybe_where(query, _field, nil), do: query

  defp maybe_where(query, :source, source),
    do: where(query, [t, _w], t.source_id == ^source)

  defp maybe_where(query, :work, work),
    do: where(query, [t, _w], t.work_id == ^work)

  defp maybe_division(query, nil), do: query
  defp maybe_division(query, division), do: where(query, [_t, w], w.division == ^division)

  defp relation_title_work_facts do
    roles =
      Relations.explanatory_roles()
      |> Enum.flat_map(&[&1 | Relations.may_explain(&1)])
      |> Enum.uniq()

    Repo.all(
      from w in Work,
        where: w.text_role in ^roles and not is_nil(w.title),
        order_by: w.id,
        select: %{id: w.id, title: w.title, text_role: w.text_role}
    )
  end

  defp shared_text_candidates(min_passages) do
    Roots.candidates(min_passages: min_passages)
    |> Enum.map(fn candidate ->
      %{
        work_id: candidate.work_id,
        title: candidate.title,
        text_role: candidate.text_role,
        target_work_id: candidate.target_work_id,
        target_title: candidate.target_title,
        family: candidate.family,
        family_members:
          candidate.family_members
          |> Enum.map(&%{work_id: &1.work_id, passages: &1.passages})
          |> Enum.sort_by(& &1.work_id),
        passages: candidate.passages,
        runner_up: candidate.runner_up,
        families: candidate.families,
        tied: candidate.tied,
        band: Atom.to_string(candidate.band)
      }
    end)
  end

  defp commentary_pair_facts(scope) do
    commentary_pair_fact_query(scope["work"])
    |> Repo.all()
  end

  defp commentary_pair_query(work_id) do
    from(r in WorkRelation,
      join: cs in Text,
      on: cs.work_id == r.source_work_id,
      join: rt in Text,
      on: rt.work_id == r.target_work_id,
      where:
        r.relation in ^@alignable_relations and not is_nil(r.target_work_id) and
          cs.source_id in ^@alignable_sources and rt.source_id in ^@alignable_sources,
      distinct: true,
      order_by: [asc: r.source_work_id, asc: r.target_work_id]
    )
    |> then(fn query ->
      if work_id,
        do: where(query, [r, _cs, _rt], r.source_work_id == ^work_id),
        else: query
    end)
  end

  defp commentary_pair_fact_query(work_id) do
    commentary_pair_query(work_id)
    |> select([r, cs, rt], %{
      commentary_work_id: r.source_work_id,
      root_work_id: r.target_work_id,
      relation: r.relation,
      commentary_text_id: cs.id,
      commentary_source_id: cs.source_id,
      commentary_body_sha256: cs.body_sha256,
      root_text_id: rt.id,
      root_source_id: rt.source_id,
      root_body_sha256: rt.body_sha256
    })
  end

  defp quotation_output_rows(nil, _scope, _min_length), do: []

  defp quotation_output_rows(bake_id, scope, min_length) do
    ids =
      scope
      |> quotation_text_facts()
      |> Enum.map(& &1.id)

    if ids == [] do
      []
    else
      Repo.all(
        from q in Quotation,
          where:
            q.bake_id == ^bake_id and q.length >= ^min_length and
              q.a_text_id in ^ids and q.b_text_id in ^ids,
          order_by: [asc: q.a_text_id, asc: q.a_char_start, asc: q.b_text_id, asc: q.b_char_start],
          select: %{
            text_sha256: q.text_sha256,
            length: q.length,
            a_text_id: q.a_text_id,
            a_work_id: q.a_work_id,
            a_urn: q.a_urn,
            a_char_start: q.a_char_start,
            a_char_end: q.a_char_end,
            b_text_id: q.b_text_id,
            b_work_id: q.b_work_id,
            b_urn: q.b_urn,
            b_char_start: q.b_char_start,
            b_char_end: q.b_char_end
          }
      )
    end
  end

  defp relation_output_rows(method) do
    Repo.all(
      from r in WorkRelation,
        where: r.method == ^method,
        order_by: [
          asc: r.source_work_id,
          asc: r.target_work_id,
          asc: r.target_work_ref,
          asc: r.relation
        ],
        select: %{
          source_work_id: r.source_work_id,
          target_work_id: r.target_work_id,
          target_work_ref: r.target_work_ref,
          relation: r.relation,
          scope: r.scope,
          target_urn: r.target_urn,
          confidence: r.confidence,
          method: r.method,
          evidence: r.evidence
        }
    )
  end

  defp alignment_output_rows(nil, _scope), do: []

  defp alignment_output_rows(bake_id, scope) do
    from(a in CommentaryAlignment,
      where: a.bake_id == ^bake_id,
      order_by: [
        asc: a.commentary_work_id,
        asc: a.root_work_id,
        asc: a.commentary_char_start,
        asc: a.root_char_start
      ],
      select: %{
        lemma_sha256: a.lemma_sha256,
        length: a.length,
        commentary_text_id: a.commentary_text_id,
        commentary_work_id: a.commentary_work_id,
        commentary_urn: a.commentary_urn,
        commentary_char_start: a.commentary_char_start,
        commentary_char_end: a.commentary_char_end,
        root_text_id: a.root_text_id,
        root_work_id: a.root_work_id,
        root_urn: a.root_urn,
        root_char_start: a.root_char_start,
        root_char_end: a.root_char_end,
        method: a.method,
        confidence: a.confidence
      }
    )
    |> maybe_alignment_work(scope["work"])
    |> Repo.all()
  end

  defp maybe_alignment_work(query, nil), do: query

  defp maybe_alignment_work(query, work_id),
    do: where(query, [a], a.commentary_work_id == ^work_id)

  defp integer_parameter(parameters, key, default) do
    case parameters[key] do
      value when is_integer(value) -> value
      _ -> default
    end
  end

  defp integer_stat(stats, key) do
    case stats[key] do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), stringify_value(value)}
    end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value) when is_atom(value) and value not in [true, false, nil], do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
