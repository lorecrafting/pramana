defmodule PramanaFoundry.Status do
  @moduledoc """
  System status reporting, revision visibility, and restart reconciliation.
  """

  alias PramanaFoundry.Status.Report

  defdelegate report(state, opts \\ []), to: Report, as: :generate
  defdelegate runtime_implementation_revision(), to: Report
  defdelegate set_runtime_implementation_revision(revision), to: Report
  defdelegate reconcile_runtime_implementation_revision(accepted_revision), to: Report

  def status(state), do: Report.generate(state)
end
