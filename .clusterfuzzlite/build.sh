#!/bin/bash -eu
# Package the fuzzer with the provider adapters and a static jq; the harness
# copies them into its work directory at start-up (see BUNDLE in the harness).
compile_python_fuzzer tests/fuzz/fuzz_provider_responses.py \
  --add-data "providers:aioc/providers" \
  --add-binary "/usr/local/bin/jq-static:aioc/bin"

# Seed corpus: every JSON fixture, prefixed with provider and status bytes.
seeds="$WORK/seeds"
mkdir -p "$seeds"
python3 tests/fuzz/fuzz_provider_responses.py --write-seeds="$seeds"
(cd "$seeds" && zip -q -r "$OUT/fuzz_provider_responses_seed_corpus.zip" .)

# Local readers: the same adapters plus the shared jq programs under scripts/.
compile_python_fuzzer tests/fuzz/fuzz_local_readers.py \
  --add-data "providers:aioc/providers" \
  --add-data "scripts:aioc/scripts" \
  --add-binary "/usr/local/bin/jq-static:aioc/bin"
local_seeds="$WORK/local-seeds"
mkdir -p "$local_seeds"
python3 tests/fuzz/fuzz_local_readers.py --write-seeds="$local_seeds"
(cd "$local_seeds" && zip -q -r "$OUT/fuzz_local_readers_seed_corpus.zip" .)
