defmodule PramanaFoundry.Effects.SilenceWatchdog do
  @moduledoc """
  A provider-response-silence deadline, configured separately from any task or check
  timeout. It only ever reasons about durable progress evidence: a provider/session
  event plus the exact live agent, pane, terminal, session, role, task, run, and
  pid/child-process identity. Transcript spinner text, wall-clock silence alone, and a
  mutable checkout timestamp are structurally excluded -- `evidence_sufficient?/1`
  refuses anything not shaped as durable evidence, so a caller cannot pass a spinner
  string in as if it were progress. A verified long-running command or tool with its
  own declared deadline is exempt entirely while that identity remains live.
  """

  @required_fields ~w(source event_at agent pane_id terminal_id session role task_id run_id pid)a
  @durable_source :durable_provider_event

  @type evidence :: %{required(atom()) => term()}

  @spec evidence_sufficient?(term()) :: boolean()
  def evidence_sufficient?(%{source: @durable_source} = evidence) do
    Enum.all?(@required_fields, fn field ->
      case Map.fetch(evidence, field) do
        {:ok, value} -> present?(value)
        :error -> false
      end
    end)
  end

  def evidence_sufficient?(_evidence), do: false

  @doc "A check or tool that declares its own deadline is never subject to this watchdog."
  @spec exempt?(%{optional(:own_deadline_epoch) => term()}) :: boolean()
  def exempt?(%{own_deadline_epoch: deadline}) when is_number(deadline), do: true
  def exempt?(_identified_effect), do: false

  @doc "True once `silence_seconds` have elapsed since the last sufficient evidence."
  @spec expired?(term(), number(), number()) :: boolean()
  def expired?(evidence, silence_seconds, now_epoch)
      when is_number(silence_seconds) and silence_seconds > 0 and is_number(now_epoch) do
    evidence_sufficient?(evidence) and now_epoch - evidence.event_at > silence_seconds
  end

  @outcomes ~w(capacity rate_limit subscription_quota cooldown unrelated_provider)a

  @doc """
  Classifies a recorded provider signal without ever calling the provider: capacity,
  rate-limit, subscription-quota, and cooldown frames are read off durable evidence the
  caller already collected, the same way `docs/RULES.md`-style quota/cooldown
  recognition works today; anything else is silence with no attributable cause.
  """
  @spec classify(%{optional(:signal) => atom()}) :: atom()
  def classify(%{signal: signal}) when signal in @outcomes, do: signal
  def classify(_evidence), do: :silent_no_progress

  defp present?(value), do: not is_nil(value) and value != ""
end
