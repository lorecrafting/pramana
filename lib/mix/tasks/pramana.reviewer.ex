defmodule Mix.Tasks.Pramana.Reviewer do
  use Mix.Task

  alias Pramana.Publishing.Guard
  alias Pramana.ReviewerAccess
  alias Pramana.Runtime

  @shortdoc "Provision, grant, revoke or rotate a private reviewer account"

  @switches [
    login_id: :string,
    display_name: :string,
    scope_sha256: :string,
    operator: :string
  ]

  @moduledoc """
  Operator-only reviewer account management. Run with administrative database credentials,
  outside reviewer/public serving mode. Credentials are printed once; deliver them privately.

      mix pramana.reviewer provision --login-id ID --display-name NAME --scope-sha256 HASH --operator ID
      mix pramana.reviewer grant --login-id ID --scope-sha256 HASH --operator ID
      mix pramana.reviewer revoke --login-id ID --scope-sha256 HASH --operator ID
      mix pramana.reviewer revoke --login-id ID
      mix pramana.reviewer rotate --login-id ID
  """

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)
    validate_action!(args, opts)

    if Guard.public?() or Runtime.reviewer?(),
      do: Mix.raise("Reviewer account management requires a separate operator process")

    Mix.Task.run("app.start")

    case perform(args, opts) do
      {:ok, _account, credential} ->
        Mix.shell().info("Credential (deliver privately): #{credential}")

      {:ok, _record} ->
        Mix.shell().info("Reviewer action completed")

      :ok ->
        Mix.shell().info("Reviewer action completed")

      {:error, _reason} ->
        Mix.raise("Reviewer action failed; inspect the account, scope and grants")
    end
  end

  defp perform(["provision"], opts),
    do:
      ReviewerAccess.provision(
        opts[:login_id],
        opts[:display_name],
        opts[:scope_sha256],
        opts[:operator]
      )

  defp perform(["grant"], opts),
    do: ReviewerAccess.grant_scope(opts[:login_id], opts[:scope_sha256], opts[:operator])

  defp perform(["revoke"], opts) do
    if opts[:scope_sha256],
      do: ReviewerAccess.revoke_scope(opts[:login_id], opts[:scope_sha256], opts[:operator]),
      else: ReviewerAccess.disable_account(opts[:login_id])
  end

  defp perform(["rotate"], opts), do: ReviewerAccess.rotate_credential(opts[:login_id])

  defp validate_action!(args, opts) do
    required =
      case args do
        ["provision"] ->
          [:login_id, :display_name, :scope_sha256, :operator]

        ["grant"] ->
          [:login_id, :scope_sha256, :operator]

        ["revoke"] ->
          if opts[:scope_sha256],
            do: [:login_id, :scope_sha256, :operator],
            else: [:login_id]

        ["rotate"] ->
          [:login_id]

        _ ->
          Mix.raise(@moduledoc)
      end

    if Enum.any?(required, &(not is_binary(opts[&1]))) or
         Enum.any?(Keyword.keys(opts), &(&1 not in required)) do
      Mix.raise(@moduledoc)
    end
  end
end
