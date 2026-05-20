# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Cooauthor
Do not mention the AI provider/model as a cooauthor in the commit message or PR description.

## Project Overview

DMS widget plugin that monitors AI provider quota health. Shows most-limited provider in DankBar pill; floating dashboard with per-provider cards.

**Runtime stack:** QML (Quickshell), bash helper scripts, optional `codexbar` CLI fallback.

**Key dependencies:** `bash`, `node`, `jq`, `curl`. Optional: `codexbar`, `gh` (Copilot), `claude` CLI.

## Key Files

| File | Role |
|------|------|
| `AiOverviewControlWidget.qml` | DankBar pill, popout dashboard, QML data collection and normalization |
| `AiOverviewControlSettings.qml` | DMS settings UI |
| `get-provider-usage` | Unified shell backend — dispatches per-provider, returns JSON array |
| `get-copilot-usage` | GitHub Copilot bridge via `gh auth token` or env tokens |
| `get-claude-usage` | Claude Code analytics from `~/.claude` JSONL logs + optional OAuth |
| `plugin.json` | Plugin metadata, capabilities, permissions |

## Data Flow

1. Widget calls `get-provider-usage` with `providerSelection`, `sourceMode`, optional `codexbarPath`, optional Copilot helper path.
2. Script dispatches per provider — local bridges first, `codexbar` fallback for others.
3. Returns JSON array. Each item: `{ provider, source, usage, credits, error }`.
4. Widget normalizes and renders cards. Errors become isolated cards — do not suppress healthy providers.
5. Provider with highest `usedPercent` drives the compact DankBar indicator.
6. For `claude`, widget may also spawn `get-claude-usage` for 5h/7d windows, token counts, cost estimates.

## Provider Output Schema

```text
provider / source / error
usage.identity.accountEmail
usage.primary / secondary / tertiary
  usedPercent, windowMinutes, resetsAt, resetDescription, remaining, unlimited, hasQuota
credits.remaining
```

## Settings Keys

`refreshInterval`, `codexbarPath`, `providerSelection`, `sourceMode`, `showErrorProviders`

Stored in DMS settings store — never overwrite user preferences when updating plugin files.

## Validation Commands

```bash
# Lint QML
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml || true

# Validate plugin metadata
jq . plugin.json

# Test data pipeline end-to-end
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage \
  "$(command -v codexbar)" "codex,claude,copilot" "cli" \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage

# Test individual bridges
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage

# Test via codexbar fallback
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
```

## Release

Releases trigger on `v*` tags. CI runs on push/PR to `main` (validates `plugin.json` + optional `qmllint`).

```bash
git tag v1.x.y && git push origin v1.x.y
```

Artifacts: `AiOverviewControl-vX.Y.Z.zip` and `.tar.gz` built from `git ls-files`.

## Design Constraints

- Plugin must be self-contained — no imports from other DMS plugins.
- Per-provider isolation: one provider failure must not hide others.
- New provider bridges must output `provider/source/usage/credits/error` schema.
- Collection timeout: 45 seconds. Exceeded → show timeout error, discard stale output.
- Follow DMS theme tokens and Quickshell UI patterns for visual consistency.
