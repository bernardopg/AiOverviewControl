# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_minimax_token_plan_native() {
  # MiniMax "Token Plan" subscription quota endpoint (read-only).
  #
  # Two distinct credentials co-exist on MiniMax:
  #   - pay-as-you-go "API Key"           (sk-api-...)  — covers /v1/models auth
  #   - "Token Plan Subscription Key"     (sk-cp-...)   — covers quota windows
  #
  # This helper handles the Token Plan path. The official MiniMax CLI uses the
  # same /v1/token_plan/remains endpoint and the same `general` bucket for both
  # the 5h rolling interval and the weekly window.
  #
  # Prints the usage JSON and returns 0 on success. On failure it prints
  # nothing, sets minimax_token_plan_code/_message and returns 1 — the caller
  # owns the decision to degrade or to emit the error.
  local key="$1"
  local tmp_body http_status message api_status out

  minimax_token_plan_code=""
  minimax_token_plan_message=""

  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "$(minimax_api_base)/v1/token_plan/remains" 2>/dev/null || true)"

  if [ "$http_status" != "200" ]; then
    message="$(jq -r \
      '.base_resp.status_msg // .error.message // .message // empty' \
      "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || \
      message="MiniMax Token Plan quota API returned HTTP ${http_status:-0}."

    rm -f "$tmp_body"
    minimax_token_plan_code="${http_status:-1}"
    minimax_token_plan_message="$message"
    return 1
  fi

  api_status="$(jq -r '.base_resp.status_code // 0' \
    "$tmp_body" 2>/dev/null || printf '1')"

  if [ "$api_status" != "0" ] || \
     ! jq -e '.model_remains | type == "array" and length > 0' \
       "$tmp_body" >/dev/null 2>&1; then
    message="$(jq -r \
      '.base_resp.status_msg // .error.message // .message // empty' \
      "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || \
      message="MiniMax Token Plan quota response did not contain model_remains."

    rm -f "$tmp_body"
    minimax_token_plan_code="${api_status:-1}"
    minimax_token_plan_message="$message"
    return 1
  fi

  if ! out="$(jq -c '
    def clamp($n):
      if $n < 0 then 0
      elif $n > 100 then 100
      else $n
      end;

    # `tonumber?` yields *empty* (not null) for a missing or non-numeric field,
    # and empty would silently collapse the whole output object. Pin it to null
    # so every downstream branch stays reachable.
    def num($v):
      ($v | tonumber?) // null;

    def reset_iso($v):
      num($v) as $n
      | if $n != null and $n > 0
        then (($n / 1000) | todateiso8601)
        else null
        end;

    def remaining($m; $pct_key; $total_key; $usage_key):
      num($m[$pct_key]) as $reported
      | num($m[$total_key]) as $total
      | num($m[$usage_key]) as $used
      | if $reported != null then
          clamp($reported)
        elif $total != null and $total > 0 and $used != null then
          clamp((($total - $used) / $total) * 100)
        else
          null
        end;

    # Window states, per window (never per bucket — a plan can cap the 5h
    # interval while leaving the weekly window untouched, or vice versa):
    #   status 2 → window exhausted            → 100% used
    #   status 3 with no counted quota         → not part of the plan → no card
    #   anything else with a usable remainder  → real usedPercent
    # Everything else returns null so the widget simply omits the slot; we
    # never fabricate a 0% or an "Unlimited" line for a window we cannot read.
    def window(
      $m;
      $pct_key;
      $total_key;
      $usage_key;
      $status_key;
      $reset_key;
      $minutes
    ):
      remaining($m; $pct_key; $total_key; $usage_key) as $left
      | num($m[$status_key]) as $status
      | num($m[$total_key]) as $total
      | if $status == 2 then {
          usedPercent: 100,
          windowMinutes: $minutes,
          resetsAt: reset_iso($m[$reset_key]),
          resetDescription: null
        }
        elif ($status == 3 and ($total // 0) == 0) then
          null
        elif $left != null then {
          usedPercent: clamp(100 - $left),
          windowMinutes: $minutes,
          resetsAt: reset_iso($m[$reset_key]),
          resetDescription: null
        }
        else
          null
        end;

    def windows($m):
      {
        primary: window(
          $m;
          "current_interval_remaining_percent";
          "current_interval_total_count";
          "current_interval_usage_count";
          "current_interval_status";
          "end_time";
          300
        ),
        secondary: window(
          $m;
          "current_weekly_remaining_percent";
          "current_weekly_total_count";
          "current_weekly_usage_count";
          "current_weekly_status";
          "weekly_end_time";
          10080
        )
      };

    [ .model_remains[]
      | select(type == "object")
      | { bucket: ., w: windows(.) }
      | select(.w.primary != null or .w.secondary != null)
    ] as $usable

    | (
        [$usable[] | select(.bucket.model_name == "general")][0]
        // $usable[0]
      ) as $pick

    | if $pick == null then
        error("MiniMax Token Plan has no usable quota bucket")
      else
        {
          provider: "minimax",
          source: "minimax-token-plan",
          usage: {
            identity: {
              providerID: "minimax",
              accountEmail: "MiniMax Token Plan",
              loginMethod: "subscription-key"
            },
            accountEmail: "MiniMax Token Plan",
            loginMethod: "subscription-key",
            primary: $pick.w.primary,
            secondary: $pick.w.secondary,
            tertiary: null,
            updatedAt: (now | todateiso8601)
          },
          credits: {
            remaining: "Token Plan"
          }
        }
      end
  ' "$tmp_body" 2>/dev/null)" || [ -z "$out" ]; then
    rm -f "$tmp_body"
    minimax_token_plan_code="1"
    minimax_token_plan_message="MiniMax Token Plan response contained no usable quota window."
    return 1
  fi

  printf '%s' "$out"
  rm -f "$tmp_body"
  return 0
}
# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_minimax_payg_native() {
  # OpenAI-compatible models list — read-only, consumes no tokens. Mirrors the
  # MiniMax M3/M2.x catalog and doubles as a key-validity check.
  local key="$1"
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "$(minimax_api_base)/v1/models" 2>/dev/null || true)"
  rm -f "$tmp_body"

  if [ "$http_status" = "200" ]; then
    json_note_usage minimax minimax-api "MiniMax account" "api-key" "Authenticated — balance at platform.minimax.io/user-center/payment/balance" "platform.minimax.io"
    return 0
  fi
  json_error minimax minimax-api "${http_status:-1}" provider "MiniMax API key invalid (HTTP ${http_status:-0}). Balance visible at platform.minimax.io only."
}
# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_minimax_native() {
  # MiniMax credentials resolve in priority order:
  #   1. MINIMAX_TOKEN_PLAN_KEY — dedicated Token Plan Subscription Key.
  #   2. MINIMAX_API_KEY starting with sk-cp- — back-compat: an older config
  #      that only knew about a single MiniMax key still gets quota windows.
  #   3. MINIMAX_API_KEY — pay-as-you-go (sk-api-...), auth-only via /v1/models.
  # When a Token Plan probe fails and a separate pay-as-you-go key is present,
  # degrade to the auth-only card rather than blanking the provider — the same
  # honest-degradation ladder Z.ai, GLM and Command Code use.
  local token_plan_key="${MINIMAX_TOKEN_PLAN_KEY:-}"
  local key="${MINIMAX_API_KEY:-}"
  local payg_key="$key"

  case "$key" in
    sk-cp-*)
      [ -n "$token_plan_key" ] || token_plan_key="$key"
      payg_key=""
      ;;
  esac

  if [ -n "$token_plan_key" ]; then
    fetch_minimax_token_plan_native "$token_plan_key" && return 0

    if [ -n "$payg_key" ]; then
      fetch_minimax_payg_native "$payg_key"
      return 0
    fi

    json_error minimax minimax-token-plan \
      "${minimax_token_plan_code:-1}" provider "$minimax_token_plan_message"
    return 0
  fi

  if [ -z "$key" ]; then
    json_error minimax minimax-api 2 provider \
      "MINIMAX_API_KEY or MINIMAX_TOKEN_PLAN_KEY is not set."
    return 0
  fi

  fetch_minimax_payg_native "$key"
}
