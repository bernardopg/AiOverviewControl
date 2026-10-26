#!/usr/bin/env python3
"""Fuzz the local readers with arbitrary file contents.

Each input picks a target and supplies the bytes of one file the target
reads from disk: a Claude Code transcript or credentials file, a Codex or pi
session log, an OpenCode message row (SQLite), a Grok CLI auth.json or the
Cline CLI providers.json. The harness checks the contract the widget relies
on:

- the reader exits 0 within the timeout;
- get-claude-usage prints only KEY=VALUE lines with the keys the dispatcher
  reads, and the JSON readers print one JSON object;
- the fake credential never appears in the output;
- no credential reaches curl's command line.

Run: python3 tests/fuzz/fuzz_local_readers.py -max_total_time=60
ClusterFuzzLite runs the same harness packaged by .clusterfuzzlite/build.sh.
"""
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import atheris

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = Path(getattr(sys, "_MEIPASS", "")) / "aioc" if getattr(sys, "frozen", False) else None
SECRET = "sk-fuzz-local-credential"
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

FAKE_CURL = r"""#!/usr/bin/env bash
# Every request is rejected; flag a credential on the command line.
case " $* " in *"$FUZZ_SECRET"*) : > "$FUZZ_DIR/argv-leak" ;; esac
out="" prev=""
for arg in "$@"; do [ "$prev" != -o ] || out="$arg"; prev="$arg"; done
[ -z "$out" ] || printf '{}' > "$out"
for arg in "$@"; do [ "$arg" != -w ] || { printf 401; break; }; done
exit 0
"""

WORK = Path(tempfile.mkdtemp(prefix="aioc-fuzz-local-"))
(WORK / "bin").mkdir()
(WORK / "bin" / "curl").write_text(FAKE_CURL)
(WORK / "bin" / "curl").chmod(0o755)
if BUNDLE:
    # Bundled data files lose their mode bits; restore them in the work dir.
    for name in ("providers", "scripts"):
        shutil.copytree(BUNDLE / name, WORK / name)
    for script in (WORK / "providers").rglob("*"):
        if script.is_file():
            script.chmod(0o755)
    shutil.copy(BUNDLE / "bin" / "jq-static", WORK / "bin" / "jq")
    (WORK / "bin" / "jq").chmod(0o755)
    PROVIDERS = WORK / "providers"
else:
    PROVIDERS = ROOT / "providers"
HOME = WORK / "home"
BASE_ENV = {
    "PATH": f"{WORK / 'bin'}:/usr/local/bin:/usr/bin:/bin",
    "HOME": str(HOME),
    "XDG_CACHE_HOME": str(WORK / "cache"),
    "XDG_CONFIG_HOME": str(WORK / "config"),
    "XDG_DATA_HOME": str(WORK / "data"),
    "FUZZ_DIR": str(WORK),
    "FUZZ_SECRET": SECRET,
    "LANG": "C.UTF-8",
    "TZ": "UTC",
    "AIOC_NO_LITELLM": "1",
    "AIOC_NO_DOH_FALLBACK": "1",
}
# KEY=VALUE fields the dispatcher's Claude adapter reads.
CLAUDE_KEYS = {"SUBSCRIPTION_TYPE", "FIVE_HOUR_UTIL", "WEEK_TOKENS", "DAILY", "USAGE_ERROR_KIND"}


class ContractViolation(Exception):
    pass


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def opencode_db(data):
    """An OpenCode v2 database whose one assistant message carries `data`."""
    db = WORK / "data" / "opencode" / "opencode.db"
    db.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db) as conn:
        conn.executescript(
            "CREATE TABLE session_v2(id TEXT PRIMARY KEY, directory TEXT);"
            "CREATE TABLE session_message(id TEXT PRIMARY KEY, session_id TEXT, type TEXT,"
            " time_created INTEGER, data TEXT);"
            "INSERT INTO session_v2 VALUES('s', '/project');")
        conn.execute("INSERT INTO session_message VALUES('m', 's', 'assistant', unixepoch() * 1000, ?)",
                     (data.decode("utf-8", "replace"),))


# target -> (setup(data), command, output kind)
TARGETS = {
    "claude-transcript": (
        lambda data: write(HOME / ".claude" / "projects" / "-project" / "s.jsonl", data),
        ["get-claude-usage"], "keyvalue"),
    "claude-credentials": (
        lambda data: write(HOME / ".claude" / ".credentials.json", data),
        ["get-claude-usage"], "keyvalue"),
    "codex-session": (
        lambda data: write(HOME / ".codex" / "sessions" / "2026" / "s.jsonl", data),
        ["get-local-analytics", "codex"], "json"),
    "pi-session": (
        lambda data: write(HOME / ".pi" / "agent" / "sessions" / "p" / "s.jsonl", data),
        ["get-pi-analytics"], "json"),
    "opencode-message": (opencode_db, ["get-local-analytics", "opencode"], "json"),
    "grok-auth": (
        lambda data: write(HOME / ".grok" / "auth.json", data),
        ["get-provider-usage", "xai"], "dispatcher"),
    "cline-providers": (
        lambda data: write(HOME / ".cline" / "data" / "settings" / "providers.json", data),
        ["get-provider-usage", "cline"], "dispatcher"),
}
NAMES = sorted(TARGETS)

# Well-formed examples that give the fuzzer each format's structure.
SEEDS = {
    "claude-transcript": json.dumps({
        "type": "assistant", "timestamp": NOW, "sessionId": "s1", "cwd": "/project",
        "message": {"model": "claude-sonnet-4", "usage": {
            "input_tokens": 100, "output_tokens": 50,
            "cache_read_input_tokens": 10, "cache_creation_input_tokens": 5}}}) + "\n",
    "claude-credentials": json.dumps({"claudeAiOauth": {
        "accessToken": SECRET, "refreshToken": SECRET, "expiresAt": 9999999999999,
        "subscriptionType": "pro", "rateLimitTier": "default_claude_pro"}}),
    "codex-session": "\n".join(json.dumps(line) for line in [
        {"type": "session_meta", "payload": {"cwd": "/project", "model_provider": "openai"}},
        {"type": "turn_context", "payload": {"model": "gpt-5"}},
        {"timestamp": NOW, "type": "event_msg", "payload": {"type": "token_count", "info": {
            "total_token_usage": {"total_tokens": 100, "input_tokens": 80, "output_tokens": 20,
                                  "cached_input_tokens": 10, "reasoning_output_tokens": 5}}}},
    ]) + "\n",
    "pi-session": "\n".join(json.dumps(line) for line in [
        {"type": "session", "timestamp": NOW, "cwd": "/project"},
        {"type": "message", "timestamp": NOW, "message": {
            "role": "assistant", "provider": "anthropic", "model": "claude-sonnet-4",
            "usage": {"input": 10, "output": 5, "cost": {"total": 0.001}}}},
    ]) + "\n",
    "opencode-message": json.dumps({
        "model": {"id": "gpt-5", "providerID": "openai"}, "cost": 0.001,
        "tokens": {"input": 10, "output": 5, "reasoning": 1, "cache": {"read": 2, "write": 0}}}),
    "grok-auth": json.dumps({"default": {
        "key": SECRET, "refresh_token": SECRET, "expires_at": "2099-01-01T00:00:00Z",
        "email": "dev@example.test", "auth_mode": "grok-login"}}),
    "cline-providers": json.dumps({"providers": {"cline": {"settings": {
        "auth": {"accessToken": SECRET, "expiresAt": 4102444800000}}}}}),
}


def run(target, data):
    shutil.rmtree(HOME, ignore_errors=True)
    shutil.rmtree(WORK / "cache", ignore_errors=True)
    shutil.rmtree(WORK / "data", ignore_errors=True)
    (WORK / "argv-leak").unlink(missing_ok=True)
    HOME.mkdir()
    setup, command, _ = TARGETS[target]
    setup(data)
    try:
        return subprocess.run(
            ["bash", str(PROVIDERS / command[0]), *command[1:]],
            env=BASE_ENV, cwd=WORK, capture_output=True, timeout=30, check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise ContractViolation(f"{target}: no answer within 30s") from error


@atheris.instrument_func
def check(target, proc):
    """Validate the reader contract; branches here guide the fuzzer."""
    kind = TARGETS[target][2]
    if proc.returncode != 0:
        raise ContractViolation(f"{target}: exit {proc.returncode}: {proc.stderr[-300:]!r}")
    if SECRET.encode() in proc.stdout:
        raise ContractViolation(f"{target}: credential leaked into output")
    if (WORK / "argv-leak").exists():
        raise ContractViolation(f"{target}: credential passed to curl on the command line")
    text = proc.stdout.decode("utf-8", "replace")
    if kind == "keyvalue":
        keys = set()
        for line in text.splitlines():
            match = re.match(r"^([A-Z][A-Z0-9_]*)=", line)
            if not match:
                raise ContractViolation(f"{target}: not a KEY=VALUE line: {line[:200]!r}")
            keys.add(match.group(1))
        if not CLAUDE_KEYS <= keys:
            raise ContractViolation(f"{target}: missing keys {sorted(CLAUDE_KEYS - keys)}")
        return "keyvalue"
    try:
        result = json.loads(text)
    except ValueError as error:
        raise ContractViolation(f"{target}: output is not JSON: {text[:300]!r}") from error
    if kind == "dispatcher":
        if not isinstance(result, list) or len(result) != 1 or not isinstance(result[0], dict):
            raise ContractViolation(f"{target}: expected one result object: {result!r}"[:400])
        entry = result[0]
        if not isinstance(entry.get("usage"), dict) and not isinstance(entry.get("error"), dict):
            raise ContractViolation(f"{target}: neither usage nor error: {entry!r}"[:400])
        return "dispatcher"
    if not isinstance(result, dict):
        raise ContractViolation(f"{target}: expected a JSON object: {result!r}"[:400])
    if "error" not in result and not isinstance(result.get("today"), dict):
        raise ContractViolation(f"{target}: neither totals nor an error: {result!r}"[:400])
    return "json"


def test_one_input(data):
    fdp = atheris.FuzzedDataProvider(data)
    target = NAMES[fdp.ConsumeIntInRange(0, len(NAMES) - 1)]
    check(target, run(target, fdp.ConsumeBytes(fdp.remaining_bytes())))


def seed_corpus(directory):
    """One seed per target, prefixed by the byte that selects it."""
    directory.mkdir(parents=True, exist_ok=True)
    if any(directory.iterdir()):
        return
    for index, name in enumerate(NAMES):
        (directory / f"{name}.seed").write_bytes(bytes([index]) + SEEDS[name].encode())


def main():
    seeds = next((arg.split("=", 1)[1] for arg in sys.argv if arg.startswith("--write-seeds=")), None)
    if seeds:
        seed_corpus(Path(seeds))
        shutil.rmtree(WORK, ignore_errors=True)
        return
    args = [arg for arg in sys.argv if not arg.startswith("--corpus=")]
    corpus = next((arg.split("=", 1)[1] for arg in sys.argv if arg.startswith("--corpus=")), None)
    corpus_dir = Path(corpus) if corpus else WORK / "corpus"
    # ClusterFuzzLite ships the seeds as a corpus zip, and its build check
    # expects only the runs it asks for, so a bundle starts empty.
    if not BUNDLE:
        seed_corpus(corpus_dir)
    corpus_dir.mkdir(parents=True, exist_ok=True)
    try:
        atheris.Setup(args + [str(corpus_dir)], test_one_input)
        atheris.Fuzz()
    finally:
        shutil.rmtree(WORK, ignore_errors=True)


if __name__ == "__main__":
    main()
