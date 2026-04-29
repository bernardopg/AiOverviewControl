# AiOverviewControl

A DMS widget for monitoring AI assistant usage through the CodexBar CLI.

It started from the CodexBar DMS plugin, but is renamed and expanded to query multiple providers independently so one unsupported provider does not hide the usage data that works.

## Features

- DankBar pill showing the highest active usage percentage
- Popout with usage windows, reset timers, identity/runtime details, and provider status
- Provider sets for Codex, Claude, Copilot, Gemini, OpenRouter, Perplexity, and other CodexBar providers
- Source modes exposed directly: `cli`, `auto`, `oauth`, `api`, and `web`
- Linux-friendly default: `cli`, because CodexBar currently reports some web dashboard fetchers as macOS-only
- Partial failure handling for providers that are not supported by the selected source

## Requirements

- Dank Material Shell on Quickshell
- `codexbar` installed and available on `PATH`, `~/.local/bin/codexbar`, `/usr/local/bin/codexbar`, or configured in plugin settings

## Install

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp plugin.json AiOverviewControlWidget.qml AiOverviewControlSettings.qml LICENSE screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
```

Restart Quickshell/DMS, enable **AiOverviewControl**, then add it to a DankBar section.

## Local validation

On this Linux setup, these commands returned usage data:

```bash
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
```

`--source auto` attempted web fetching and returned CodexBar's macOS-only web support error. Copilot is accepted by the plugin, but the installed CodexBar build currently reports no available Copilot fetch strategy for the tested source.
