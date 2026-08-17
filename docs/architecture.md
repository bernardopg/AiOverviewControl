# Architecture

## Components

```text
AiOverviewControlWidget.qml       Runtime orchestration and dashboard
AiOverviewControlSettings.qml     Settings, provider selection, health UI
AiOverviewControlI18n.qml         Locale loading and interpolation
ProviderLogo.qml                  Local provider-logo resolution and fallback icons
providers/get-provider-usage      Multi-provider dispatcher
providers/get-provider-health     Prerequisite checks for settings
providers/get-codex-usage         Codex app-server protocol bridge
providers/get-claude-usage        Claude local analytics and quota bridge
providers/get-copilot-usage       Authenticated GitHub Copilot quota bridge
providers/get-antigravity-usage   Local Antigravity session quota bridge
providers/get-9router-analytics   9Router local telemetry blob (expanded card)
providers/get-pi-analytics        pi coding-agent local session telemetry blob (expanded card)
providers/get-hermes-analytics    Hermes agent local state telemetry blob (expanded card)
providers/get-provider-wrapper    Single-provider wrapper
providers/get-*-usage             Canonical provider entrypoints
scripts/package-release           Release archive build and validation
```

Most API-backed and informational providers expose a normalized JSON
`get-<id>-usage` entrypoint through `get-provider-wrapper`. The specialized
Claude helper emits `KEY=VALUE` analytics for the dispatcher to normalize, and
`pi` and `hermes` use inline dispatcher envelopes plus `get-pi-analytics` /
`get-hermes-analytics`; none of them follows the generic stub contract.

## Runtime flow

1. The widget resolves its own plugin directory through `PluginService` or its QML URL.
2. It verifies that the dispatcher and core commands are available.
3. It executes `get-provider-usage <provider-csv> <copilot-helper>`.
4. The dispatcher calls one adapter per provider and validates every result with `jq`.
5. QML normalizes the JSON array, isolates errors, updates stale timestamps, and renders cards.
6. Claude details run in a separate process so analytics failure cannot block other providers.
7. `pi` follows the same isolation principle via a lighter mechanism: its dispatcher-side envelope (`fetch_pi_native`, inline in `get-provider-usage`) only ever reads a cached snapshot and never scans session files itself; the expanded card's own process (`get-pi-analytics`) does the actual scan on the normal refresh cycle.
8. `hermes` splits the same way, but its collapsed-card envelope (`fetch_hermes_native`) queries `~/.hermes/state.db` directly instead of a cache: the aggregates are indexed SQLite sums that complete in milliseconds, so first paint carries real numbers without waiting for the analytics process.

## Provider contract

Successful adapters return:

```text
provider
source
usage.identity.providerID
usage.identity.accountEmail
usage.identity.loginMethod
usage.primary / secondary / tertiary
  usedPercent
  windowMinutes
  resetsAt
  resetDescription
  displayValue (optional)
usage.updatedAt
accounts[] (optional; local multi-account providers)
  windows (concise quota families)
  modelWindows (optional advanced detail)
credits.remaining
```

Errors return:

```json
{
  "provider": "example",
  "source": "example-api",
  "error": {
    "code": 2,
    "kind": "provider",
    "message": "EXAMPLE_API_KEY is not set."
  }
}
```

## Codex protocol

`get-codex-usage` starts `codex app-server`, completes the `initialize` / `initialized` handshake, sends `account/read` and `account/rateLimits/read`, then maps the official response to the common schema. The bridge reads until both account and rate-limit responses arrive instead of closing stdin after a fixed delay. It retries an authenticated account's transient rate-limit failure once, then may reuse a successful snapshot for up to 15 minutes while preserving its original `updatedAt` timestamp. Authentication failures never fall back to cached data. The bridge uses a bounded process lifetime and never reads browser state.

Window labels are derived from `windowDurationMins`, not from whether app-server placed a limit in `primary` or `secondary`. This matters for current weekly-only responses, where `primary.windowDurationMins` is `10080` and `secondary` is null. OpenAI's current pricing page still documents a shared five-hour window with additional weekly limits, so a weekly-only app-server payload is handled as a temporary or account-specific response shape rather than interpreted as a confirmed policy removal.

## Antigravity protocol

`get-antigravity-usage` reads local Antigravity OAuth sessions from the desktop keyring and each IDE SQLite state database, refreshes them, and calls `v1internal:loadCodeAssist` followed by `v1internal:fetchAvailableModels` on `cloudcode-pa.googleapis.com`. Supplying the account's Cloud Code Assist project is essential: an empty request may receive a generic entitlement view and incorrectly report 0% use. The adapter now aborts that account before the quota call when the project is absent. Refresh tokens are form-encoded from stdin; bearer tokens use an ephemeral curl config descriptor. Neither secret is printed or placed in process arguments.

The adapter preserves the API's per-model values in `modelWindows`, but publishes concise `windows` grouped as **Gemini Models**, **Claude & OpenAI Models**, and, only when the service returns a real unrecognized family, **Other Models**. Internal placeholder entries are discarded. The group percentage and reset come from the model with the least remaining quota in that family, so the dashboard does not hide the first limit a user will hit. A single local account uses the normal provider card; two or more accounts get a compact block per account. The optional `showAntigravityModelDetails` setting exposes the raw per-model list for troubleshooting.

Every account request captures HTTP status and validates the response schema. Partial failures are retained in `accountErrors` while healthy accounts remain usable; an all-account failure becomes a provider error carrying the first precise cause instead of the generic “no session” message.

## pi protocol

`pi` is Analytics-only (no quota API) — same tier as Claude's local half, Cloudflare, and 9Router. It splits the same way 9Router does: `fetch_pi_native()` (inline in `get-provider-usage`) builds the cheap collapsed-card envelope, and the standalone `providers/get-pi-analytics` does the real work for the expanded "pi telemetry" card.

`get-pi-analytics` scans `~/.pi/agent/sessions/**/*.jsonl` (recursively, `find -L` — the sessions directory may be a symlink to a synced folder, and plain `find` silently returns nothing in that case). Each session file is aggregated once (cwd from its `{type:"session"}` header, tokens/cost from `{type:"message"}` lines with a `usage` payload) and the whole file's totals are bucketed to its local start day — sessions are not split across midnight, matching the existing `~/.pi/agent/extensions/session-breakdown.ts` TUI tool's convention. Provider/model come directly off each message; a `{type:"model_change"}` fallback exists for older/partial formats. Results are cached at `${XDG_CACHE_HOME:-$HOME/.cache}/AiOverviewControl/pi-analytics-cache.json` with a 120s TTL (matches the default `refreshInterval`), so the full scan only runs once per window regardless of poll frequency; the envelope function only ever reads that cache, never triggering a scan itself.

## Hermes protocol

`hermes` ([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)) is the only **dual-nature** entry: an agent harness that is simultaneously a provider front (it routes its own spend through Nous Portal, OpenRouter, and friends). The dashboard therefore tags it `Agent · Provider`, and the two natures come from different files under `$HERMES_HOME` (default `~/.hermes`):

| Nature | Source | Rendered as |
| --- | --- | --- |
| Agent harness | `state.db` — `sessions` joined to `session_model_usage` | Today/Week/Month tokens + cost, 7-day chart, top models, top projects, session sources, session/message/API-call counters |
| Provider front | `config.yaml` (`model.default`, `model.provider`) and `auth.json` (`active_provider`) | Card identity line (`<billing provider> · <default model>`), login method, "Open console" → [Nous Portal](https://portal.nousresearch.com) |

Coverage is Analytics-only: Hermes exposes no local quota API, and cost columns are frequently `0` because pricing resolution happens upstream — tokens and API calls carry the real signal, so the expanded chart plots tokens rather than cost.

All SQLite access is `-readonly`: the gateway keeps `state.db` live in WAL mode, and the adapter must never take a write lock on a database the agent is actively using. Usage rows bucket to each session's **local start day** (`date(started_at,'unixepoch','localtime')`), matching the pi adapter's convention — sessions spanning midnight are not split.

`providers/get-hermes-analytics` caches its snapshot at `${XDG_CACHE_HOME:-$HOME/.cache}/AiOverviewControl/hermes-analytics-cache.json` with a 120s TTL (matches the default `refreshInterval`). Counters are queried independently rather than as one combined `SELECT`, so an older Hermes schema missing a table degrades that single counter instead of zeroing all of them. A missing `state.db` returns a provider error, and a missing `sqlite3` binary returns a runtime error — never a crash or an empty card.

## Settings keys

| Key | Default | Purpose |
| --- | --- | --- |
| `providerSelection` | `codex,claude,copilot` | Comma-separated provider IDs. |
| `refreshInterval` | `120000` | Poll interval in milliseconds. |
| `showErrorProviders` | `true` | Keep provider failures visible. |
| `pillMode` | `auto` | Automatic, custom, or highest-usage (`top`) DankBar provider list. |
| `pillProviders` | selection | Strict custom DankBar provider subset; independent from the tracked provider list. |
| `barWindowOverrides` | empty | Per-provider DankBar usage window (`provider:slot`, e.g. `claude:secondary`); slot is `primary`/`secondary`/`tertiary`/`highest`, with graceful fallback to the primary window when the slot is absent from the payload. Only the DankBar reads it — cards, hero, notifications, and history keep the primary window. |
| `densityMode` | `comfortable` | Comfortable or compact card layout. |
| `languageOverride` | `auto` | Plugin locale override. |
| `quotaNotifications` | `true` | Enable desktop quota notifications. |
| `notifyThreshold` | `85` | Global quota notification threshold. |
| `notifyThresholds` | empty | Per-provider `id:percent` notification overrides. |
| `notifyCooldownMinutes` | `0` | Minimum minutes between in-place notification updates; `0` means once per quota window. |
| `historyRetention` | `2000` | Maximum local usage-history snapshots. |
| `pinnedProviders` | empty | Provider IDs sorted before unpinned cards. |
| `providerLogoColor` | current DMS primary color | Monochrome tint for provider logos and notification icons. |
| `showClaudeProjects` | `true` | Show Claude local project analytics. |
| `showAntigravityModelDetails` | `false` | Replace Antigravity family rows with per-model rows in expanded cards. |

Legacy settings unknown to the current code are ignored.

## Resilience

- Overall collection timeout: 45 seconds.
- Provider failures are data, not dispatcher failures.
- Temporary files live in one per-run directory and are removed on exit.
- Informational, local-runtime, balance-only, and analytics-only providers may return a valid `usage` object with a truthful `0%` placeholder; those placeholders are rendered but not written to history.
- `usage-history.jsonl` records only non-zero quota/spend pressure, so sparklines and trends are not polluted by flat informational cards.
- The dashboard marks data stale after two refresh intervals.
- Process command arrays are snapshotted before execution to avoid reactive mutation.

## UI structure

- DankBar pill: selected measurable providers. Per provider, `barWindowOverrides` selects which usage window the pill displays (`primary` by default, or `secondary`/`tertiary`/`highest`); the ranking used by `top` and `auto` pill modes follows the same displayed number.
- Overview: active/error counts and local backend status.
- Provider manager: add and remove providers without editing settings files.
- Filter: shown when more than eight cards are visible.
- Cards: collapsed preview, expanded windows, identity, credits, source, and timestamps.
- Claude details: token/cost history and model distribution.
- pi details: token/cost history, 7-day chart, top models, top projects (same expanded-card slot pattern as 9Router).
- Hermes details: identity pills (default model, billing provider, session/message/API-call counters, version), token/cost tiles, 7-day token chart, top models, top projects, and session-source badges.

## Validation

```bash
find providers -maxdepth 1 -type f -print0 | xargs -0 bash -n
for test in tests/*.sh; do bash -n "$test"; done
bash -n scripts/package-release
shellcheck providers/* tests/*.sh scripts/package-release
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml ProviderLogo.qml
./providers/get-provider-health "codex,claude,copilot,pi" | jq .
./providers/get-provider-usage "codex,claude,copilot,pi" ./providers/get-copilot-usage | jq .
./providers/get-pi-analytics | jq .
./providers/get-hermes-analytics | jq .
bash tests/test-hermes-analytics.sh
```
