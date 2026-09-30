# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_xai_native() {
  # SuperGrok / Grok Build usage (grok login) is the desktop default. The
  # inference XAI_API_KEY cannot read remaining credits. Prepaid API credits
  # need a separate Management key.
  local grok_auth original_grok_auth billing_status refresh_attempted refresh_failed
  grok_auth="$(xai_grok_auth_json)"
  original_grok_auth="$grok_auth"
  billing_status=1
  refresh_attempted=0
  refresh_failed=0

  if [ -n "$grok_auth" ]; then
    if xai_grok_auth_is_expired "$grok_auth"; then
      if xai_grok_auth_has_refresh_token "$grok_auth"; then
        refresh_attempted=1
        if xai_refresh_grok_auth "$grok_auth"; then
          grok_auth="$(xai_grok_auth_json)"
        else
          refresh_failed=1
        fi
      else
        refresh_failed=1
      fi
    fi

    if ! xai_grok_auth_is_expired "$grok_auth"; then
      fetch_xai_cli_billing "$grok_auth"
      billing_status=$?
      if [ "$billing_status" -eq 0 ]; then
        return 0
      fi

      # The server can revoke a token before its recorded expiry. Ask the CLI
      # to renew it once, then retry billing once. Never refresh for 5xx or
      # schema failures because those are not credential problems.
      if [ "$billing_status" -eq 2 ] \
        && [ "$refresh_attempted" -eq 0 ] \
        && xai_grok_auth_has_refresh_token "$grok_auth"; then
        refresh_attempted=1
        if xai_refresh_grok_auth "$grok_auth"; then
          grok_auth="$(xai_grok_auth_json)"
          fetch_xai_cli_billing "$grok_auth"
          billing_status=$?
          if [ "$billing_status" -eq 0 ]; then
            return 0
          fi
        else
          refresh_failed=1
        fi
      fi
    fi
  fi
  if fetch_xai_management_balance "${grok_auth:-$original_grok_auth}"; then
    return 0
  fi
  if [ -n "${XAI_API_KEY:-}" ]; then
    fetch_xai_api_key_status
    return 0
  fi
  if [ -n "$original_grok_auth" ]; then
    if xai_grok_auth_is_expired "${grok_auth:-$original_grok_auth}"; then
      if xai_grok_auth_has_refresh_token "$original_grok_auth"; then
        if [ -z "$(xai_grok_cli_path)" ]; then
          json_error xai grok-cli-billing 2 provider \
            "Grok access token expired and the Grok CLI was not found. Install Grok or run grok login."
        else
          json_error xai grok-cli-billing 2 provider \
            "Grok access token expired and automatic renewal failed. Run grok login."
        fi
      else
        json_error xai grok-cli-billing 2 provider \
          "Grok login expired and has no refresh token. Run grok login."
      fi
      return 0
    fi
    if [ "$billing_status" -eq 2 ] && [ "$refresh_failed" -eq 1 ]; then
      json_error xai grok-cli-billing 2 provider \
        "Grok login was rejected and automatic renewal failed. Run grok login."
      return 0
    fi
    if [ "$billing_status" -eq 2 ]; then
      if [ "$refresh_attempted" -eq 1 ]; then
        json_error xai grok-cli-billing 2 provider \
          "Grok login was rejected after automatic renewal. Run grok login."
      else
        json_error xai grok-cli-billing 2 provider \
          "Grok login was rejected. Run grok login."
      fi
      return 0
    fi
    json_error xai grok-cli-billing 1 provider \
      "Grok CLI billing API unavailable (${XAI_CLI_BILLING_FAILURE:-unknown error}). Retry later."
    return 0
  fi
  if xai_grok_has_auth_file; then
    json_error xai grok-cli-billing 2 provider \
      "Grok login expired. Run grok login, or set XAI_API_KEY."
    return 0
  fi
  json_error xai xai-api 2 provider \
    "No xAI credentials found. Sign in with grok login, or set XAI_API_KEY. Remaining API credits need XAI_MANAGEMENT_KEY and XAI_TEAM_ID from console.x.ai."
}
