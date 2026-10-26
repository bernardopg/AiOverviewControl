#!/usr/bin/env python3
"""Fuzz the provider adapters with arbitrary HTTP responses.

Each input picks an API-key provider, an HTTP status and a response body. A
fake `curl` on PATH serves that body to providers/get-provider-usage, and the
harness checks the adapter contract the widget relies on:

- the dispatcher exits 0 within the timeout;
- stdout is a JSON array with exactly one object for the requested provider;
- that object carries either a `usage` object or an `error` object;
- the fake credential never appears in the output.

Run: python3 tests/fuzz/fuzz_provider_responses.py -max_total_time=60
ClusterFuzzLite runs the same harness packaged by .clusterfuzzlite/build.sh.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import atheris

ROOT = Path(__file__).resolve().parents[2]
# A PyInstaller bundle (ClusterFuzzLite) carries the adapters and a static jq
# under aioc/ instead of a repository checkout.
BUNDLE = Path(getattr(sys, "_MEIPASS", "")) / "aioc" if getattr(sys, "frozen", False) else None
SECRET = "sk-fuzz-0000-credential"
# provider id -> credential variables its native adapter reads.
PROVIDERS = {
    "ai21": ["AI21_API_KEY"],
    "byteplus": ["ARK_API_KEY"],
    "cline": ["CLINE_API_KEY"],
    "cloudflare": ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"],
    "cohere": ["COHERE_API_KEY"],
    "deepseek": ["DEEPSEEK_API_KEY"],
    "fireworks": ["FIREWORKS_API_KEY", "FIREWORKS_ACCOUNT_ID"],
    "gemini": ["GEMINI_API_KEY"],
    "glm": ["GLM_API_KEY"],
    "groq": ["GROQ_API_KEY"],
    "kilo": ["KILO_API_KEY"],
    "kimi": ["MOONSHOT_API_KEY"],
    "minimax": ["MINIMAX_API_KEY"],
    "mistral": ["MISTRAL_API_KEY"],
    "neuralwatt": ["NEURALWATT_API_KEY"],
    "ollama-cloud": ["OLLAMA_API_KEY"],
    "anthropic": ["ANTHROPIC_ADMIN_KEY"],
    "openai": ["OPENAI_ADMIN_KEY"],
    "vercel": ["AI_GATEWAY_API_KEY"],
    "nvidia": ["NVIDIA_API_KEY"],
    "openrouter": ["OPENROUTER_API_KEY"],
    "qwen": ["DASHSCOPE_API_KEY"],
    "replicate": ["REPLICATE_API_TOKEN"],
    "together": ["TOGETHER_API_KEY"],
    "zai": ["ZAI_API_KEY"],
}
NAMES = sorted(PROVIDERS)
STATUSES = [200, 200, 200, 200, 400, 401, 403, 404, 429, 500, 502, 0]

FAKE_CURL = r"""#!/usr/bin/env bash
# Serve the fuzzed body for every request, like curl: -o writes the body to a
# file, -D writes headers, -w prints the status code.
out="" headers="" write=0
args=("$@")
# A credential on the command line is readable by every local user (ps,
# /proc/<pid>/cmdline); adapters must pass it through --config instead.
case " $* " in *"$FUZZ_SECRET"*) : > "$FUZZ_DIR/argv-leak" ;; esac
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o|--output) out="${args[$((i + 1))]}" ;;
    -D|--dump-header) headers="${args[$((i + 1))]}" ;;
    -w|--write-out) write=1 ;;
  esac
done
status="$(cat "$FUZZ_DIR/status")"
if [ -n "$headers" ]; then
  printf 'HTTP/2 %s\r\ncontent-type: application/json\r\n\r\n' "$status" > "$headers"
fi
if [ -n "$out" ]; then cat "$FUZZ_DIR/body" > "$out"; else cat "$FUZZ_DIR/body"; fi
if [ "$write" = 1 ]; then printf '%s' "$status"; fi
exit 0
"""

WORK = Path(tempfile.mkdtemp(prefix="aioc-fuzz-"))
(WORK / "bin").mkdir()
(WORK / "bin" / "curl").write_text(FAKE_CURL)
(WORK / "bin" / "curl").chmod(0o755)
if BUNDLE:
    # Bundled data files lose their mode bits; restore them in the work dir.
    shutil.copytree(BUNDLE / "providers", WORK / "providers")
    for script in (WORK / "providers").rglob("*"):
        if script.is_file():
            script.chmod(0o755)
    shutil.copy(BUNDLE / "bin" / "jq-static", WORK / "bin" / "jq")
    (WORK / "bin" / "jq").chmod(0o755)
    DISPATCHER = WORK / "providers" / "get-provider-usage"
else:
    DISPATCHER = ROOT / "providers" / "get-provider-usage"
BASE_ENV = {
    "PATH": f"{WORK / 'bin'}:/usr/local/bin:/usr/bin:/bin",
    "HOME": str(WORK / "home"),
    "XDG_CACHE_HOME": str(WORK / "cache"),
    "XDG_CONFIG_HOME": str(WORK / "config"),
    "FUZZ_DIR": str(WORK),
    "FUZZ_SECRET": SECRET,
    "LANG": "C.UTF-8",
    # Keep the optional third-party calls out of the fuzzed path.
    "AIOC_NO_LITELLM": "1",
    "AIOC_NO_DOH_FALLBACK": "1",
    "AIOC_NO_FX": "1",
}


class ContractViolation(Exception):
    pass


def run(provider, status, body):
    (WORK / "status").write_text(str(status))
    (WORK / "body").write_bytes(body)
    (WORK / "argv-leak").unlink(missing_ok=True)
    shutil.rmtree(WORK / "cache", ignore_errors=True)
    env = dict(BASE_ENV)
    for name in PROVIDERS[provider]:
        env[name] = SECRET if name.endswith(("KEY", "TOKEN")) else "acct-fuzz"
    try:
        proc = subprocess.run(
            ["bash", str(DISPATCHER), provider],
            env=env, cwd=WORK, capture_output=True, timeout=30, check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise ContractViolation(f"{provider}: no answer within 30s") from error
    return proc


@atheris.instrument_func
def check(provider, proc):
    """Validate the adapter contract; branches here guide the fuzzer."""
    if proc.returncode != 0:
        raise ContractViolation(f"{provider}: exit {proc.returncode}: {proc.stderr[-300:]!r}")
    if SECRET.encode() in proc.stdout:
        raise ContractViolation(f"{provider}: credential leaked into output")
    if (WORK / "argv-leak").exists():
        raise ContractViolation(f"{provider}: credential passed to curl on the command line")
    try:
        result = json.loads(proc.stdout)
    except ValueError as error:
        raise ContractViolation(f"{provider}: output is not JSON: {proc.stdout[:300]!r}") from error
    if not isinstance(result, list) or len(result) != 1 or not isinstance(result[0], dict):
        raise ContractViolation(f"{provider}: expected one result object: {result!r}"[:400])
    entry = result[0]
    if entry.get("provider") != provider:
        raise ContractViolation(f"{provider}: wrong provider id {entry.get('provider')!r}")
    usage, error = entry.get("usage"), entry.get("error")
    if isinstance(error, dict):
        if not isinstance(error.get("message"), str):
            raise ContractViolation(f"{provider}: error without a message: {error!r}"[:400])
        return "error:" + str(error.get("kind"))
    if not isinstance(usage, dict):
        raise ContractViolation(f"{provider}: neither usage nor error: {entry!r}"[:400])
    for window in ("primary", "secondary", "tertiary"):
        value = usage.get(window)
        if value is not None and not isinstance(value, dict):
            raise ContractViolation(f"{provider}: usage.{window} is {type(value).__name__}")
        if isinstance(value, dict) and value.get("usedPercent") is not None:
            if not isinstance(value["usedPercent"], (int, float)):
                raise ContractViolation(f"{provider}: usage.{window}.usedPercent is not a number")
    return "usage"


def test_one_input(data):
    fdp = atheris.FuzzedDataProvider(data)
    provider = NAMES[fdp.ConsumeIntInRange(0, len(NAMES) - 1)]
    status = STATUSES[fdp.ConsumeIntInRange(0, len(STATUSES) - 1)]
    body = fdp.ConsumeBytes(fdp.remaining_bytes())
    check(provider, run(provider, status, body))


def seed_corpus(directory):
    """Seed with every JSON fixture, prefixed by provider and status bytes."""
    directory.mkdir(parents=True, exist_ok=True)
    if any(directory.iterdir()):
        return
    fixtures = sorted((ROOT / "tests" / "fixtures").rglob("*.json"))
    for index, fixture in enumerate(fixtures):
        prefix = bytes([index % len(NAMES), 0])
        (directory / fixture.name).write_bytes(prefix + fixture.read_bytes())


def main():
    seeds = next((arg.split("=", 1)[1] for arg in sys.argv if arg.startswith("--write-seeds=")), None)
    if seeds:
        seed_corpus(Path(seeds))
        shutil.rmtree(WORK, ignore_errors=True)
        return
    args = [arg for arg in sys.argv if not arg.startswith("--corpus=")]
    corpus = next((arg.split("=", 1)[1] for arg in sys.argv if arg.startswith("--corpus=")), None)
    corpus_dir = Path(corpus) if corpus else WORK / "corpus"
    seed_corpus(corpus_dir)
    try:
        atheris.Setup(args + [str(corpus_dir)], test_one_input)
        atheris.Fuzz()
    finally:
        shutil.rmtree(WORK, ignore_errors=True)


if __name__ == "__main__":
    main()
