# AiOverviewControl

[![CI](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml/badge.svg)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/bernardopg/AiOverviewControl)](https://github.com/bernardopg/AiOverviewControl/releases/latest)
[![License](https://img.shields.io/github/license/bernardopg/AiOverviewControl)](./LICENSE)

A self-contained [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
widget for AI quota, billing, authentication, and local usage telemetry.

AiOverviewControl collects each provider independently, normalizes the result,
and renders an overview in DankBar without requiring an external aggregation
service. It reports measured data when a supported source exists and clearly
labels authentication-only or informational providers when it does not.

![AiOverviewControl dashboard](./screenshot.png)

## Highlights

- Unified dashboard for 30+ AI providers and developer tools.
- Official Codex rate-limit windows through `codex app-server`.
- Claude Code quota plus local token, session, model, project, and cost analytics.
- GitHub Copilot premium request, Chat, and Completions quota snapshots.
- Provider cards with usage windows, reset times, account identity, credits,
  data source, freshness state, sparklines, trends, and direct console links.
- Independent provider execution: one timeout or invalid credential does not
  hide healthy providers.
- Compact and comfortable layouts, status/name filters, pinned providers,
  expand-all controls, and `auto`, `custom`, or `top` DankBar pill modes.
- Desktop quota notifications with global and per-provider thresholds.
- English, Brazilian Portuguese, Simplified Chinese, Spanish, and German UI.
- No dashboard scraping and no fabricated quota percentages.

## Version 1.4.0

The current release expands the dashboard and its telemetry pipeline:

- Usage-history points now include timestamps for sparkline hover details.
- Claude analytics show weekly cost by model and a 7-day burn-rate forecast.
- OpenRouter can show the top two models from its 30-day activity endpoint.
- Cloudflare Workers AI can show seven-day and latest-day request/neuron totals
  when `CLOUDFLARE_ACCOUNT_ID` is configured.
- History retention is configurable at 500, 2,000, or 10,000 snapshots.
- Providers can be pinned from settings and assigned individual notification
  thresholds such as `claude:90,codex:75`.
- Provider cards support keyboard focus plus Enter/Space, Delete, P, and R
  actions.
- Spanish (`es_ES`) and German (`de_DE`) join the existing locale bundles.

See the complete history in [CHANGELOG.md](./CHANGELOG.md).

## Coverage Model

Provider cards use one of four honest coverage levels:

| Coverage | Meaning |
| --- | --- |
| Quota or balance | Returns limits, usage, credits, or billing data. |
| Local analytics | Reads provider-owned files or databases. |
| Authentication | Verifies credentials without stable quota data. |
| Informational | Links official usage when no read-only API exists. |

Notable measured integrations include:

| Provider | Data source |
| --- | --- |
| Codex | Official `codex app-server` account and rate-limit methods. |
| Claude Code | OAuth quota plus local `~/.claude/projects` analytics. |
| GitHub Copilot | Authenticated GitHub/Copilot quota snapshot. |
| 9Router | Local SQLite or JSON usage data. |
| OpenRouter | Key limits, spend, balance, and model activity. |
| DeepSeek, Kimi, Together | Provider balance or credit APIs. |
| Ollama | Installed and running models from `/api/tags` and `/api/ps`. |
| Cloudflare | Token verification and optional Workers AI GraphQL analytics. |

The full matrix, credentials, and upstream references are documented in
[Providers](./docs/providers.md) and
[Provider verification](./docs/provider-verification.md).

## Requirements

- DankMaterialShell running on Quickshell.
- `bash`, `jq`, and `curl`.
- Provider-specific CLIs or credentials only for providers you enable.

Recommended baseline for the default provider set:

```bash
command -v bash jq curl codex claude gh
codex login
claude auth status
gh auth status
```

## Installation

### Release Archive

Download the `.tar.gz` or `.zip` from the
[latest release](https://github.com/bernardopg/AiOverviewControl/releases/latest),
extract it as `AiOverviewControl`, and place it in the DMS plugin directory:

```text
~/.config/DankMaterialShell/plugins/AiOverviewControl
```

Then restore executable bits and restart DMS:

```bash
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

### Git Checkout

```bash
git clone https://github.com/bernardopg/AiOverviewControl.git \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

Enable **AiOverviewControl** in DMS settings and add it to a DankBar section.
Detailed installation and upgrade guidance is available in
[docs/installation.md](./docs/installation.md).

## Configuration

Settings are stored by DMS and survive plugin upgrades.

| Setting | Values | Default |
| --- | --- | --- |
| Language | `auto`, `en_US`, `pt_BR`, `zh_CN`, `es_ES`, `de_DE` | `auto` |
| Dashboard density | `comfortable`, `compact` | `comfortable` |
| Pill mode | `auto`, `custom`, `top` | `auto` |
| Refresh interval | 1, 2, 5, 15, or 30 minutes | 2 minutes |
| Show provider errors | enabled or disabled | enabled |
| Claude project breakdown | enabled or disabled | enabled |
| Quota notifications | enabled or disabled | enabled |
| Global notification threshold | 75%, 85%, or 95% | 85% |
| Per-provider thresholds | comma-separated `provider:percent` pairs | empty |
| History retention | 500, 2,000, or 10,000 snapshots | 2,000 |

The default provider selection is:

```text
codex,claude,copilot
```

API-backed providers read credentials from the DMS process environment. An
export available only in an interactive shell may not reach a graphical DMS
session. See [Configuration](./docs/configuration.md) for the environment
variable matrix and health-check behavior.

## Dashboard Behavior

- Cards are sorted with pinned providers first, then by highest measurable
  usage, with failed providers last.
- Data becomes stale after twice the configured refresh interval.
- Failed cards expose a provider-specific retry action.
- Expanded cards show available windows, credits, source, identity, and update
  time without inventing unavailable fields.
- Usage snapshots are stored locally in
  `~/.cache/AiOverviewControl/usage-history.jsonl` and trimmed according to the
  configured retention.
- Claude analytics run separately so local history or OAuth failures cannot
  block the main provider collection.

## Privacy and Resilience

- Credentials are read from provider CLIs, local provider-owned data, or
  environment variables; the UI never displays secret values.
- The plugin does not scrape authenticated web dashboards.
- It does not call paid inference endpoints merely to test a key.
- Temporary files are isolated per run and removed when collection finishes.
- Provider errors are returned as structured data instead of terminating the
  complete refresh.
- Informational cards use explicit text and official links rather than
  synthetic percentages.

## Validation

Run the same core checks used by CI:

```bash
jq -e . plugin.json >/dev/null
for file in i18n/*.json; do jq -e . "$file" >/dev/null; done
bash -n providers/get-*
shellcheck providers/get-*
qmllint \
  AiOverviewControlWidget.qml \
  AiOverviewControlSettings.qml \
  AiOverviewControlI18n.qml
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-provider-usage \
  "codex,claude,copilot" \
  ./providers/get-copilot-usage | jq .
./providers/get-usage-history | jq .
```

GitHub Actions additionally validates workflow syntax, locale key parity,
provider script permissions, integration contracts, Crowdin configuration,
and release packaging.

## Architecture

```text
AiOverviewControlWidget.qml       Runtime orchestration and dashboard
AiOverviewControlSettings.qml     Settings, provider selection, and health UI
AiOverviewControlI18n.qml         Locale loading and interpolation
providers/get-provider-usage      Multi-provider dispatcher and history writer
providers/get-provider-health     Local prerequisite checks
providers/get-codex-usage         Codex app-server protocol bridge
providers/get-claude-usage        Claude quota and local analytics bridge
providers/get-copilot-usage       GitHub Copilot quota bridge
providers/get-*-usage             Canonical single-provider entrypoints
```

See [Architecture](./docs/architecture.md) for the runtime flow and normalized
provider contract.

## Documentation

- [Installation and upgrades](./docs/installation.md)
- [Configuration and credentials](./docs/configuration.md)
- [Provider coverage matrix](./docs/providers.md)
- [Provider verification policy](./docs/provider-verification.md)
- [Architecture and adapter contract](./docs/architecture.md)
- [Troubleshooting](./docs/troubleshooting.md)
- [Português do Brasil](./docs/README.pt-BR.md)
- [Internationalization and Crowdin](./docs/i18n-crowdin.md)
- [Release checklist](./docs/release-checklist.md)
- [Changelog](./CHANGELOG.md)

## License

Released under the [MIT License](./LICENSE).
