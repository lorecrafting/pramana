defmodule PramanaFoundry.SchemaReferenceTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.SchemaReference

  @root Path.expand("../..", __DIR__)

  test "the committed reference matches the schema it is generated from" do
    committed = File.read!(Path.join(@root, SchemaReference.doc_path()))

    assert committed == SchemaReference.render(@root), """
    docs/DURABLE-STORE-SCHEMA.md is out of date with database.ex.

    Regenerate it rather than editing by hand:

        cd foundry
        mix run --no-start -e 'File.write!(PramanaFoundry.SchemaReference.doc_path(), PramanaFoundry.SchemaReference.render())'
    """
  end

  test "every table declared in the schema appears in the reference" do
    source = File.read!(Path.join(@root, SchemaReference.source_path()))
    declared = Regex.scan(~r/CREATE TABLE (\w+) \(/, source) |> Enum.map(&Enum.at(&1, 1))
    parsed = SchemaReference.parse(source) |> Enum.map(&elem(&1, 0))

    assert declared != []

    # The parser is a regex over the schema, so a table whose declaration is formatted
    # unusually could be silently dropped. That would produce a reference that is
    # confidently incomplete, which is worse than none.
    assert Enum.sort(parsed) == Enum.sort(declared),
           "tables declared but missing from the reference: #{inspect(declared -- parsed)}"
  end

  test "the constraints that are easy to miss are actually rendered" do
    rendered = SchemaReference.render(@root)

    # These are load-bearing and invisible from anywhere but database.ex. A design
    # revision was spent in this repair because the first was not documented anywhere.
    assert rendered =~ "schema_version INTEGER NOT NULL CHECK (schema_version = 1)"
    assert rendered =~ "event_type TEXT NOT NULL"
    assert rendered =~ "STRICT"
  end
end
