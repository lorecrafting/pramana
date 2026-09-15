"""FR-06 disposable storage experiment, not a production backend.

Run from any directory: python3 storage_spike.py. All writes use TemporaryDirectory.
Each transaction contains its command result, event, projection and effect intent.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile


def bundle(key):
    return dict(version=1, command=key, result="queued", event="admitted",
                state="queued", intent="launch:" + key)


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def read_journal(path):
    records = []
    for line in path.read_bytes().splitlines(keepends=True):
        if not line.endswith(b"\n"):
            raise ValueError("incomplete tail: explicit recovery required")
        frame = json.loads(line)
        value = frame["value"]
        if hashlib.sha256(encode(value)).hexdigest() != frame["sha256"]:
            raise ValueError("checksum")
        if value["version"] != 1:
            raise ValueError("unsupported version")
        records.append(value)
    return records


def connect(path):
    db = sqlite3.connect(path, timeout=0)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=FULL")
    db.execute("CREATE TABLE IF NOT EXISTS tx (id TEXT PRIMARY KEY, body TEXT NOT NULL)")
    db.commit()
    return db


def write(kind, path, key, boundary):
    value = bundle(key)
    if kind == "sqlite":
        db = connect(path)
        db.execute("BEGIN IMMEDIATE")
        prior = db.execute("SELECT body FROM tx WHERE id=?", (key,)).fetchone()
        if prior:
            assert json.loads(prior[0]) == value
        else:
            db.execute("INSERT INTO tx VALUES (?,?)", (key, encode(value).decode()))
        if boundary == "before_commit":
            os._exit(71)
        db.commit()
    else:
        with path.open("a+b") as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            prior = [v for v in read_journal(path) if v["command"] == key]
            if boundary == "before_commit":
                os._exit(71)
            if not prior:
                frame = encode(dict(value=value, sha256=hashlib.sha256(encode(value)).hexdigest())) + b"\n"
                if boundary == "short_write":
                    stream.write(frame[:len(frame)//2])
                    stream.flush()
                    os.fsync(stream.fileno())
                    os._exit(73)
                stream.write(frame)
                stream.flush()
                os.fsync(stream.fileno())
            else:
                assert prior == [value]
    if boundary == "after_commit":
        os._exit(72)


def read(kind, path):
    if kind == "journal":
        return read_journal(path)
    with connect(path) as db:
        values = [json.loads(row[0]) for row in db.execute("SELECT body FROM tx ORDER BY rowid")]
        if any(v["version"] != 1 for v in values):
            raise ValueError("unsupported version")
        return values


def child(kind, path, key, boundary, expected):
    result = subprocess.run([sys.executable, __file__, "child", kind, str(path), key, boundary],
                            capture_output=True, text=True)
    assert result.returncode == expected, result.stderr


def main():
    observations = []
    with tempfile.TemporaryDirectory(prefix="foundry-fr06-") as root:
        for kind in ("sqlite", "journal"):
            path = Path(root) / kind
            child(kind, path, "a", "before_commit", 71)
            assert read(kind, path) == []
            child(kind, path, "a", "after_commit", 72)
            assert read(kind, path) == [bundle("a")]
            child(kind, path, "a", "normal", 0)
            assert read(kind, path) == [bundle("a")]
            observations.append([kind, "process exit before commit, after commit before reply, same-key retry", "pass"])
            # Contend from a second OS process while the first owns its writer boundary.
            if kind == "sqlite":
                owner = connect(path)
                owner.execute("BEGIN IMMEDIATE")
                child(kind, path, "b", "normal", 1)
                owner.rollback()
                owner.close()
            else:
                with path.open("ab") as owner:
                    fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    child(kind, path, "b", "normal", 1)
            assert read(kind, path) == [bundle("a")]
            child(kind, path, "b", "normal", 0)
            assert read(kind, path) == [bundle("a"), bundle("b")]
            observations.append([kind, "two-process write exclusion and release", "pass"])

        path = Path(root) / "sqlite"
        db = connect(path)
        pages = db.execute("PRAGMA page_count").fetchone()[0]
        db.execute("PRAGMA max_page_count=" + str(pages))
        try:
            db.execute("INSERT INTO tx VALUES ('full', ?)", ("x" * 1000000,))
            db.commit()
            raise AssertionError("capacity failure expected")
        except sqlite3.DatabaseError as error:
            assert "full" in str(error), str(error)
            db.rollback()
        assert len(read("sqlite", path)) == 2
        observations.append(["sqlite", "engine capacity error (max_page_count), prior transactions intact", "pass"])
        backup = sqlite3.connect(str(Path(root) / "backup"))
        db.backup(backup)
        assert backup.execute("SELECT count(*) FROM tx").fetchone()[0] == 2
        backup.close()
        db.execute("BEGIN IMMEDIATE")
        db.execute("PRAGMA user_version=2")
        db.rollback()
        assert db.execute("PRAGMA user_version").fetchone()[0] == 0
        db.execute("UPDATE tx SET body=? WHERE id='a'", (encode(dict(bundle("a"), version=99)).decode(),))
        db.commit()
        try:
            read("sqlite", path)
            raise AssertionError("unknown version accepted")
        except ValueError:
            pass
        db.close()
        observations.append(["sqlite", "consistent backup, migration rollback, unknown application version refusal", "pass"])

        path = Path(root) / "journal"
        original = path.read_bytes()
        child("journal", path, "torn", "short_write", 73)
        try:
            read_journal(path)
            raise AssertionError("torn tail accepted")
        except ValueError:
            assert path.read_bytes().startswith(original)
        observations.append(["journal", "short append refuses startup; earlier bytes preserved", "pass"])
        # A repaired journal needs an explicit, checked snapshot publication protocol.
        snapshot = Path(root) / "snapshot"
        snapshot.write_bytes(original)
        pending = Path(root) / "snapshot.pending"
        pending.write_bytes(b"incomplete")
        assert read_journal(snapshot) == [bundle("a"), bundle("b")]
        damaged = original.replace(b'"queued"', b'"broken"', 1)
        corrupt = Path(root) / "corrupt"
        corrupt.write_bytes(damaged)
        try:
            read_journal(corrupt)
            raise AssertionError("interior corruption accepted")
        except ValueError:
            pass
        observations.append(["journal", "unpublished snapshot ignored; interior checksum failure refused", "pass"])
    print(json.dumps(dict(python=sys.version, sqlite=sqlite3.sqlite_version,
                         observations=observations), indent=2))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        write(sys.argv[2], Path(sys.argv[3]), sys.argv[4], sys.argv[5])
    else:
        main()
