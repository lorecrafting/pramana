defmodule PramanaFoundry.SchemaReference do
  @moduledoc false

  # Generates the durable-store schema reference from the schema itself.
  #
  # Written generated rather than by hand deliberately. A hand-maintained schema document
  # drifts, and in this repository a stale document is worse than none: the discipline
  # elsewhere is to generate evidence and pin it by hash rather than describe it in prose.
  # A test asserts the committed reference equals this output, so it cannot drift without
  # failing.
  #
  # This exists because the schema was undocumented and that cost real design time: a
  # correction was designed against the record codec without the CHECK constraint on
  # events.schema_version being visible anywhere but one line of database.ex.

  @source "lib/pramana_foundry/durable_store/database.ex"
  @doc_path "docs/DURABLE-STORE-SCHEMA.md"

  @spec source_path() :: String.t()
  def source_path, do: @source

  @spec doc_path() :: String.t()
  def doc_path, do: @doc_path

  @doc """
  Renders the complete reference. `root` is the Foundry project root.
  """
  @spec render(Path.t()) :: String.t()
  def render(root \\ File.cwd!()) do
    tables = parse(File.read!(Path.join(root, @source)))

    [
      header(),
      Enum.map(tables, &table_section/1)
    ]
    |> IO.iodata_to_binary()
  end

  defp header do
    """
    # Durable store schema reference

    **Generated from [`#{@source}`](../#{@source}). Do not edit by hand.**
    `PramanaFoundry.SchemaReferenceTest` fails if this file and the schema disagree.

    Regenerate with:

    ```sh
    cd foundry
    mix run --no-start -e 'File.write!(PramanaFoundry.SchemaReference.doc_path(), PramanaFoundry.SchemaReference.render())'
    ```

    This reference describes the schema as declared. It is not evidence that any table is
    populated, that a migration has run against a given store, or that any behavior is
    activated. [The durable store overview](DURABLE-STORE.md) describes intent; this
    describes the declarations.

    ## Reading the constraints

    Only some columns are constrained by the schema itself. A vocabulary enforced solely
    in Elixir does not appear here, and a `TEXT` column with no `CHECK` accepts any string
    at the storage layer whatever the application validates. `STRICT` tables reject values
    of the wrong storage class; SQLite cannot alter a `CHECK` in place, so changing one
    requires rebuilding its table.

    """
  end

  defp table_section({name, columns, suffix}) do
    [
      "## `#{name}`",
      if(suffix == "", do: "", else: "\n\n`#{suffix}`"),
      "\n\n```sql\n",
      Enum.map(columns, &["  ", &1, "\n"]),
      "```\n\n"
    ]
  end

  @doc """
  Parses `CREATE TABLE` declarations into `{name, column_lines, table_suffix}`.
  """
  @spec parse(String.t()) :: [{String.t(), [String.t()], String.t()}]
  def parse(source) do
    ~r/CREATE TABLE (\w+) \((.*?)\n\s*\)\s*([A-Z, ]*);/s
    |> Regex.scan(source)
    |> Enum.map(fn [_all, name, body, suffix] ->
      columns =
        body
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {name, columns, String.trim(suffix)}
    end)
  end
end
