#!/usr/bin/env python3
"""Exercise a built release with owned Docker resources and synthetic data only.

No operator DATABASE_URL, credentials, corpus, model, host service or image push is
used. PostgreSQL is disposable; HTTP is published on loopback only. Run from any
working directory: python3 pramana/ci/release_smoke.py --image pramana:ci.
"""
import argparse
import hashlib
import http.client
import json
import re
import subprocess
import time
import uuid

if not __debug__:
    raise RuntimeError("release acceptance requires Python assertions; do not use -O")
from pathlib import Path

TEXT = "Synthetic startup fixture."
URN = "pramana:sc.ms:smoke1@1.1"
SECRET = "synthetic-release-smoke-only-" + "0" * 64
READER = "smoke_reader"
READER_PASSWORD = "synthetic-reader-only"
BAKE_TEXT = "PUBLIC_INGEST_SENTINEL"
BAKE_XML = f"""<TEI xmlns="http://www.tei-c.org/ns/1.0">
<teiHeader><fileDesc><titleStmt><title level="m" xml:lang="zh-Hant">Synthetic bake</title>
</titleStmt></fileDesc></teiHeader><text><body><milestone n="1" unit="juan"/>
<lb n="0001c19"/>{BAKE_TEXT}</body></text></TEI>"""


class Smoke:
    def __init__(self, image, output):
        self.image = image
        self.output = output.resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.token = uuid.uuid4().hex
        self.prefix = "pramana-smoke-" + self.token[:12]
        self.label = "org.pramana.release-smoke=" + self.token
        self.network = self.prefix + "-net"
        self.db = self.prefix + "-db"
        self.raw = self.output / "raw"
        raw_file = self.raw / "cbeta/T/T09/T09n9999.xml"
        raw_file.parent.mkdir(parents=True, exist_ok=True)
        raw_file.write_text(BAKE_XML)
        self.counter = 0
        self.results = {"image": image, "cases": []}

    def command(self, *args, stdin=None, timeout=120, check=True):
        result = subprocess.run(args, input=stdin, text=True, capture_output=True, timeout=timeout)
        self.counter += 1
        (self.output / f"command-{self.counter:03d}.log").write_text(
            f"argv: {list(args)!r}\nexit: {result.returncode}\n{result.stdout}\n{result.stderr}")
        if check and result.returncode:
            raise RuntimeError(f"command {self.counter} failed: exit {result.returncode}")
        return result

    def docker(self, *args, **opts):
        return self.command("docker", *args, **opts)

    def sql(self, database, sql):
        return self.docker("exec", "-i", self.db, "psql", "-XAt", "-v", "ON_ERROR_STOP=1",
                           "-U", "postgres", "-d", database, stdin=sql).stdout.strip()

    def prepare(self):
        self.results["image_id"] = self.docker("image", "inspect", self.image,
                                               "--format", "{{.Id}}").stdout.strip()
        # A tag may move between cases on an operator's Docker host.
        self.image = self.results["image_id"]
        self.docker("network", "create", "--label", self.label, self.network)
        self.docker("run", "-d", "--name", self.db, "--label", self.label, "--network", self.network,
                    "--network-alias", "db", "-e", "POSTGRES_PASSWORD=postgres",
                    "pgvector/pgvector:pg18")
        deadline = time.monotonic() + 60
        while True:
            if self.docker("exec", self.db, "pg_isready", "-U", "postgres", check=False).returncode == 0:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("disposable PostgreSQL did not become ready")
            time.sleep(0.25)
        # Same extension/tag as the ordinary umbrella lane; needed by real migrations.
        self.docker("exec", self.db, "bash", "-euc", """
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential postgresql-server-dev-18 wget ca-certificates
cd /tmp
wget -q https://github.com/pgbigm/pg_bigm/archive/refs/tags/v1.2-20250903.tar.gz
tar zxf v1.2-20250903.tar.gz
cd pg_bigm-1.2-20250903
make USE_PGXS=1 with_llvm=no
make USE_PGXS=1 with_llvm=no install
""", timeout=300)
        self.sql("postgres", "CREATE DATABASE allowed; CREATE DATABASE unmigrated;")
        self.evaluate("migrate", "allowed", """
Application.load(:pramana)
{:ok, _, _} = Ecto.Migrator.with_repo(Pramana.Repo, fn repo ->
  Ecto.Migrator.run(repo, :up, all: true)
end)
if Process.whereis(PramanaWeb.Endpoint), do: raise("migration started the web application")
IO.puts("EXPLICIT_MIGRATION_OK")
""")
        sha = hashlib.sha256(TEXT.encode()).hexdigest()
        self.sql("allowed", f"""
INSERT INTO sources (id,name,license_spdx,license_class,commercial_use,redistributable,inserted_at,updated_at)
VALUES ('sc','CI synthetic source','CC0-1.0','cc0',true,true,now(),now());
INSERT INTO witnesses (id,name,inserted_at,updated_at) VALUES ('ms','CI witness',now(),now());
INSERT INTO works (id,title,composition_origin,text_role,inserted_at,updated_at)
VALUES ('smoke1','Synthetic startup fixture','indic','root',now(),now());
INSERT INTO texts (work_id,source_id,witness_id,urn_prefix,body,body_sha256,inserted_at,updated_at)
VALUES ('smoke1','sc','ms','pramana:sc.ms:smoke1','{TEXT}','{sha}',now(),now());
INSERT INTO segments (text_id,urn,ordinal,content,content_sha256,char_start,char_end,byte_start,byte_end,inserted_at,updated_at)
SELECT id,'{URN}',1,'{TEXT}','{sha}',0,{len(TEXT)},0,{len(TEXT)},now(),now() FROM texts;
""")
        self.sql("postgres", "CREATE DATABASE forbidden TEMPLATE allowed; CREATE DATABASE restricted_translation TEMPLATE allowed;")
        self.sql("forbidden", "UPDATE sources SET redistributable=false,license_class='nc',license_spdx='LicenseRef-CI-Forbidden';")
        self.sql("restricted_translation", f"""
INSERT INTO translations (anchor_urn,work_id,lang,translator_id,tier,method,text,text_sha256,license_spdx,redistributable,inserted_at,updated_at)
VALUES ('{URN}','smoke1','en','ci','t0','human','synthetic restricted rendering','x','LicenseRef-CI-Forbidden',false,now(),now());
""")

        self.sql("postgres", "CREATE DATABASE queued TEMPLATE allowed; CREATE DATABASE audit_denied TEMPLATE allowed;")
        args = json.dumps({"source": "cbeta", "canon": "T", "volume": 9, "number": "9999",
                           "work_id": "T9999", "paths": ["T/T09/T09n9999.xml"]})
        self.sql("queued", f"""
INSERT INTO oban_jobs (state,queue,worker,args,max_attempts)
VALUES ('available','bake','Pramana.Bake.Worker','{args}'::jsonb,3);
INSERT INTO oban_jobs (state,queue,worker,args,attempt,completed_at,inserted_at)
VALUES ('completed','bake','Pramana.Bake.Worker','{{}}',1,now()-interval '9 days',now()-interval '9 days');
""")
        # Only this owned disposable cluster is changed. Runtime identities are not
        # table/database owners, and receive neither sequence nor Oban-table access.
        self.sql("postgres", f"""
CREATE ROLE {READER} LOGIN PASSWORD '{READER_PASSWORD}' NOSUPERUSER NOCREATEDB
  NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT;
""")
        for database in ["allowed", "forbidden", "restricted_translation", "unmigrated", "queued", "audit_denied"]:
            self.sql(database, f"""
REVOKE ALL ON DATABASE {database} FROM PUBLIC;
GRANT CONNECT ON DATABASE {database} TO {READER};
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO {READER};
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
SELECT format('GRANT SELECT ON TABLE %I.%I TO {READER}', schemaname, tablename)
FROM pg_tables WHERE schemaname='public' AND tablename NOT LIKE 'oban_%'
  AND tablename <> 'schema_migrations'
\\gexec
""")
        self.sql("audit_denied", f"REVOKE SELECT ON sources FROM {READER};")

    def options(self, case, database, public=True, role=None):
        name = self.prefix + "-" + case
        role = role or (READER if public else "postgres")
        password = READER_PASSWORD if role == READER else "postgres"
        return name, ["--name", name, "--label", self.label, "--network", self.network,
                      "-e", f"DATABASE_URL=ecto://{role}:{password}@db/{database}",
                      "-e", f"SECRET_KEY_BASE={SECRET}", "-e", "APP_HOST=localhost",
                      "-e", "PORT=4000", "-e", "POOL_SIZE=2",
                      "-e", "PRAMANA_EMBEDDING=0", "-e", f"PRAMANA_PUBLIC={'1' if public else '0'}",
                      "--mount", f"type=bind,source={self.raw},target=/app/raw,readonly"]

    def evaluate(self, case, database, code, public=False, serving=None):
        _, opts = self.options(case, database, public)
        if serving is not None:
            opts += ["-e", f"PHX_SERVER={'true' if serving else 'false'}"]
        return self.docker("run", *opts, "--entrypoint", "/app/bin/pramana", self.image, "eval", code, timeout=90)

    def launch(self, case, database, public=True, plain=False, role=None):
        name, opts = self.options(case, database, public, role)
        args = ["run", "-d", *opts, "-e", "PHX_SERVER=false", "-p", "127.0.0.1::4000"]
        if plain:
            args += ["--entrypoint", "/app/bin/pramana", self.image, "start"]
        else:
            args += [self.image]
        self.docker(*args)
        port = self.docker("port", name, "4000/tcp").stdout.strip().rsplit(":", 1)[1]
        return name, int(port)

    def state(self, name):
        return json.loads(self.docker("inspect", name, "--format", "{{json .State}}").stdout)

    @staticmethod
    def request(port, path, payload=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
        request_headers = {"Host": "localhost", **(headers or {})}
        data = None if payload is None else json.dumps(payload)
        if data is not None:
            request_headers.update({"Content-Type": "application/json",
                                    "Accept": "application/json, text/event-stream"})
        try:
            conn.request("GET" if data is None else "POST", path, data, request_headers)
            response = conn.getresponse()
            body = response.read(2_000_000).decode("utf-8")
            return response.status, dict((k.lower(), v) for k, v in response.getheaders()), body
        finally:
            conn.close()

    def wait_ready(self, name, port):
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if not self.state(name)["Running"]:
                raise RuntimeError(f"{name} exited before HTTP readiness")
            try:
                status, _, body = self.request(port, "/check")
                if status == 200 and "Check a report" in body:
                    return body
            except (OSError, http.client.HTTPException):
                pass
            time.sleep(0.1)
        raise RuntimeError("shipped entrypoint never served /check")

    @staticmethod
    def rpc_body(body):
        if body.lstrip().startswith("{"):
            return json.loads(body)
        for line in body.splitlines():
            if line.startswith("data: "):
                value = json.loads(line[6:])
                if "id" in value:
                    return value
        raise AssertionError("MCP did not return a JSON-RPC response")

    def serving(self, public):
        case = "allowed-public" if public else "restricted-research"
        name, port = self.launch(case, "allowed" if public else "forbidden", public)
        body = self.wait_ready(name, port)
        assets = set(re.findall(r'(?:src|href)="(/assets/[^" ]+)"', body))
        assert any(".css" in asset for asset in assets) and any(".js" in asset for asset in assets)
        for asset in assets:
            status, headers, content = self.request(port, asset)
            kind = "css" if ".css" in asset else "javascript"
            assert status == 200 and content and kind in headers.get("content-type", ""), f"asset missing: {asset}"
        status, _, inventory = self.request(port, "/inventory")
        assert status == 200 and "What is in this bake" in inventory, "real inventory page failed"
        request = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                   "params": {"protocolVersion": "2025-11-25", "capabilities": {},
                              "clientInfo": {"name": "release-smoke", "version": "1"}}}
        status, headers, body = self.request(port, "/mcp", request)
        reply = self.rpc_body(body)
        assert status == 200 and reply["result"]["serverInfo"]["name"] == "pramana"
        session = {"mcp-session-id": headers["mcp-session-id"]} if "mcp-session-id" in headers else {}
        session["mcp-protocol-version"] = "2025-11-25"
        self.request(port, "/mcp", {"jsonrpc": "2.0", "method": "notifications/initialized"}, session)
        status, _, body = self.request(port, "/mcp",
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}, session)
        names = {t["name"] for t in self.rpc_body(body)["result"]["tools"]}
        assert status == 200 and {"get_passage", "verify_report"} <= names
        status, _, body = self.request(port, "/mcp",
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
             "params": {"name": "get_passage", "arguments": {"urn": URN}}}, session)
        result = self.rpc_body(body)["result"]
        assert status == 200 and not result.get("isError", False)
        passage = json.loads(result["content"][0]["text"])
        assert passage["text"] == TEXT and passage["urn"] == URN
        if public:
            self.assert_no_jobs(name)
            probe = Path(__file__).with_name("serving_privileges.exs").read_text()
            assert "SERVING_PRIVILEGES_OK" in self.rpc(name, probe).stdout
            self.read_only_queries(port, session)
        self.docker("stop", "-t", "10", name)
        self.results["cases"].append({"case": case, "passed": True, "assets": sorted(assets)})

    def rpc(self, name, code):
        return self.docker("exec", name, "/app/bin/pramana", "rpc", code, timeout=45)

    def assert_no_jobs(self, name):
        # Oban uses a via registry: Process.whereis(Oban) is not a valid probe.
        code = """
if Oban.whereis(Oban), do: raise("public serving started Oban")
if Enum.any?(Supervisor.which_children(Pramana.Supervisor), fn {id, _, _, _} -> id == Oban end),
  do: raise("public supervisor retained an Oban child")
IO.puts("NO_PUBLIC_JOBS_OK")
"""
        assert "NO_PUBLIC_JOBS_OK" in self.rpc(name, code).stdout

    def read_only_queries(self, port, session):
        def call(identifier, tool, arguments):
            status, _, body = self.request(port, "/mcp",
                {"jsonrpc": "2.0", "id": identifier, "method": "tools/call",
                 "params": {"name": tool, "arguments": arguments}}, session)
            result = self.rpc_body(body)["result"]
            assert status == 200 and not result.get("isError", False), tool
            return json.loads(result["content"][0]["text"])

        survey = call(4, "survey_corpus", {"query": "Synthetic"})
        assert survey["total_segments"] == 1 and survey["distinct_works"] == 1
        search = call(5, "search", {"query": "Synthetic", "mode": "lexical"})
        assert URN in json.dumps(search), "lexical search lost the fixture"
        report = f"「{TEXT}」 ({URN})\n\n```pramana-replay\n" + json.dumps({
            "tool": "survey_corpus", "arguments": {"query": "Synthetic"},
            "assert": {"total_segments": 1, "distinct_works": 1}}) + "\n```"
        checked = call(6, "verify_report", {"report": report})
        assert checked["status"] == "verified" and checked["counts"]["verified_replays"] == 1
        assert checked["counts"]["verified_quotes"] == 1 and checked["repair"] is not None
        status, _, body = self.request(port, "/passage?urn=" + URN)
        assert status == 200 and TEXT in body
        self.results["cases"].append({"case": "restricted-account-reads-and-denied-writes", "passed": True})

    def background_isolation(self):
        snapshot_sql = "SELECT jsonb_agg(to_jsonb(j) ORDER BY id)::text FROM oban_jobs j;"
        before = self.sql("queued", snapshot_sql)
        jobs = json.loads(before)
        assert len(jobs) == 2 and {job["state"] for job in jobs} == {"available", "completed"}
        assert next(job for job in jobs if job["state"] == "available")["attempt"] == 0
        # Test with restricted AND privileged credentials, so a permission error
        # cannot masquerade as omission of the queue/pruner/peer instance.
        for role in [READER, "postgres"]:
            name, port = self.launch("queued-public-" + role, "queued", role=role)
            self.wait_ready(name, port)
            self.assert_no_jobs(name)
            assert self.sql("queued", snapshot_sql) == before, "public node changed job history"
            assert self.sql("queued", "SELECT count(*) FROM texts WHERE work_id='T9999';") == "0"
            self.docker("stop", "-t", "10", name)
        self.results["cases"].append({"case": "public-does-not-claim-prune-or-elect", "passed": True})

        # Same queued job and mounted source, no inline executor or direct perform:
        # the real research-mode Oban instance must process it and prune old history.
        name, port = self.launch("ingestion-control", "queued", public=False)
        self.wait_ready(name, port)
        code = """
unless is_pid(Oban.whereis(Oban)), do: raise("ingestion has no Oban instance")
conf = Oban.config()
unless conf.testing == :disabled, do: raise("not exercising the real queue")
unless Application.fetch_env!(:pramana, Oban)[:queues] == [bake: 8], do: raise("bake queue policy changed")
IO.puts("INGESTION_INSTANCE_OK")
"""
        assert "INGESTION_INSTANCE_OK" in self.rpc(name, code).stdout
        deadline = time.monotonic() + 70
        while time.monotonic() < deadline:
            rows = json.loads(self.sql("queued", snapshot_sql))
            if len(rows) == 1 and rows[0]["state"] == "completed" and rows[0]["attempt"] == 1:
                break
            if any(job["state"] in {"retryable", "discarded", "cancelled"} for job in rows):
                raise AssertionError("positive ingestion fixture failed")
            time.sleep(0.25)
        else:
            raise AssertionError("real queue/pruner did not complete the positive control")
        assert self.sql("queued", "SELECT content FROM segments WHERE urn='pramana:cbeta.T:T9999_001@p0001c19';") == BAKE_TEXT
        self.docker("stop", "-t", "10", name)
        self.results["cases"].append({"case": "same-fixture-ingested-and-history-pruned-in-research", "passed": True})

    def rejection(self, case, database, reason):
        name, port = self.launch(case, database)
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            try:
                self.request(port, "/check")
            except (OSError, http.client.HTTPException):
                pass
            else:
                raise AssertionError(f"rejected {case} served HTTP")
            state = self.state(name)
            if not state["Running"]:
                assert state["ExitCode"] != 0 and not state["OOMKilled"], state
                captured = self.docker("logs", name)
                logs = captured.stdout + captured.stderr
                assert reason in logs, f"{case} failed for the wrong reason"
                assert "Running PramanaWeb.Endpoint" not in logs
                self.results["cases"].append({"case": case, "passed": True, "exit": state["ExitCode"]})
                return
            time.sleep(0.1)
        raise AssertionError(f"{case} did not refuse within the harness deadline")

    def admission_order(self):
        # Fresh VM only: replace model construction with a canary, never real inference.
        # Setting the embedding flag without a canary could fetch/build a model on regression.
        code = '''
Code.compiler_options(ignore_module_conflict: true)
Code.compile_string("""
defmodule Pramana.Embed do
  def build_query_serving(_), do: raise("PRE_ADMISSION_MODEL_BUILD")
end
""")
System.put_env("PRAMANA_EMBEDDING", "1")
spec = Pramana.Embed.Serving.child_spec_if_enabled()
unless match?(%{id: Pramana.Embed.Serving, type: :supervisor,
               start: {Pramana.Embed.Serving, :start_link, []}}, spec),
  do: raise("wrong deferred serving spec")
try do
  Pramana.Embed.build_query_serving([])
  raise("canary not installed")
rescue
  error in RuntimeError ->
    unless error.message == "PRE_ADMISSION_MODEL_BUILD", do: reraise(error, __STACKTRACE__)
end
result = Application.ensure_all_started(:pramana_web)
unless match?({:error, _}, result) and inspect(result) =~ "public_corpus_forbidden",
  do: raise("wrong startup disposition: #{inspect(result)}")
for name <- [Pramana.Supervisor, Pramana.Repo, Oban, Pramana.Embed.Serving,
             PramanaWeb.Supervisor, PramanaWeb.Endpoint] do
  if Process.whereis(name), do: raise("rejected startup retained #{inspect(name)}")
end
IO.puts("ADMISSION_ORDER_OK")
'''
        result = self.evaluate("admission-order", "forbidden", code, public=True, serving=True)
        assert "ADMISSION_ORDER_OK" in result.stdout and "PRE_ADMISSION_MODEL_BUILD" not in result.stdout
        self.results["cases"].append({"case": "admission-before-model-and-web", "passed": True})

    def admitted_serving(self):
        # Positive counterpart to the refusal canary: native serving really starts
        # and answers after admission, without weights, downloads or an EXLA backend.
        code = '''
Code.compiler_options(ignore_module_conflict: true)
Code.compile_string("""
defmodule Pramana.Embed do
  def build_query_serving([]) do
    send(Application.fetch_env!(:pramana, :startup_smoke_owner), :constructed)
    Nx.Serving.new(fn opts ->
      Nx.Defn.jit(fn tensor -> tensor end, Keyword.put(opts, :compiler, Nx.Defn.Evaluator))
    end)
  end
end
""")
Application.load(:pramana)
Application.put_env(:pramana, :startup_smoke_owner, self())
System.put_env("PRAMANA_EMBEDDING", "1")
{:ok, _} = Application.ensure_all_started(:pramana_web)
receive do
  :constructed -> :ok
  after 5_000 -> raise("deferred serving never constructed")
end
unless Pramana.Embed.Serving.name() == Pramana.Embed.Serving,
  do: raise("native serving was not registered")
input = Nx.tensor([7], backend: Nx.BinaryBackend)
output = Nx.Serving.batched_run(Pramana.Embed.Serving, Nx.Batch.stack([input]))
unless Nx.to_flat_list(output) == [7], do: raise("native serving returned the wrong result")
IO.puts("ADMITTED_SERVING_OK")
'''
        result = self.evaluate("admitted-serving", "allowed", code, public=True)
        assert "ADMITTED_SERVING_OK" in result.stdout
        self.results["cases"].append({"case": "admitted-native-serving", "passed": True})

    def admin(self):
        code = '''
{:ok, _} = Application.ensure_all_started(:pramana_web)
unless PramanaWeb.Endpoint.config(:server) == false, do: raise("implicit server enabled")
case :gen_tcp.connect({127, 0, 0, 1}, 4000, [:binary, active: false], 1000) do
  {:error, :econnrefused} -> :ok
  other -> raise("unexpected listener: #{inspect(other)}")
end
IO.puts("NON_SERVING_OK")
'''
        result = self.evaluate("admin", "allowed", code, public=True)
        assert "NON_SERVING_OK" in result.stdout
        self.results["cases"].append({"case": "non-serving-administration", "passed": True})

    def close(self):
        # Discover by an unguessable run label, including resources created before
        # a subprocess timed out. Never remove a guessed name or another run's data.
        errors = []
        for kind, listing in [("container", ["ps", "-aq"]), ("network", ["network", "ls", "-q"])]:
            try:
                found = self.docker(*listing, "--filter", "label=" + self.label, timeout=20)
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                errors.append(f"{kind} discovery: {type(error).__name__}")
                continue
            for resource in found.stdout.split():
                try:
                    if kind == "container":
                        self.docker("logs", resource, check=False, timeout=20)
                        self.docker("rm", "-f", "-v", resource, timeout=20)
                    else:
                        self.docker("network", "rm", resource, timeout=20)
                except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    errors.append(f"{kind} cleanup: {type(error).__name__}")
        self.results["cleanup_errors"] = errors
        self.results["passed"] = self.results.get("passed", False) and not errors
        (self.output / "results.json").write_text(json.dumps(self.results, indent=2) + "\n")
        if errors:
            raise RuntimeError("disposable resource cleanup failed; inspect retained logs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    smoke = Smoke(args.image, args.output)
    try:
        smoke.prepare()
        smoke.admin()
        smoke.serving(public=True)
        smoke.rejection("forbidden-source", "forbidden", "public_corpus_forbidden")
        smoke.rejection("forbidden-rendering", "restricted_translation", "public_corpus_forbidden")
        smoke.rejection("missing-schema", "unmigrated", "publishing_audit_unavailable")
        assert smoke.sql("unmigrated", "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';") == "0"
        smoke.rejection("missing-database", "does_not_exist", "publishing_audit_unavailable")
        smoke.admission_order()
        smoke.admitted_serving()
        smoke.serving(public=False)
        smoke.rejection("missing-audit-permission", "audit_denied", "publishing_audit_unavailable")
        smoke.background_isolation()
        smoke.results["passed"] = True
    finally:
        smoke.close()
    print(json.dumps(smoke.results, indent=2))


if __name__ == "__main__":
    main()
