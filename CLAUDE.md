# CLAUDE.md

## Project

AiOverviewControl is a self-contained DankMaterialShell widget for AI quota, billing, authentication, and local usage telemetry.

Runtime: QML/Quickshell plus Bash helpers. Core dependencies: `bash`, `jq`, and `curl`.

## Rules

- Do not mention an AI provider/model as coauthor in commits or pull requests.
- Keep provider failures isolated.
- Never fabricate quota percentages for providers without a documented surface.
- Prefer official CLI protocols and documented APIs; do not scrape authenticated dashboards.
- Keep the plugin self-contained and preserve user settings during upgrades.

## Data flow

1. Widget runs `providers/get-provider-usage <providers> <copilot-helper>`.
2. Dispatcher calls one local adapter per provider.
3. Every result follows `{provider, source, usage, credits, error}`.
4. Widget renders healthy and failed providers independently.
5. Claude analytics run separately from the main dispatcher.

## Settings

`refreshInterval`, `providerSelection`, `showErrorProviders`, `pillMode`, `pillProviders`, `densityMode`, `costCurrency`, `showClaudeProjects`, `languageOverride`.

## Validation

```bash
jq . plugin.json
bash -n providers/get-*
shellcheck providers/get-*
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-codex-usage | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
```

## Provider policy

See `docs/providers.md` for behavior and `docs/provider-verification.md` for upstream documentation links and evidence level.

## Release

Tag must match `plugin.json` and the changelog entry:

```bash
git tag v1.x.y
git push origin v1.x.y
```
