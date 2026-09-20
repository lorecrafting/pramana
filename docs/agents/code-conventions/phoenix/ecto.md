# Ecto conventions

Applies when changing Pramāṇa Ecto schemas, changesets, queries, seeds or migrations.
Also read the shared [Elixir conventions](../elixir.md).

- Preload Ecto associations in queries when templates will access them.
- `Ecto.Schema` fields use `:string` even when the database column is `:text`.
- `Ecto.Changeset.validate_number/2` does not support `:allow_nil`; validations already
  run only when an applicable non-nil change is present.
- Use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields.
- Fields set programmatically, such as `user_id`, must not be admitted through `cast`;
  set them explicitly when constructing or changing the struct.
- Generate migrations with `mix ecto.gen.migration migration_name_using_underscores`
  so timestamps and project conventions are applied.
- When writing `seeds.exs`, import `Ecto.Query` or other supporting modules when the
  seed code actually uses them.

[Code convention router](../README.md)
