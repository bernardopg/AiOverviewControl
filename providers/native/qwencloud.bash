# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
#
# QwenCloud (home.qwencloud.com) is Alibaba's international Qwen storefront,
# separate from the DashScope/Model Studio `qwen` provider: its own console,
# its own API keys (`sk-` pay-as-you-go, `sk-sp-` Token Plan) and its own
# billing. There is no public read-only usage HTTP API, so this adapter shells
# out to the official QwenCloud CLI (npm i -g @qwencloud/qwencloud-cli), which
# holds an OAuth device-flow login with a `usage:read` scope. Every command
# used here is read-only; the account commands need qwencloud-cli >= 1.3.0.
#
# AIDEV-NOTE: `qwencloud usage summary` reports the Token Plan as unsubscribed
# for Token Plan dedicated (`sk-sp-`) key traffic — plan quota only shows up in
# `qwencloud subscription status`, which is therefore the authoritative source
# for the primary bar.
#
# Finds the CLI beyond the widget's lean PATH (an npm global prefix, mise/asdf
# shims, ~/.local/bin). Keep the candidate list in sync with the qwencloud case
# in providers/get-provider-health.
qwencloud_cli_path() {
  if command -v qwencloud >/dev/null 2>&1; then
    command -v qwencloud
    return 0
  fi
  local candidate
  for candidate in \
    "$HOME/.local/share/npm/bin/qwencloud" \
    "$HOME/.local/share/mise/shims/qwencloud" \
    "$HOME/.asdf/shims/qwencloud" \
    "$HOME/.npm-global/bin/qwencloud" \
    "$HOME/.local/bin/qwencloud" \
    "/usr/local/bin/qwencloud"; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# AIDEV-NOTE: the CLI is a node script (`#!/usr/bin/env node`) while the shell
# process PATH usually has neither the npm prefix nor node itself (mise/asdf
# installs). Run it with the discovery dirs prepended so the env shebang still
# resolves node.
qwencloud_run() {
  local d extra=""
  for d in \
    "$HOME/.local/share/npm/bin" \
    "$HOME/.local/share/mise/shims" \
    "$HOME"/.local/share/mise/installs/node/*/bin \
    "$HOME/.asdf/shims" \
    "$HOME/.npm-global/bin" \
    "$HOME/.local/bin"; do
    [ -d "$d" ] && extra="${extra:+$extra:}$d"
  done
  PATH="${extra:+$extra:}$PATH" timeout 20 "$@" 2>/dev/null
}

fetch_qwencloud_native() {
  local cli
  if ! cli="$(qwencloud_cli_path)"; then
    json_error qwencloud qwencloud-cli 2 provider "QwenCloud CLI not found. Install with: npm install -g @qwencloud/qwencloud-cli, then run: qwencloud auth login"
    return 0
  fi

  local auth sub summary
  auth="$(qwencloud_run "$cli" auth status --format json || true)"
  if ! jq -e '.authenticated == true' >/dev/null 2>&1 <<<"$auth"; then
    json_error qwencloud qwencloud-cli 2 provider "QwenCloud CLI is not signed in or the login expired. Run: qwencloud auth login"
    return 0
  fi

  # Read-only account commands; a failure degrades that branch to {} instead
  # of failing the whole card.
  sub="$(qwencloud_run "$cli" subscription status --format json || true)"
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$sub" || sub="{}"
  summary="$(qwencloud_run "$cli" usage summary --format json || true)"
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$summary" || summary="{}"

  jq -cn --argjson auth "$auth" --argjson sub "$sub" --argjson summary "$summary" '
    def num($v): ($v | tonumber? // 0);
    def clamp100($v): (if $v < 0 then 0 elif $v > 100 then 100 else $v end);
    def pct1($v): ((num($v) * 10 | round) / 10 | tostring) + "%";
    def money($v; $cur):
      ((num($v) * 100) | round) as $cc
      | (if $cur == "USD" or $cur == "" then "$" else ($cur + " ") end)
        + (($cc / 100) | floor | tostring) + "."
        + ((100 + ($cc % 100) | tostring) | .[1:]);
    def plain($label; $value):
      {usedPercent: 0, hasLimit: false, windowMinutes: null, resetsAt: null,
       resetDescription: $label, displayValue: $value};
    def isodate($v):
      ($v // null) | if . == null then null else (strings | sub("\\.[0-9]+Z$"; "Z")) end;

    ($auth.user.aliyunId // "QwenCloud account" | strings) as $email
    # Token Plan: the individual subscription first, then a team one. The
    # monthlyCredits percentages are already on a 0..100 scale.
    | (if ($sub.individual.status // "") == "active" then
         {name: ("Token Plan" + (if ($sub.individual.name // "") != "" then " " + $sub.individual.name else "" end)),
          mc: ($sub.individual.monthlyCredits // {})}
       elif ($sub.team.status // "") == "active" then
         {name: "Token Plan Team", mc: ($sub.team.monthlyCredits // {})}
       else null end) as $tp
    | (if $tp != null and ($tp.mc.usedPct | type) == "number" then
         {
           usedPercent: clamp100($tp.mc.usedPct),
           windowMinutes: null,
           resetsAt: isodate($tp.mc.resetTime),
           resetDescription: "Token Plan",
           hasLimit: true,
           displayValue: (pct1($tp.mc.usedPct) + " · " + $tp.name)
         }
       else null end) as $plan
    | ($summary.pay_as_you_go.total // {}) as $payg_total
    | plain("PAYG this month"; money($payg_total.cost; ($payg_total.currency // "USD"))) as $payg_bar
    | ([$summary.free_tier[]? | select(.quota.status == "valid")] | length) as $free_valid
    | ([$summary.free_tier[]?] | length) as $free_total
    | (if $free_total > 0 then
         plain("Free tier"; (($free_valid | tostring) + "/" + ($free_total | tostring) + " models"))
       else null end) as $free_bar
    # Slot order: the plan bar leads when subscribed; a pure pay-as-you-go
    # account leads with its spend. Missing pieces degrade to a plain note.
    | (if $plan != null then
         {primary: $plan,
          secondary: $payg_bar,
          tertiary: ($free_bar // plain("Free tier"; "No free-tier quota"))}
       elif $free_bar != null then
         {primary: $free_bar,
          secondary: $payg_bar,
          tertiary: plain("Token Plan"; "Not subscribed")}
       else
         {primary: $payg_bar,
          secondary: plain("Free tier"; "No free-tier quota"),
          tertiary: plain("Token Plan"; "Not subscribed")}
       end) as $slots
    | {
        provider: "qwencloud",
        source: "qwencloud-cli",
        usage: ({
          identity: {providerID: "qwencloud", accountEmail: $email, loginMethod: "qwencloud-cli"},
          accountEmail: $email,
          loginMethod: "qwencloud-cli",
          updatedAt: (now | todateiso8601)
        } + $slots),
        credits: {
          remaining: (
            if $plan != null then
              (pct1($tp.mc.remainingPct // (100 - num($tp.mc.usedPct))) + " left")
            else "pay-as-you-go"
            end
          )
        }
      }
  '
}
