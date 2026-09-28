defmodule Mix.Tasks.Pramana.Reviews do
  use Mix.Task

  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Publishing.Guard
  alias Pramana.Reviewer.Adjudications
  alias Pramana.Reviewer.Reviews
  alias Pramana.Runtime

  @shortdoc "Inspect and adjudicate attributed commentary-link reviews"

  @switches [
    scope: :string,
    assertion_id: :string,
    fingerprint: :string,
    disposition: :string,
    rationale: :string,
    source_references: :string,
    operator: :string
  ]

  @moduledoc """
  Operator-only review adjudication. Use an administrative database credential and an
  exact saved pilot scope artifact. The CLI never infers a scholarly verdict from votes.

      mix pramana.reviews show --scope PATH --assertion-id ID
      mix pramana.reviews decide --scope PATH --assertion-id ID \\
        --fingerprint SHA256 --disposition supported|disputed|unresolved \\
        --rationale TEXT --source-references TEXT --operator ID

  Run `show` first. `decide` requires its current fingerprint and at least one attributed
  judgment on that exact assertion. Supported clears the relation's review flag and
  invalidates the saved scope; materialize and review a new scope before more decisions.
  Disputed and unresolved preserve `needs_review` and do not admit an answer path.
  """

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)
    validate_action!(args, opts)

    if Guard.public?() or Runtime.reviewer?(),
      do: Mix.raise("Review adjudication requires a separate operator process")

    Mix.Task.run("app.start")

    artifact =
      case Reviews.load_scope(opts[:scope]) do
        {:ok, artifact} -> artifact
        _ -> Mix.raise("scope artifact is invalid or superseded; inspect its path and hash")
      end

    case args do
      ["show"] -> show(artifact, opts[:assertion_id])
      ["decide"] -> decide(artifact, opts)
    end
  end

  defp show(artifact, assertion_id) do
    case Adjudications.inspect_case(artifact, assertion_id) do
      {:ok, case_info} ->
        Mix.shell().info("""
        Assertion #{case_info.row.id}; current fingerprint #{case_info.fingerprint}
        Matches selected scope: #{case_info.in_scope}
        Scope #{artifact["scope_content_sha256"]}; release #{artifact["release"]["release_id"]}
        #{ScopeArtifact.encode(case_info.snapshot)}
        """)

        Enum.each(case_info.judgments, &print_judgment(&1, case_info, artifact))
        Enum.each(case_info.dispositions, &print_disposition/1)

      _ ->
        Mix.raise("assertion does not exist")
    end
  end

  defp print_judgment(item, case_info, artifact) do
    judgment = item.judgment

    current =
      judgment.scope_sha256 == artifact["scope_content_sha256"] and
        judgment.release_id == artifact["release"]["release_id"] and
        judgment.assertion_fingerprint == case_info.fingerprint

    label = if current, do: "current", else: "STALE"

    Mix.shell().info("""
    Judgment #{judgment.id} (#{label}) by #{item.email}
      #{judgment.judgment}; fingerprint #{judgment.assertion_fingerprint}
      reason: #{judgment.rationale}
      sources: #{judgment.source_references}
    """)
  end

  defp print_disposition(disposition) do
    Mix.shell().info("""
    Earlier operator disposition #{disposition.id} by #{disposition.operator_id}
      #{disposition.disposition}; fingerprint #{disposition.assertion_fingerprint}
      reason: #{disposition.rationale}
      sources: #{disposition.source_references}
    """)
  end

  defp decide(artifact, opts) do
    attrs = %{
      disposition: opts[:disposition],
      rationale: opts[:rationale],
      source_references: opts[:source_references],
      operator_id: opts[:operator]
    }

    case Adjudications.decide(artifact, opts[:assertion_id], opts[:fingerprint], attrs) do
      {:ok, disposition} ->
        Mix.shell().info("Recorded #{disposition.disposition} disposition #{disposition.id}")

        if disposition.disposition == "supported" do
          Mix.shell().info("Old scope invalidated; rematerialize and review before reuse")
        end

      _ ->
        Mix.raise("decision refused; check current assertion, fingerprint, judgment and scope")
    end
  end

  defp validate_action!(args, opts) do
    required =
      case args do
        ["show"] ->
          [:scope, :assertion_id]

        ["decide"] ->
          [
            :scope,
            :assertion_id,
            :fingerprint,
            :disposition,
            :rationale,
            :source_references,
            :operator
          ]

        _ ->
          Mix.raise(@moduledoc)
      end

    if Enum.any?(required, &(not is_binary(opts[&1]))) or
         Enum.any?(Keyword.keys(opts), &(&1 not in required)) do
      Mix.raise(@moduledoc)
    end
  end
end
