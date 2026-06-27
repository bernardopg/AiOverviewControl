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

## Antigravity protocol

`get-antigravity-usage` reads the current Antigravity CLI OAuth profile from the desktop keyring, falling back to the IDE SQLite state used by older builds, and calls the read-only internal `v1internal:fetchAvailableModels` endpoint. It groups model quotas into Claude, Gemini 3 Pro, and Gemini 3 Flash windows, ordered by highest consumption. The bearer token is supplied to curl over stdin and is never printed or placed in process arguments. This is an internal Google endpoint and may change without notice.

## Settings keys

| Key | Default | Purpose |
| --- | --- | --- |
| `providerSelection` | `codex,claude,copilot` | Comma-separated provider IDs. |
| `refreshInterval` | `120000` | Poll interval in milliseconds. |
| `showErrorProviders` | `true` | Keep provider failures visible. |
| `pillMode` | `auto` | Automatic or custom DankBar provider list. |
| `pillProviders` | selection | Custom DankBar provider IDs. |
| `densityMode` | `comfortable` | Comfortable or compact card layout. |
| `languageOverride` | `auto` | Plugin locale override. |

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
