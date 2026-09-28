defmodule Mix.Tasks.Pramana.Reviewer do
  use Mix.Task

  alias Pramana.Accounts
  alias Pramana.Mailer
  alias Pramana.Publishing.Guard
  alias Pramana.ReviewerAccess
  alias Pramana.Runtime

  @shortdoc "Provision, grant, or revoke private reviewer access"
  @switches [email: :string, scope_sha256: :string, operator: :string, capability: :string]

  @moduledoc """
  Operator-only reviewer account management. Run against the private review database
  with administrative credentials, outside reviewer/public serving mode.

      mix pramana.reviewer provision --email EMAIL
      mix pramana.reviewer grant --email EMAIL --scope-sha256 HASH --operator ID [--capability relation_review|rights_signoff]
      mix pramana.reviewer revoke --email EMAIL --scope-sha256 HASH --operator ID [--capability relation_review|rights_signoff]
      mix pramana.reviewer revoke --email EMAIL --operator ID

  Provision sends a Phoenix magic link to the configured PRAMANA_REVIEWER_URL.
  Grant only after the reviewer confirms that link. Provision never grants access.
  """

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)
    validate_action!(args, opts)

    if Guard.public?() or Runtime.reviewer?(),
      do: Mix.raise("Reviewer account management requires a separate operator process")

    Mix.Task.run("app.start")

    case perform(args, opts) do
      {:ok, _record} ->
        Mix.shell().info("Reviewer action completed")

      :ok ->
        Mix.shell().info("Reviewer action completed")

      {:error, _reason} ->
        Mix.raise("Reviewer action failed; inspect account, scope, mail and grants")
    end
  end

  defp perform(["provision"], opts) do
    if not Mailer.delivery_ready?(), do: Mix.raise("Account email delivery is unavailable")
    base = reviewer_url!()

    with {:ok, user} <- Accounts.register_user(%{email: opts[:email]}),
         {:ok, _mail} <-
           Accounts.deliver_login_instructions(user, &"#{base}/users/log-in/#{&1}") do
      {:ok, user}
    end
  end

  defp perform(["grant"], opts),
    do:
      ReviewerAccess.grant_scope(
        opts[:email],
        opts[:scope_sha256],
        opts[:operator],
        opts[:capability] || "relation_review"
      )

  defp perform(["revoke"], opts) do
    if opts[:scope_sha256],
      do:
        ReviewerAccess.revoke_scope(
          opts[:email],
          opts[:scope_sha256],
          opts[:operator],
          opts[:capability]
        ),
      else: ReviewerAccess.revoke_all(opts[:email], opts[:operator])
  end

  defp reviewer_url! do
    case URI.parse(System.get_env("PRAMANA_REVIEWER_URL") || "") do
      %URI{scheme: "https", host: host, path: path, userinfo: nil, query: nil, fragment: nil} =
          uri
      when is_binary(host) and path in [nil, "", "/"] ->
        URI.to_string(uri) |> String.trim_trailing("/")

      %URI{
        scheme: "http",
        host: "localhost",
        path: path,
        userinfo: nil,
        query: nil,
        fragment: nil
      } = uri
      when path in [nil, "", "/"] ->
        URI.to_string(uri) |> String.trim_trailing("/")

      _ ->
        Mix.raise("PRAMANA_REVIEWER_URL must be the private HTTPS origin (localhost HTTP in dev)")
    end
  end

  defp validate_action!(args, opts) do
    required =
      case args do
        ["provision"] ->
          [:email]

        ["grant"] ->
          [:email, :scope_sha256, :operator]

        ["revoke"] ->
          if(opts[:scope_sha256],
            do: [:email, :scope_sha256, :operator],
            else: [:email, :operator]
          )

        _ ->
          Mix.raise(@moduledoc)
      end

    allowed =
      if(args in [["grant"], ["revoke"]] and opts[:scope_sha256],
        do: required ++ [:capability],
        else: required
      )

    unless valid_options?(opts, required, allowed), do: Mix.raise(@moduledoc)
  end

  defp valid_options?(opts, required, allowed) do
    Enum.all?(required, &is_binary(opts[&1])) and
      Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and
      opts[:capability] in [nil, "relation_review", "rights_signoff"]
  end
end
