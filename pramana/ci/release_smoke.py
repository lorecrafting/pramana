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

    def options(self, case, database, public=True):
        name = self.prefix + "-" + case
        return name, ["--name", name, "--label", self.label, "--network", self.network,
                      "-e", f"DATABASE_URL=ecto://postgres:postgres@db/{database}",
                      "-e", f"SECRET_KEY_BASE={SECRET}", "-e", "APP_HOST=localhost",
                      "-e", "PORT=4000", "-e", "POOL_SIZE=2",
                      "-e", "PRAMANA_EMBEDDING=0", "-e", f"PRAMANA_PUBLIC={'1' if public else '0'}"]

    def evaluate(self, case, database, code, public=False, serving=None):
        _, opts = self.options(case, database, public)
        if serving is not None:
            opts += ["-e", f"PHX_SERVER={'true' if serving else 'false'}"]
        return self.docker("run", *opts, "--entrypoint", "/app/bin/pramana", self.image, "eval", code, timeout=90)

    def launch(self, case, database, public=True, plain=False):
        name, opts = self.options(case, database, public)
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
        self.docker("stop", "-t", "10", name)
        self.results["cases"].append({"case": case, "passed": True, "assets": sorted(assets)})

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
        smoke.serving(public=False)
        smoke.results["passed"] = True
    finally:
        smoke.close()
    print(json.dumps(smoke.results, indent=2))


if __name__ == "__main__":
    main()
