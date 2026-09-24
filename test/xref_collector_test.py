"""Regression tests for the actual CI collector and documented caller loop.

Run from the Git root: python3 test/xref_collector_test.py
Requires Bash, Git and the pinned Elixir/Mix; only Python's standard library is used.
Every build is a dependency-free synthetic Mix project in a temporary directory.
The production checkout, application runtime and corpus are never started.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
# Execute the shipped shell, not a parallel implementation of its checks. A changed
# step boundary fails extraction rather than silently skipping the regression tests.
SECTION = WORKFLOW.split("      - name: Export compiler dependency reports\n", 1)[1]
COLLECTOR = textwrap.dedent(
    SECTION.split("        run: |\n", 1)[1].split(
        "\n      - name: Upload compiler dependency reports", 1
    )[0]
)
RUNBOOK = (ROOT / "docs/agents/DEPENDENCY_REVIEW.md").read_text(encoding="utf-8")
CALLERS = RUNBOOK.split("## Find callers across the application boundary\n", 1)[1].split(
    "```sh\n", 1
)[1].split("```", 1)[0]


class XrefCollectorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        for command in ("bash", "git", "mix", "elixir"):
            if shutil.which(command) is None:
                raise RuntimeError(f"Required compiler-test tool unavailable: {command}")

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="pramana-xref-test-")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.root = self.work / "checkout"
        self.project = self.root
        self.app = self.project / "apps/demo"
        self.report = self.work / "report"
        # Do not inherit a Git worktree/index or alternate Mix build location.
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_") and key not in (
                "MIX_BUILD_PATH", "MIX_DEPS_PATH", "MIX_EXS", "MIX_TARGET"
            )
        }
        self.env.update(MIX_ENV="test", GITHUB_RUN_ID="fixture", GITHUB_RUN_ATTEMPT="1",
                        XREF_REPORT_DIR=str(self.report), GIT_CONFIG_NOSYSTEM="1",
                        GIT_CONFIG_GLOBAL=os.devnull)

    @staticmethod
    def put(path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def command(self, args: list[str], cwd: Path, *, check: bool = True) -> subprocess.CompletedProcess:
        result = subprocess.run(args, cwd=cwd, env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout)
        return result

    def fixture(self, *, paths: str = '["lib"]', empty: bool = False) -> None:
        self.put(self.project / "mix.exs", '''defmodule Fixture.Umbrella do
  use Mix.Project
  def project, do: [apps_path: "apps", version: "0.1.0"]
end
''')
        self.put(self.app / "mix.exs", f'''defmodule Fixture.Demo do
  use Mix.Project
  def project do
    [app: :demo, version: "0.1.0", build_path: "../../_build",
     deps_path: "../../deps", lockfile: "../../mix.lock", elixirc_paths: {paths}]
  end
  # Undefined on purpose: accidental application startup fails the test.
  def application, do: [mod: {{Fixture.DoNotStart, []}}]
end
''')
        if not empty:
            self.put(self.app / "lib/target.ex", '''defmodule Pramana.Release do
  def current_id, do: "fixture"
end
''')
            self.put(self.app / "lib/caller.ex", '''defmodule Fixture.Caller do
  def run, do: Pramana.Release.current_id()
end
''')
        self.put(self.root / ".gitignore", "**/_build/\n**/deps/\n**/generated/\n")
        self.put(self.root / "mise.toml", '[tools]\nelixir = "1.20.3-otp-29"\n')
        self.put(self.root / ".github/workflows/ci.yml", WORKFLOW)

    def compile(self) -> None:
        for args in (["git", "init", "-q"],
                     ["git", "config", "user.name", "xref-fixture"],
                     ["git", "config", "user.email", "fixture@example.invalid"],
                     ["git", "add", "--", "."],
                     ["git", "commit", "-qm", "synthetic compiler fixture"]):
            self.command(args, self.root)
        self.env["GITHUB_SHA"] = self.command(["git", "rev-parse", "HEAD"], self.root).stdout.strip()
        self.command(["mix", "compile", "--force", "--warnings-as-errors"], self.project)
        self.assertEqual(self.command(["git", "status", "--porcelain"], self.root).stdout, "")

    def collect(self) -> subprocess.CompletedProcess:
        return self.command(["bash", "-c", COLLECTOR], self.project, check=False)

    def graph(self) -> dict:
        return json.loads((self.report / "demo/graph.json").read_text(encoding="utf-8"))

    def test_tracked_sources_have_real_edges_and_hash_coverage(self) -> None:
        self.fixture()
        self.compile()
        result = self.collect()
        self.assertEqual(result.returncode, 0, result.stdout)
        graph = self.graph()
        self.assertEqual(graph["lib/caller.ex"]["lib/target.ex"], "runtime")
        inventory = (self.report / "source-files.paths0").read_bytes().split(b"\0")
        hashes = (self.report / "source-files.sha256").read_text(encoding="utf-8")
        for source in graph:
            relative = f"apps/demo/{source}"
            self.assertIn(relative.encode(), inventory)
            digest = hashlib.sha256((self.root / relative).read_bytes()).hexdigest()
            self.assertIn(f"{digest}  {relative}\n", hashes)
        metadata = json.loads((self.report / "metadata.json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["source_sha"], self.env["GITHUB_SHA"])
        self.assertEqual(metadata["schema_version"], 2)
        self.assertEqual(metadata["scopes"][0]["status"], "collected")
        self.assertEqual(self.command(["git", "status", "--porcelain"], self.root).stdout, "")

    def test_ignored_input_changed_after_compile_is_rejected(self) -> None:
        self.fixture(paths='["lib", "generated"]')
        source = self.app / "generated/generated.ex"
        self.put(source, "defmodule Fixture.Generated do\n  def run, do: Pramana.Release.current_id()\nend\n")
        self.compile()
        self.put(source, "defmodule Fixture.Generated do\n  def run, do: :changed_after_compile\nend\n")
        self.assertEqual(self.command(["git", "status", "--porcelain"], self.root).stdout, "")
        result = self.collect()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Uninventoried compiler source", result.stdout)
        self.assertIn("generated/generated.ex", result.stdout)
        # Confirm this is the old dependency, not a fixture that never had a call.
        self.assertEqual(self.graph()["generated/generated.ex"]["lib/target.ex"], "runtime")
        self.assertFalse((self.report / "metadata.json").exists())

    def test_tracked_symlink_cannot_stand_for_target_bytes(self) -> None:
        self.fixture()
        external = self.work / "outside.ex"
        self.put(external, "defmodule Fixture.Linked do\n  def run, do: Pramana.Release.current_id()\nend\n")
        (self.app / "lib/linked.ex").symlink_to(external)
        self.compile()
        result = self.collect()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("symlinked compiler source", result.stdout)
        self.assertFalse((self.report / "metadata.json").exists())

    def test_external_source_is_rejected_even_when_tracked(self) -> None:
        self.fixture(paths='["lib", Path.expand("../../outside", __DIR__)]')
        self.put(self.root / "outside/external.ex",
                 "defmodule Fixture.External do\n  def run, do: Pramana.Release.current_id()\nend\n")
        self.compile()
        result = self.collect()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Out-of-scope compiler source", result.stdout)
        self.assertFalse((self.report / "metadata.json").exists())

    def test_valid_no_source_application_is_explicitly_not_applicable(self) -> None:
        self.fixture(empty=True)
        self.compile()
        result = self.collect()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.graph(), {})
        metadata = json.loads((self.report / "metadata.json").read_text(encoding="utf-8"))
        scope = metadata["scopes"][0]
        self.assertEqual((scope["status"], scope["nodes"], scope["edges"]),
                         ("no_elixir_sources", 0, 0))
        self.assertEqual(json.loads((self.report / scope["elixir_sources"]).read_text()), [])

    def test_empty_graph_with_configured_source_is_not_called_no_source(self) -> None:
        self.fixture(empty=True)
        self.put(self.app / "lib/no_module.ex", ":ok\n")
        self.compile()
        result = self.collect()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Empty graph despite configured Elixir sources", result.stdout)
        self.assertFalse((self.report / "metadata.json").exists())

    def test_missing_manifest_is_unavailable_in_collector_and_runbook(self) -> None:
        self.fixture()
        self.compile()
        before = self.command(["bash", "-c", CALLERS], self.root)
        self.assertIn("lib/caller.ex (runtime)", before.stdout)
        (self.project / "_build/test/lib/demo/.mix/compile.elixir").unlink()
        for result in (self.collect(), self.command(["bash", "-c", CALLERS], self.root, check=False)):
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("Compiler evidence unavailable", result.stdout)
        self.assertFalse((self.report / "metadata.json").exists())

    def test_wrong_revision_environment_and_dirty_source_fail_before_export(self) -> None:
        self.fixture()
        self.compile()
        for key, bad_value in (("MIX_ENV", "dev"), ("GITHUB_SHA", "0" * 40)):
            with self.subTest(key=key):
                original = self.env[key]
                self.env[key] = bad_value
                try:
                    self.assertNotEqual(self.collect().returncode, 0)
                    self.assertFalse(self.report.exists())
                finally:
                    self.env[key] = original
        self.put(self.app / "lib/caller.ex", "# uncompiled edit\n")
        self.assertNotEqual(self.collect().returncode, 0)
        self.assertFalse(self.report.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
