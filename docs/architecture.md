# Architecture

AiOverviewControl is a widget plugin for Dank Material Shell (DMS). The UI, local helper scripts and metadata are kept inside the plugin directory to avoid tight coupling with other plugins.

## Key files

```text
plugin.json
AiOverviewControlWidget.qml
AiOverviewControlSettings.qml
get-copilot-usage
get-claude-usage
get-provider-usage
README.md
docs/
CHANGELOG.md
LICENSE
```

## Metadata

`plugin.json` declares:

- `id`: `aiOverviewControl`
- `type`: `widget`
- `component`: `./AiOverviewControlWidget.qml`
- `settings`: `./AiOverviewControlSettings.qml`
- capabilities: `dankbar-widget` and `process`
- permissions: read/write settings and execute processes

## Data flow

1. On load the widget checks whether `get-provider-usage` is executable.
2. If available, it triggers `refresh()`.
3. `refresh()` calls `get-provider-usage` with `providerSelection`, `sourceMode`, optional `codexbar` path and helper scripts.
4. The helper calls native adapters or `codexbar`, depending on the provider.
5. For `claude`, the widget may also spawn `get-claude-usage` to gather extra analytics.
6. Each response is normalized into a provider list.
7. Errors become independent cards and do not remove healthy providers.
8. The popout filters providers according to `showErrorProviders`.

## Expected visual model

Each provider item may expose:

```text
provider
source
usage.identity.accountEmail
usage.identity.loginMethod
usage.primary
usage.secondary
usage.tertiary
credits.remaining
error
```

Usage windows follow this format:

```text
usedPercent
windowMinutes
resetsAt
resetDescription
remaining
unlimited
hasQuota
```

The dashboard chooses the provider with the highest successful `usedPercent` for the compact indicator and the top summary.

## QML processes

`AiOverviewControlWidget.qml` uses `Quickshell.Io Process` to:

- detect local helpers and optional `codexbar` path
- fetch provider usage
- fetch extra Claude analytics

Collection timeout is 45 seconds. If a process exceeds that timeout the widget shows a timeout error and avoids reusing stale output.

## Persisted settings

Settings keys used by the plugin:

```text
refreshInterval
codexbarPath
providerSelection
sourceMode
showErrorProviders
```

These keys are stored in the DMS settings store. Updating plugin files should not overwrite user preferences.

## Plugin isolation

AiOverviewControl does not import UI components from other local plugins. External dependencies are:

- Dank Material Shell APIs and UI components
- Quickshell for processes and UI
- optional `codexbar` executable for Codex and providers without a local bridge
- provider CLIs and local files

Removing or disabling another DMS plugin (for example CodexBar) should not break this widget. For providers that rely on the CodexBar fallback, keep a system `codexbar` installed.

## Local scripts

### `get-copilot-usage`

Transforms GitHub Copilot usage into JSON compatible with widget cards.

Input:

- token via `gh auth token`
- or `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`

Output:

- provider `copilot`
- source `github-copilot-api`
- windows for Premium, Chat and Completions
- remaining credits when available
- `error` JSON object when missing token or API failure

### `get-provider-usage`

Unified local backend for providers.

Input:

- optional `codexbar` path
- CSV of providers
- source mode
- optional path to the Copilot helper

Output:

- JSON array with one item per provider
- common structure `provider/source/usage/credits/error` used by the cards

Known fallbacks:

- Copilot via `get-copilot-usage`
- Claude via `codexbar` with fallback to `get-claude-usage`
- Gemini via `codexbar` or local API key/credentials fallback
- OpenRouter via `OPENROUTER_API_KEY` or `codexbar`
- other providers via `codexbar`

### `get-claude-usage`

Provides extra Claude Code details.

Input:

- `~/.claude/.credentials.json`
- `~/.claude/projects/**/*.jsonl`
- `~/.claude/stats-cache.json`
- optional network access for pricing/models and FX rates

Output:

- KEY=VALUE pairs read by QML
- 5-hour and 7-day usage windows
- tokens, sessions, messages and estimated costs
- caches under `~/.claude`

## Maintenance principles

- Preserve per-provider isolation.
- Avoid depending on files from other plugins.
- Prefer structured JSON errors in helper scripts.
- When adding a provider bridge, keep its output compatible with `provider/source/usage/credits/error`.
- Document recommended sources and validation commands in [providers.md](./providers.md).

---

# Arquitetura (PT-BR)

O conteúdo desta página na versão em inglês acima descreve a arquitetura do plugin. Abaixo estão as notas originais em Português.

<!-- O conteúdo original em Português foi preservado na versão anterior do repositório. -->
