#!/usr/bin/env bash
# Offline contract: independent identities, credentials, quota and local caches.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" AIOC_NO_LITELLM=1
export PATH="$TMP/bin:$PATH"
unset CLAUDE_CONFIG_DIR
mkdir -p "$TMP/bin" "$HOME/.claude" "$TMP/work account; literal" "$TMP/personal" "$TMP/expired"
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '2.0.0\n'
SH
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
args="$*"
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out="$2"; shift; fi
  shift
done
case "$args" in
  *api.anthropic.com/api/oauth/usage*)
    case "$args" in
      *fixture-work*) body='{"five_hour":{"utilization":73},"seven_day":{"utilization":81}}' ;;
      *fixture-personal*) body='{"five_hour":{"utilization":12},"seven_day":{"utilization":22},"limits":[{"kind":"session","percent":12},{"kind":"weekly_all","percent":22},{"kind":"weekly_scoped","percent":40,"is_active":true,"scope":{"model":{"display_name":"Fable"}}}]}' ;;
      *fixture-expired*) printf '{"error":"expired"}' > "$out"; printf 401; exit 0 ;;
      *fixture-default*) body='{"five_hour":{"utilization":35}}' ;;
      *) exit 1 ;;
    esac
    printf '%s' "$body" > "$out"
    printf 200 ;;
  *) printf 'unexpected network request\n' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/"*
# Fixtures differ per profile so a shared pipeline cannot pass by accident.
# No cwd may contain the credential marker used by the leak check below.
for profile in default personal work expired; do
  model=claude-sonnet-4 cwd=/srv/default tokens=100 tier=""
  case "$profile" in
    default) dir="$HOME/.claude" ;;
    work) dir="$TMP/work account; literal" model=claude-opus-4 cwd=/work/app tokens=900 tier=default_claude_max_20x ;;
    personal) dir="$TMP/personal" cwd=/home/me ;;
    expired) dir="$TMP/expired" cwd=/srv/expired tokens=300 ;;
  esac
  jq -n --arg token "fixture-$profile" --arg tier "$tier" \
    '{claudeAiOauth:({accessToken:$token,subscriptionType:"pro"} + (if $tier == "" then {} else {rateLimitTier:$tier} end))}' > "$dir/.credentials.json"
  mkdir -p "$dir/projects/test"
  jq -nc --arg time "$(date -Iseconds)" --argjson tokens "$tokens" --arg model "$model" --arg cwd "$cwd" \
    '{type:"assistant",timestamp:$time,sessionId:"s1",cwd:$cwd,message:{model:$model,usage:{input_tokens:$tokens,output_tokens:0}}}' > "$dir/projects/test/session.jsonl"
done
export AIOC_CLAUDE_PROFILES
AIOC_CLAUDE_PROFILES="$(jq -nc --arg work "$TMP/work account; literal" --arg personal "$TMP/personal" '{"claude-work":{name:"Work",configDir:$work},"claude-personal":{name:"Personal",configDir:$personal}}')"
# An old flat snapshot must not be trusted for any profile, including default.
mkdir -p "$XDG_CACHE_HOME/AiOverviewControl"
printf '{"five_hour":{"utilization":99}}' > "$XDG_CACHE_HOME/AiOverviewControl/claude-usage-cache.json"
result="$(bash "$ROOT/providers/get-provider-usage" claude,claude-work,claude-personal)"
printf '%s' "$result" | jq -e '
  length == 3 and .[0].provider == "claude" and .[0].usage.primary.usedPercent == 35
  and .[1].provider == "claude-work" and .[1].usage.identity.providerID == "claude-work"
  and .[1].usage.primary.usedPercent == 73 and .[1].usage.secondary.usedPercent == 81
  and .[2].provider == "claude-personal" and .[2].usage.primary.usedPercent == 12
  and .[1].analytics.weekTokens == 900 and .[2].analytics.weekTokens == 100
  and .[1].analytics.weekModels == "opus:900" and .[2].analytics.weekModels == "sonnet:100"
  and .[1].analytics.weekProjects == "/work/app:900" and .[2].analytics.weekProjects == "/home/me:100"
  and .[1].analytics.rateLimitTier == "default_claude_max_20x" and .[2].analytics.rateLimitTier == "unknown"
  and ([.[].analytics.dailyTokens | length] == [7,7,7])
  and .[2].analytics.scopedModel == "Fable" and .[2].usage.tertiary.usedPercent == 40
  and .[1].analytics.scopedModel == ""
' >/dev/null
[ "$(find "$XDG_CACHE_HOME/AiOverviewControl/claude-profiles" -name claude-usage-cache.json | wc -l)" -eq 3 ]
# Each config dir aggregates into its own transcript cache.
[ "$(find "$XDG_CACHE_HOME/AiOverviewControl/claude-profiles" -name claude-transcripts.tsv | wc -l)" -eq 3 ]
[ "$(find "$XDG_CACHE_HOME/AiOverviewControl/claude-profiles" -name claude-transcripts.tsv -exec sha256sum {} + | cut -d ' ' -f 1 | sort -u | wc -l)" -eq 3 ]
# Rejected OAuth keeps the local analytics but never stale quota.
expired="$(AIOC_CLAUDE_PROFILES="$(jq -nc --arg dir "$TMP/expired" '{"claude-expired":{name:"Expired",configDir:$dir}}')" \
  bash "$ROOT/providers/get-provider-usage" claude-expired)"
printf '%s' "$expired" | jq -e '
  .[0].provider == "claude-expired" and .[0].error.kind == "authentication"
  and .[0].usage == null and .[0].analytics.weekTokens == 300
  and .[0].analytics.weekModels == "sonnet:300"
' >/dev/null
[[ "$expired" != *fixture-* ]]
# Reordered requests hit only their own caches; no credential value is emitted.
again="$(bash "$ROOT/providers/get-provider-usage" claude-personal,claude-work)"
printf '%s' "$again" | jq -e '.[0].usage.primary.usedPercent == 12 and .[1].usage.primary.usedPercent == 73' >/dev/null
[[ "$result$again" != *fixture-* ]]
# Readiness follows the profile, never the default CLI or account.
health="$(bash "$ROOT/providers/get-provider-health" claude-work,claude-personal,claude-missing)"
printf '%s' "$health" | jq -e '.[] | select(.provider == "claude-work") | .status == "ready"' >/dev/null
printf '%s' "$health" | jq -e '.[] | select(.provider == "claude-missing") | .status == "missing"' >/dev/null
for profiles in '{}' '{"claude-work":{"configDir":"relative"}}' '{"claude-work":{"configDir":42}}' '{broken' '["/tmp"]' '{"claude-work":{"configDir":"/tmp\nother"}}'; do
  result="$(AIOC_CLAUDE_PROFILES="$profiles" bash "$ROOT/providers/get-provider-usage" claude-work)"
  printf '%s' "$result" | jq -e '.[0].provider == "claude-work" and .[0].error.kind == "configuration" and (.[0].usage == null)' >/dev/null
done
# A symlink spelling of the same directory shares its scope, not another cache.
ln -s "$TMP/personal" "$TMP/personal-link"
CLAUDE_CONFIG_DIR="$TMP/personal-link/../personal" bash "$ROOT/providers/get-claude-usage" >/dev/null
[ "$(find "$XDG_CACHE_HOME/AiOverviewControl/claude-profiles" -name claude-usage-cache.json | wc -l)" -eq 3 ]
echo 'OK: independent Claude profiles, caches, analytics, readiness and invalid config'
