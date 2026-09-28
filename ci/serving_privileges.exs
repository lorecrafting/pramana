# Runs by release RPC in the very process serving the positive HTTP/MCP case.
# Fixed synthetic credentials/objects only; never invoke against an operator database.
defmodule Pramana.CI.ServingPrivileges do
  @moduledoc false

  alias Pramana.Repo

  def run do
    expected_role = System.get_env("PRAMANA_SMOKE_ROLE", "smoke_reader")

    # A read-only transaction default is reversible by its user and is not a grant
    # boundary. Denial tests below deliberately request read-write transactions.
    expect!(
      query!("""
      SELECT current_user, session_user, rolsuper, rolcreatedb, rolcreaterole,
             rolreplication, rolbypassrls
      FROM pg_roles WHERE rolname = current_user
      """) == [[expected_role, expected_role, false, false, false, false, false]],
      "unexpected serving identity or elevated role attributes"
    )

    expect_zero!("""
    SELECT count(*) FROM pg_roles
    WHERE rolname <> current_user AND pg_has_role(current_user, oid, 'MEMBER')
    """)

    expect_zero!("""
    SELECT count(*) FROM pg_database
    WHERE datname = current_database() AND
      (datdba = (SELECT oid FROM pg_roles WHERE rolname = current_user)
       OR has_database_privilege(oid, 'CREATE,TEMPORARY'))
    """)

    expect_zero!("""
    SELECT count(*) FROM pg_namespace
    WHERE nspname = 'public' AND
      (nspowner = (SELECT oid FROM pg_roles WHERE rolname = current_user)
       OR has_schema_privilege(oid, 'CREATE'))
    """)

    # AND predicates may be reordered. CASE keeps each type-sensitive privilege
    # function away from indexes and other objects it cannot inspect.
    expect_zero!("""
    SELECT count(*) FROM pg_class
    WHERE relnamespace = 'public'::regnamespace AND
      relname NOT IN ('users', 'users_tokens') AND
      (current_user <> 'smoke_reviewer' OR relname <> 'reviewer_judgments') AND
      CASE WHEN relkind IN ('r','p','v','m','f') THEN
        (relowner = (SELECT oid FROM pg_roles WHERE rolname = current_user)
         OR has_table_privilege(oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
         OR has_any_column_privilege(oid, 'INSERT,UPDATE,REFERENCES'))
      ELSE false END
    """)

    expect_zero!("""
    SELECT count(*) FROM pg_class
    WHERE relnamespace = 'public'::regnamespace AND
      CASE WHEN relkind = 'S' THEN has_sequence_privilege(oid, 'USAGE,UPDATE')
      ELSE false END
    """)

    expect_zero!("""
    SELECT count(*) FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace AND prosecdef
      AND has_function_privilege(oid, 'EXECUTE')
    """)

    for statement <- [
          "INSERT INTO works (id,title) SELECT 'denied','denied' WHERE false",
          "UPDATE segments SET content = content WHERE false",
          "DELETE FROM translations WHERE false",
          "TRUNCATE works CASCADE",
          "CREATE TABLE public.denied (id integer)",
          "CREATE TEMP TABLE denied (id integer)",
          "ALTER TABLE works ADD COLUMN denied integer",
          "SELECT nextval('segments_id_seq')",
          "SELECT * FROM oban_jobs LIMIT 0",
          "UPDATE reviewer_judgments SET rationale = rationale WHERE false",
          "DELETE FROM reviewer_judgments WHERE false",
          "INSERT INTO reviewer_dispositions (id) SELECT NULL::uuid WHERE false",
          "DELETE FROM users WHERE false",
          "UPDATE users_tokens SET token = token WHERE false",
          "INSERT INTO reviewer_grants (id) SELECT NULL::uuid WHERE false",
          "SET ROLE postgres"
        ] do
      denied =
        Repo.transaction(fn ->
          query!("SET TRANSACTION READ WRITE")

          case Ecto.Adapters.SQL.query(Repo, statement, []) do
            {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} ->
              Repo.rollback(:denied)

            _ ->
              # Roll back even an unexpectedly successful DDL/DML probe.
              Repo.rollback(:not_denied)
          end
        end)

      expect!(denied == {:error, :denied}, "serving operation was not denied: #{statement}")
    end

    if expected_role == "smoke_reader" do
      for table <- ["reviewer_grants", "reviewer_judgments", "reviewer_dispositions"] do
        denied = Ecto.Adapters.SQL.query(Repo, "SELECT * FROM #{table} LIMIT 0", [])

        expect!(
          match?({:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}}, denied),
          "public reader could inspect private reviewer table: #{table}"
        )
      end
    else
      expect!(
        query!("SELECT count(*) FROM users") == [[0]] and
          query!("SELECT count(*) FROM reviewer_grants") == [[0]] and
          query!("SELECT count(*) FROM reviewer_judgments") == [[0]] and
          query!("SELECT count(*) FROM reviewer_dispositions") == [[0]],
        "private reviewer cannot read review identity/evidence records"
      )

      expect!(
        query!("SELECT has_table_privilege('reviewer_judgments', 'INSERT')") == [[true]],
        "private reviewer cannot append judgments"
      )

      expect!(
        query!("""
        SELECT has_table_privilege('reviewer_judgments',
          'UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
        """) == [[false]],
        "private reviewer can alter existing judgments"
      )

      expect!(
        query!("""
        SELECT relowner = (SELECT oid FROM pg_roles WHERE rolname = current_user)
          OR has_any_column_privilege(oid, 'UPDATE,REFERENCES')
        FROM pg_class WHERE oid = 'reviewer_judgments'::regclass
        """) == [[false]],
        "private reviewer owns or can alter a judgment column"
      )

      query!("INSERT INTO reviewer_judgments (id) SELECT NULL::uuid WHERE false")
    end

    expect!(
      query!("SELECT has_table_privilege('users_tokens', 'INSERT')") == [[true]] and
        query!("SELECT has_table_privilege('users_tokens', 'DELETE')") == [[true]],
      "serving account cannot create and consume auth tokens"
    )

    expect_zero!("""
    SELECT count(*) FROM pg_class
    WHERE relname IN ('users', 'users_tokens') AND
      relowner = (SELECT oid FROM pg_roles WHERE rolname = current_user)
    """)

    expect!(
      query!(
        "SELECT has_table_privilege('users_tokens', 'UPDATE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')"
      ) == [[false]] and
        query!("SELECT has_any_column_privilege('users_tokens', 'UPDATE,REFERENCES')") ==
          [[false]] and
        query!(
          "SELECT has_table_privilege('users', 'DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')"
        ) == [[false]],
      "serving account can alter auth history or identity rows"
    )

    expect_zero!("""
    SELECT count(*) FROM pg_attribute
    WHERE attrelid = 'users'::regclass AND attnum > 0 AND NOT attisdropped
      AND attname NOT IN ('email', 'hashed_password', 'confirmed_at', 'updated_at')
      AND has_column_privilege('users', attname, 'UPDATE,REFERENCES')
    """)

    expect!(
      query!("SELECT has_table_privilege('users', 'INSERT')") ==
        [[expected_role == "smoke_reader"]],
      "private reviewer can create users or public account cannot register"
    )

    IO.puts("SERVING_PRIVILEGES_OK")
  end

  defp query!(sql), do: Ecto.Adapters.SQL.query!(Repo, sql, []).rows

  defp expect_zero!(sql),
    do: expect!(query!(sql) == [[0]], "unexpected effective serving authority")

  defp expect!(true, _message), do: :ok
  defp expect!(false, message), do: raise(message)
end

Pramana.CI.ServingPrivileges.run()
