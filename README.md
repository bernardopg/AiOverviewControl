<div align="center">

![AiOverviewControl banner](./docs/assets/banner.png)

# AiOverviewControl

**All your AI quotas. One dashboard. Zero guesswork.**

A self-contained [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) widget for AI quota,
billing, authentication, and local usage telemetry — right in your DankBar.

[![CI](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml/badge.svg)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/bernardopg/AiOverviewControl)](https://github.com/bernardopg/AiOverviewControl/releases/latest)
[![License](https://img.shields.io/github/license/bernardopg/AiOverviewControl)](./LICENSE)
[![Providers](https://img.shields.io/badge/providers-33-7C4DFF)](./docs/providers.md)
[![Languages](https://img.shields.io/badge/UI%20languages-5-00BFA5)](./docs/i18n-crowdin.md)

[Install](#installation) · [Screenshots](#screenshots) · [Providers](./docs/providers.md) ·
[Configuration](./docs/configuration.md) · [Changelog](./CHANGELOG.md) ·
[Português do Brasil](./docs/README.pt-BR.md)

</div>

---

## See it in action

![AiOverviewControl demo](./docs/assets/demo.gif)

> 🎬 Prefer higher quality? Watch the [MP4 demo](./docs/assets/demo.mp4).

The pill lives in your DankBar and shows live usage at a glance:

![DankBar pill](./docs/assets/bar-pill.png)

## Why AiOverviewControl?

You pay for Claude, Codex, Copilot, OpenRouter — and each one hides its quota
in a different dashboard, CLI, or API. AiOverviewControl collects every
provider **independently and locally**, normalizes the result, and renders one
honest overview without any external aggregation service.

**Honest** is the key word: it reports measured data when a supported source
exists, and clearly labels authentication-only or informational providers when
it does not. No dashboard scraping. No fabricated percentages. Ever.

## Highlights

| | |
| --- | --- |
| 📊 **Unified dashboard** | 33 AI providers and developer tools in one place. |
| ⏱️ **Official Codex windows** | Rate-limit windows straight from `codex app-server`. |
| 🤖 **Deep Claude analytics** | Quota plus local token, session, model, project, and cost analytics. |
| 🐙 **Copilot quotas** | Premium request, Chat, and Completions snapshots. |
| 🗂️ **Rich provider cards** | Usage windows, reset times, identity, credits, sparklines, trends, and console links. |
| 🛡️ **Failure isolation** | One timeout or invalid credential never hides healthy providers. |
| 🎛️ **Flexible layout** | Compact/comfortable density, status filters, pinned providers, and `auto`/`custom`/`top` pill modes. |
| 🔔 **Quota notifications** | Desktop alerts with global and per-provider thresholds, fired once per quota window. |
| 🌍 **5 UI languages** | English, Português (BR), 简体中文, Español, and Deutsch. |
| 🔒 **Privacy first** | Local adapters, no paid endpoints just to test keys, secrets never displayed. |

## Screenshots

| Dashboard overview | Expanded provider card |
| --- | --- |
| ![Dashboard](./docs/assets/dashboard.png) | ![Expanded card](./docs/assets/card-expanded.png) |

<details>
<summary><b>📈 Local telemetry deep-dive (9Router example)</b></summary>
<br>

Per-provider telemetry sections include daily cost charts, today/week/month
totals, token in/out counters, top models, and routed-provider breakdowns —
all read from local, provider-owned data.

![9Router telemetry](./docs/assets/telemetry.png)

</details>

## Coverage Model

Provider cards use one of these honest coverage levels:

| Coverage | Meaning |
| --- | --- |
| **Quota** | Returns rate-limit windows and used percentage (Codex, Copilot, OpenRouter). |
| **Balance** | Returns remaining prepaid balance or credits in real currency (Kimi, DeepSeek, Together). |
| **Analytics** | Reads consumption counters or provider-owned local data (Cloudflare GraphQL, 9Router, Claude, Ollama). |
| **Authentication** | Verifies credentials via a read-only endpoint without stable quota data (Gemini, Mistral, GLM, Z.ai, NVIDIA, MiniMax, Qwen, xAI, and more). |
| **Informational** | Links official usage when no read-only API exists (Kiro, Cursor, Warp, and more). |

Notable integrations:

| Provider | Data source |
| --- | --- |
| Codex | Official `codex app-server` account and rate-limit methods. |
| Claude Code | OAuth quota plus local `~/.claude/projects` analytics. |
| GitHub Copilot | Authenticated GitHub/Copilot quota snapshot. |
| 9Router | Local SQLite or JSON usage data, including routed-model telemetry. |
| OpenRouter | Key limits, spend, balance, and 30-day model activity. |
| Kimi (Moonshot) | `GET /v1/users/me/balance` — available, voucher, and cash balance (USD/CNY). |
| DeepSeek, Together | Provider balance or credit APIs. |
| Cloudflare | Token verification and optional Workers AI GraphQL analytics. |
| xAI, GLM, Z.ai, MiniMax, Qwen, NVIDIA, Mistral | Read-only `/models` (or `/api-key`) validation — zero token consumption. |
| Ollama | Installed and running models from `/api/tags` and `/api/ps`. |

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
| Per-provider thresholds | comma-separated `provider:percent` pairs (e.g. `claude:90,codex:75`) | empty |
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
- Cards support keyboard focus plus Enter/Space (expand), Delete (remove),
  P (pin), and R (retry) actions.
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

<details>
<summary>Run the same core checks used by CI</summary>
<br>

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

</details>

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

| Topic | Link |
| --- | --- |
| Installation and upgrades | [docs/installation.md](./docs/installation.md) |
| Configuration and credentials | [docs/configuration.md](./docs/configuration.md) |
| Provider coverage matrix | [docs/providers.md](./docs/providers.md) |
| Provider verification policy | [docs/provider-verification.md](./docs/provider-verification.md) |
| Architecture and adapter contract | [docs/architecture.md](./docs/architecture.md) |
| Troubleshooting | [docs/troubleshooting.md](./docs/troubleshooting.md) |
| Português do Brasil | [docs/README.pt-BR.md](./docs/README.pt-BR.md) |
| Internationalization and Crowdin | [docs/i18n-crowdin.md](./docs/i18n-crowdin.md) |
| Release checklist | [docs/release-checklist.md](./docs/release-checklist.md) |
| Changelog | [CHANGELOG.md](./CHANGELOG.md) |

---

<div align="center">

Released under the [MIT License](./LICENSE).

Made with ❤️ for the [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) community.

</div>
