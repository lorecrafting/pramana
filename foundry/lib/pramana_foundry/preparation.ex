defmodule PramanaFoundry.Preparation do
  @moduledoc "Pure preparation selection from a ticket's declared resources."

  @workflow_checks [
    %{argv: ["mise", "trust"], cwd: "."},
    %{argv: ["mise", "exec", "--", "mix", "deps.get", "--locked"], cwd: "workflow"}
  ]
  @database_checks [
    %{argv: ["mise", "exec", "--", "mix", "deps.get", "--locked"], cwd: "."},
    %{argv: ["mise", "exec", "--", "mix", "ecto.create"], cwd: "."}
  ]

  def commands(%{"shared_resources" => %{"database" => database}}) when is_list(database) do
    if database == [], do: @workflow_checks, else: @workflow_checks ++ @database_checks
  end

  def commands(_), do: {:error, :invalid_resource_declaration}
end
