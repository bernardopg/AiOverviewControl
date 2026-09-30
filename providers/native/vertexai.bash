# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_vertexai_native() {
  local project="${GOOGLE_CLOUD_PROJECT:-${GCLOUD_PROJECT:-${VERTEXAI_PROJECT:-}}}"
  if command -v gcloud >/dev/null 2>&1 && gcloud auth print-access-token >/dev/null 2>&1; then
    local account
    account="$(gcloud config get-value account 2>/dev/null || echo "GCP account")"
    [ -n "$account" ] && [ "$account" != "(unset)" ] || account="GCP account"
    local label="Authenticated"
    [ -n "$project" ] && label="Project: ${project}"
    json_note_usage vertexai vertexai-gcloud "$account" "gcloud-oauth" "$label" "console.cloud.google.com/vertex-ai"
    return 0
  fi
  json_error vertexai vertexai-gcloud 2 provider "gcloud not authenticated. Run: gcloud auth login && gcloud auth application-default login"
}
