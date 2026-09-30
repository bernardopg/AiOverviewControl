# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_codex_native() {
  if [ ! -x "$CODEX_SCRIPT" ]; then
    json_error codex codex-app-server 127 runtime "Codex usage helper is missing or not executable."
    return 0
  fi
  "$CODEX_SCRIPT"
}
