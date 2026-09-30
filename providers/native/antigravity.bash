# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_antigravity_native() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
  # Match the quota path used by 9Router and the Cloud Code Assist client.
  # The `daily` host accepts the request too, but may return a generic quota
  # view. Keep the base URL override for future Antigravity builds.
  local endpoint="${ANTIGRAVITY_API_BASE_URL:-https://daily-cloudcode-pa.googleapis.com}"
  local quota_method="${ANTIGRAVITY_QUOTA_METHOD:-v1internal:retrieveUserQuotaSummary}"
  local response_file="${ANTIGRAVITY_RESPONSE_FILE:-}"
  local user_agent="${ANTIGRAVITY_USER_AGENT:-antigravity/ide/2.1.1 darwin/arm64}"
  local platform="${ANTIGRAVITY_PLATFORM:-3}"
  local accounts_file account_errors_file request_error_file tmp_body quota_body rt refreshed at id_token email install db
  local -a dbs=()

  accounts_file="$(mktemp)"
  account_errors_file="$(mktemp)"
  request_error_file="$(mktemp)"
  tmp_body="$(mktemp)"

  # --- Fixture path: deterministic parsing tests, no live session. The fixture
  # is a retrieveUserQuotaSummary payload; it becomes a single synthetic account.
  if [ -n "$response_file" ]; then
    if [ ! -r "$response_file" ]; then
      rm -f "$tmp_body" "$accounts_file" "$account_errors_file" "$request_error_file"
      json_error antigravity antigravity-internal 2 runtime "Antigravity response fixture is not readable."
      return 0
    fi
    # ANTIGRAVITY_HTTP_STATUS lets tests exercise the transport error mapping
    # without a live session; the live path applies the same codes per account.
    local fixture_status="${ANTIGRAVITY_HTTP_STATUS:-200}"
    if [ "$fixture_status" != "200" ]; then
      rm -f "$tmp_body" "$accounts_file" "$account_errors_file" "$request_error_file"
      case "$fixture_status" in
        401|403) json_error antigravity antigravity-internal "$fixture_status" provider "Antigravity session expired. Open Antigravity and sign in again." ;;
        429) json_error antigravity antigravity-internal 429 provider "Antigravity quota endpoint is rate-limited. Retry after its reset time." ;;
        *) json_error antigravity antigravity-internal "$fixture_status" provider "Antigravity quota request returned HTTP ${fixture_status}." ;;
      esac
      return 0
    fi
    if jq -e '.groups | type == "array"' "$response_file" >/dev/null 2>&1; then
      # Legacy fixture support for retrieveUserQuotaSummary captures.
      if ! antigravity_append_group_account \
          "$accounts_file" "$response_file" \
          "${ANTIGRAVITY_INSTALL_LABEL:-Antigravity}" \
          "${ANTIGRAVITY_ACCOUNT_EMAIL:-Antigravity}" \
          "fixture"; then
        rm -f "$tmp_body" "$accounts_file" "$account_errors_file" "$request_error_file"
        json_error antigravity antigravity-internal 1 provider "Antigravity quota response has no readable quota windows."
        return 0
      fi
    elif jq -e '(.models | type) == "object"' "$response_file" >/dev/null 2>&1; then
      antigravity_models_account_json \
        "${ANTIGRAVITY_INSTALL_LABEL:-Antigravity}" \
        "${ANTIGRAVITY_ACCOUNT_EMAIL:-Antigravity}" \
        "fixture" < "$response_file" >> "$accounts_file"
    else
      rm -f "$tmp_body" "$accounts_file" "$account_errors_file" "$request_error_file"
      json_error antigravity antigravity-internal 1 provider "Antigravity quota response schema changed: groups or models object is missing."
      return 0
    fi
  else
    # --- Discover install sessions. Each Antigravity install keeps its own
    # state.vscdb under a distinct config dir, so two IDEs / two Google accounts
    # appear as two databases. An explicit override pins a single DB for tests.
    if [ -n "${ANTIGRAVITY_STATE_DB:-}" ]; then
      [ -r "$ANTIGRAVITY_STATE_DB" ] && dbs+=("$ANTIGRAVITY_STATE_DB")
    else
      for dir in "$cfg/Antigravity IDE" "$cfg/Antigravity" "$cfg"/*ntigravity*; do
        db="$dir/User/globalStorage/state.vscdb"
        [ -r "$db" ] || continue
        case " ${dbs[*]:-} " in *" $db "*) continue ;; esac
        dbs+=("$db")
      done
    fi

    local seen_emails=" "
    if [ "${#dbs[@]}" -gt 0 ]; then
      for db in "${dbs[@]}"; do
        install="$(printf '%s' "$db" | sed -E 's#.*/\.config/([^/]+)/User/.*#\1#')"
        [ -n "$install" ] && [ "$install" != "$db" ] || install="Antigravity"
        rt="$(extract_antigravity_idedb_refresh "$db")"
        [ -n "$rt" ] || continue
        : > "$request_error_file"
        if ! refreshed="$(antigravity_refresh_access_token "$rt" 2>"$request_error_file")"; then
          antigravity_append_account_error "$account_errors_file" "$install" "Account unavailable" "oauth-refresh" \
            "$(cut -f1 "$request_error_file")" "$(cut -f2- "$request_error_file")"
          continue
        fi
        at="$(printf '%s' "$refreshed" | cut -f1)"
        id_token="$(printf '%s' "$refreshed" | cut -f2)"
        email="$(antigravity_email_from_idtoken "$id_token")"
        [ -n "$email" ] || email="Antigravity account"
        # Skip a duplicate account already collected from another install dir.
        case "$seen_emails" in *" $email "*) continue ;; esac
        seen_emails="$seen_emails$email "
        : > "$tmp_body"
        : > "$request_error_file"
        if ! quota_body="$(antigravity_quota_request_body "$at" "$endpoint" "$user_agent" "$platform" 2>"$request_error_file")"; then
          antigravity_append_account_error "$account_errors_file" "$install" "$email" "loadCodeAssist" \
            "$(cut -f1 "$request_error_file")" "$(cut -f2- "$request_error_file")"
          continue
        fi
        antigravity_fetch_account \
          "$accounts_file" "$account_errors_file" "$tmp_body" "$install" "$email" \
          "IDE session OAuth (refreshed)" "$at" "$endpoint" "$quota_body" "$user_agent" "$quota_method" || true
      done
    fi

    # Desktop keyring or CLI file storage (agy CLI) as an extra source.
    # When ANTIGRAVITY_STATE_DB is explicitly set, it pins discovery to that DB
    # for deterministic tests and targeted debugging, so do not fall through to
    # unrelated local keyring credentials.
    if [ -z "${ANTIGRAVITY_STATE_DB:-}" ]; then
      local keyring_payload="" service="" source_label="CLI keyring"
      if command -v secret-tool >/dev/null 2>&1; then
        for service in "gemini" "${ANTIGRAVITY_KEYRING_SERVICE:-Antigravity CLI}" "antigravity-cli" "Antigravity"; do
          if [ "$service" = "gemini" ]; then
            keyring_payload="$(timeout 3 secret-tool lookup service gemini username antigravity 2>/dev/null || true)"
          else
            keyring_payload="$(timeout 3 secret-tool lookup service "$service" 2>/dev/null || true)"
          fi
          [ -n "$keyring_payload" ] && break
        done
      fi
      if [ -z "$keyring_payload" ]; then
        for token_file in "${HOME}/.gemini/antigravity-cli/antigravity-oauth-token" \
                          "${XDG_CONFIG_HOME:-$HOME/.config}/antigravity-cli/antigravity-oauth-token"; do
          if [ -r "$token_file" ]; then
            keyring_payload="$(cat "$token_file" 2>/dev/null || true)"
            [ -n "$keyring_payload" ] && { source_label="CLI file"; break; }
          fi
        done
      fi
      if [ -n "$keyring_payload" ]; then
        rt="$(printf '%s' "$keyring_payload" | extract_antigravity_keyring_refresh)"
        if [ -n "$rt" ]; then
          : > "$request_error_file"
          if ! refreshed="$(antigravity_refresh_access_token "$rt" 2>"$request_error_file")"; then
            antigravity_append_account_error "$account_errors_file" "$source_label" "Account unavailable" "oauth-refresh" \
              "$(cut -f1 "$request_error_file")" "$(cut -f2- "$request_error_file")"
          else
            at="$(printf '%s' "$refreshed" | cut -f1)"
            email="$(antigravity_email_from_idtoken "$(printf '%s' "$refreshed" | cut -f2)")"
            [ -n "$email" ] || email="Antigravity CLI"
            case "$seen_emails" in *" $email "*) : ;; *)
              seen_emails="$seen_emails$email "
              : > "$tmp_body"
              : > "$request_error_file"
              if ! quota_body="$(antigravity_quota_request_body "$at" "$endpoint" "$user_agent" "$platform" 2>"$request_error_file")"; then
                antigravity_append_account_error "$account_errors_file" "$source_label" "$email" "loadCodeAssist" \
                  "$(cut -f1 "$request_error_file")" "$(cut -f2- "$request_error_file")"
              else
                antigravity_fetch_account \
                  "$accounts_file" "$account_errors_file" "$tmp_body" "$source_label" "$email" \
                  "CLI OAuth (refreshed)" "$at" "$endpoint" "$quota_body" "$user_agent" "$quota_method" || true
              fi
              ;;
            esac
          fi
        fi
      fi
    fi
  fi

  # --- No account collected: emit an isolated, honest error. ---
  if [ ! -s "$accounts_file" ]; then
    if [ -s "$account_errors_file" ]; then
      jq -cs '
        . as $errors | $errors[0] as $first
        | {provider:"antigravity",source:"antigravity-internal",
           error:{code:($first.code // 1),kind:($first.kind // "provider"),message:$first.message},
           accountErrors:$errors}
      ' "$account_errors_file"
      rm -f "$tmp_body" "$accounts_file" "$account_errors_file" "$request_error_file"
      return 0
    fi
    rm -f "$tmp_body" "$accounts_file" "$account_errors_file" "$request_error_file"
    json_error antigravity antigravity-local 2 provider "No usable Antigravity session was found. Open Antigravity and sign in, or install the agy CLI."
    return 0
  fi

  # --- Assemble. The compact card mirrors the most-constrained account so the
  # single-line render still works; the accounts[] array drives the expanded,
  # per-account panel. ---
  jq -cs --slurpfile errors "$account_errors_file" '
    map(select(. != null and (.windows | length) > 0)) as $accts
    | if ($accts | length) == 0 then
        {provider:"antigravity", source:"antigravity-internal",
         error:{code:1, kind:"provider", message:"Antigravity returned no quota pools for any account."}}
      else
        ($accts
          | sort_by( - ( [.windows[].usedPercent] | max // 0 ) )
          | .[0]) as $lead
        | ($accts | length) as $n
        | {
            provider:"antigravity",
            source:"antigravity-internal",
            usage:{
              identity:{providerID:"antigravity", accountEmail:$lead.email, loginMethod:$lead.loginMethod},
              accountEmail:$lead.email,
              loginMethod:$lead.loginMethod,
              primary:(($lead.windows | sort_by(-.usedPercent))[0] // null),
              secondary:(($lead.windows | sort_by(-.usedPercent))[1] // null),
              tertiary:(($lead.windows | sort_by(-.usedPercent))[2] // null),
              updatedAt:(now | todateiso8601)
            },
            accounts:$accts,
            accountErrors:$errors,
            credits:{remaining: (($n | tostring) + " account" + (if $n == 1 then "" else "s" end))}
          }
      end
  ' "$accounts_file"

  rm -f "$tmp_body" "$accounts_file" "$account_errors_file" "$request_error_file"
}
