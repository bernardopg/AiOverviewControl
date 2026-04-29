# AiOverviewControl

AiOverviewControl is a Dank Material Shell widget for tracking AI assistant usage in one place. It uses the CodexBar CLI for provider quota windows, includes native GitHub Copilot subscription usage, and embeds Claude Code analytics directly in the dashboard.

## What It Shows

- A compact DankBar pill for the provider closest to its limit.
- A large floating dashboard with one foldable card per provider.
- Dashboard controls for adding providers without editing JSON by hand.
- Per-card remove controls for providers you no longer want to poll.
- Provider windows for Codex, Claude, Copilot, and any other provider supported by your installed CodexBar build.
- Native Copilot usage through the authenticated GitHub Copilot API when CodexBar has no Linux fetch strategy.
- Partial-failure handling, so unsupported providers show an error card without hiding working providers.
- Claude Code details migrated from the standalone `claudeCodeUsage` plugin:
  - 5-hour and weekly subscription utilization
  - token consumption for week and month
  - estimated API-style cost from local Claude Code JSONL usage
  - daily activity bars
  - model mix for the current week
  - all-time sessions and message count

## Requirements

- Dank Material Shell on Quickshell
- `codexbar`
- `bash`, `node`, `jq`, `curl`, and `gh`
- Optional for Claude details: `claude` CLI with `~/.claude/.credentials.json` and local Claude Code project logs

## Install

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp plugin.json AiOverviewControlWidget.qml AiOverviewControlSettings.qml get-claude-usage get-copilot-usage LICENSE screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
dms restart
```

Enable **AiOverviewControl** in DMS Settings, then add it to a DankBar section.

## Recommended Settings On Linux

Use:

- Provider Set: `codex,claude,copilot`
- Source Mode: `cli`

CodexBar currently reports web dashboard fetching as macOS-only for some providers on Linux. `cli` works for the local Codex and Claude subscription telemetry tested here. Copilot is handled by `get-copilot-usage`, which reads the current GitHub authentication from `gh auth token` or standard GitHub token environment variables and calls the GitHub Copilot usage endpoint directly.

## Managing Providers

Use the dashboard **Provider control** row to add a provider from the known CodexBar provider list. The selection is saved to DMS plugin settings as a comma-separated `providerSelection` value.

For providers not listed in the dashboard dropdown, use Settings > Plugins > AiOverviewControl > **Custom provider list** and enter IDs such as:

```text
codex,claude,copilot,gemini,openrouter
```

## Local Validation Commands

```bash
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml
```

## Design Notes

The dashboard follows the existing DMS plugin language: token-driven colors, restrained cards, fast status scanning, and provider-specific accents. The top summary gives a quick operational read; detailed data stays inside foldable provider cards.
