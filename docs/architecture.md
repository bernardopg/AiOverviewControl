# Architecture

## Components

```text
AiOverviewControlWidget.qml       Runtime orchestration and dashboard
AiOverviewControlSettings.qml     Settings, provider selection, health UI
AiOverviewControlI18n.qml         Locale loading and interpolation
providers/get-provider-usage      Multi-provider dispatcher
providers/get-provider-health     Prerequisite checks for settings
providers/get-codex-usage         Codex app-server protocol bridge
providers/get-claude-usage        Claude local analytics and quota bridge
providers/get-copilot-usage       Authenticated GitHub Copilot quota bridge
providers/get-antigravity-usage   Local Antigravity session quota bridge
providers/get-provider-wrapper    Single-provider wrapper
providers/get-*-usage             Canonical provider entrypoints
```

## Runtime flow

1. The widget resolves its own plugin directory through `PluginService` or its QML URL.
2. It verifies that the dispatcher and core commands are available.
3. It executes `get-provider-usage <provider-csv> <copilot-helper>`.
4. The dispatcher calls one adapter per provider and validates every result with `jq`.
5. QML normalizes the JSON array, isolates errors, updates stale timestamps, and renders cards.
6. Claude details run in a separate process so analytics failure cannot block other providers.

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

`get-codex-usage` starts `codex app-server`, sends `initialize`, `account/read`, and `account/rateLimits/read`, then maps the official response to the common schema. The bridge uses a bounded process lifetime and never reads browser state.

Window labels are derived from `windowDurationMins`, not from whether app-server placed a limit in `primary` or `secondary`. This matters for current weekly-only responses, where `primary.windowDurationMins` is `10080` and `secondary` is null. OpenAI's current pricing page still documents a shared five-hour window with additional weekly limits, so a weekly-only app-server payload is handled as a temporary or account-specific response shape rather than interpreted as a confirmed policy removal.

## Antigravity protocol

`get-antigravity-usage` reads local Antigravity OAuth sessions from the desktop keyring and each IDE SQLite state database, refreshes them, and calls `v1internal:loadCodeAssist` followed by `v1internal:fetchAvailableModels` on `cloudcode-pa.googleapis.com`. Supplying the account's Cloud Code Assist project is essential: an empty request may receive a generic entitlement view and incorrectly report 0% use. The adapter now aborts that account before the quota call when the project is absent. Refresh tokens are form-encoded from stdin; bearer tokens use an ephemeral curl config descriptor. Neither secret is printed or placed in process arguments.

The adapter preserves the API's per-model values in `modelWindows`, but publishes concise `windows` grouped as **Gemini Models**, **Claude & OpenAI Models**, and, only when the service returns a real unrecognized family, **Other Models**. Internal placeholder entries are discarded. The group percentage and reset come from the model with the least remaining quota in that family, so the dashboard does not hide the first limit a user will hit. A single local account uses the normal provider card; two or more accounts get a compact block per account. The optional `showAntigravityModelDetails` setting exposes the raw per-model list for troubleshooting.

Every account request captures HTTP status and validates the response schema. Partial failures are retained in `accountErrors` while healthy accounts remain usable; an all-account failure becomes a provider error carrying the first precise cause instead of the generic “no session” message.

## Settings keys

| Key | Default | Purpose |
| --- | --- | --- |
| `providerSelection` | `codex,claude,copilot` | Comma-separated provider IDs. |
| `refreshInterval` | `120000` | Poll interval in milliseconds. |
| `showErrorProviders` | `true` | Keep provider failures visible. |
| `pillMode` | `auto` | Automatic, custom, or highest-usage (`top`) DankBar provider list. |
| `pillProviders` | selection | Strict custom DankBar provider subset; independent from the tracked provider list. |
| `densityMode` | `comfortable` | Comfortable or compact card layout. |
| `languageOverride` | `auto` | Plugin locale override. |
| `quotaNotifications` | `true` | Enable desktop quota notifications. |
| `notifyThreshold` | `85` | Global quota notification threshold. |
| `notifyThresholds` | empty | Per-provider `id:percent` notification overrides. |
| `notifyCooldownMinutes` | `0` | Minimum minutes between repeated alerts. |
| `historyRetention` | `2000` | Maximum local usage-history snapshots. |
| `pinnedProviders` | empty | Provider IDs sorted before unpinned cards. |
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

- DankBar pill: selected measurable providers.
- Overview: active/error counts and local backend status.
- Provider manager: add and remove providers without editing settings files.
- Filter: shown when more than eight cards are visible.
- Cards: collapsed preview, expanded windows, identity, credits, source, and timestamps.
- Claude details: token/cost history and model distribution.

## Validation

```bash
bash -n providers/get-*
shellcheck providers/get-*
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
```
