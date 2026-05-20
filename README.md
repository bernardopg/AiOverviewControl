<div align="center">

<img width="100%" alt="AiOverviewControl" src="https://capsule-render.vercel.app/api?type=wave&color=0:0F172A,45:2563EB,100:22C55E&height=220&section=header&text=AiOverviewControl&fontSize=52&fontColor=FFFFFF&animation=fadeIn&fontAlignY=36&desc=AI%20usage%20telemetry%20for%20Dank%20Material%20Shell&descSize=18&descAlignY=58" />

[![CI](https://img.shields.io/github/actions/workflow/status/bernardopg/AiOverviewControl/ci.yml?branch=main&label=CI&style=flat-square)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml)
[![CodeQL](https://img.shields.io/github/actions/workflow/status/bernardopg/AiOverviewControl/codeql.yml?branch=main&label=CodeQL&style=flat-square)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/codeql.yml)
[![Release](https://img.shields.io/github/v/tag/bernardopg/AiOverviewControl?label=Release&style=flat-square)](https://github.com/bernardopg/AiOverviewControl/releases)
[![License](https://img.shields.io/github/license/bernardopg/AiOverviewControl?style=flat-square)](LICENSE)
[![Crowdin](https://badges.crowdin.net/aioverviewcontrol/localized.svg)](https://crowdin.com/project/aioverviewcontrol)

**A self-contained Dank Material Shell widget for monitoring AI assistant usage, quota limits, reset windows, and provider health.**

[English](README.md) · [Português do Brasil](docs/README.pt-BR.md) · [Documentation](#-documentation) · [Report an issue](https://github.com/bernardopg/AiOverviewControl/issues/new/choose)

</div>

---

## ✨ What It Does

AiOverviewControl adds a compact telemetry panel to Dank Material Shell (DMS). It watches multiple AI providers, highlights the one closest to its quota limit in the DankBar, and opens a detailed dashboard with per-provider usage cards.

The plugin is designed to stay useful even when one provider fails: each provider is collected independently, so a broken Gemini, OpenRouter, Copilot, or Claude check does not hide working providers.

![AiOverviewControl screenshot](./screenshot.png)

## 🚀 Highlights

- 📊 **DankBar quota indicator** showing the provider closest to its limit.
- 🧩 **Floating dashboard** with usage cards, progress bars, reset windows, and isolated error states.
- 🛠️ **Self-contained local helpers** for Copilot, Claude Code, Codex fallbacks, and compatible providers.
- ⚙️ **Visual provider controls** so users can add or remove providers without editing JSON by hand.
- 🌍 **Crowdin-powered translations** using JSON locale files under `i18n/`.
- 🔒 **Repository hygiene** with CI, CodeQL, Dependabot, issue templates, discussions, and a security policy.

## 📦 Requirements

- Dank Material Shell running on Quickshell.
- Linux shell tools: `bash`, `node`, `jq`, and `curl`.
- Recommended fallback: `codexbar` available in `PATH`, `~/.local/bin`, `/usr/local/bin`, or configured in the plugin settings.
- Optional for Copilot: `gh auth login`, `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN`.
- Optional for Claude details: `claude`, `~/.claude/.credentials.json`, and local logs in `~/.claude/projects`.

## ⚡ Quick Start

Copy the plugin into your DMS plugins directory, make helper scripts executable, then restart DMS:

```bash
cd /path/to/downloaded/AiOverviewControl
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml \
  plugin.json qmldir get-* README.md CHANGELOG.md LICENSE docs i18n screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-*
dms restart
```

Then open DMS settings, enable **AiOverviewControl**, and add the widget to a DankBar section.

Full guide: [docs/installation.md](./docs/installation.md)

## ⚙️ Recommended Setup

| Setting | Recommended value | Why |
| ------- | ----------------- | --- |
| Provider Set | `codex,claude,copilot` | Good default coverage for local AI assistant usage. |
| Source Mode | `cli` | Uses local CLIs and native helpers first. |
| Show Provider Errors | `true` | Makes setup and provider debugging visible. |
| Refresh Interval | `120000` or `300000` | Keeps telemetry current without excessive polling. |

Configuration reference: [docs/configuration.md](./docs/configuration.md)

## 🤖 Provider Coverage

AiOverviewControl recognizes these provider IDs:

```text
codex, claude, copilot, gemini, openrouter, perplexity, cursor, kilo, kiro, ollama, warp, amp
```

Support depends on local credentials, provider APIs, bundled helper scripts, and optional `codexbar` fallback support.

| Provider | Collection path | Notes |
| -------- | --------------- | ----- |
| `codex` | `codexbar` fallback | Reads usage from compatible local CodexBar providers. |
| `claude` | `get-claude-usage` | Adds Claude Code analytics, windows, tokens, sessions, and estimated costs. |
| `copilot` | `get-copilot-usage` | Uses GitHub auth from `gh` or token environment variables. |
| `gemini`, `openrouter`, others | Native helpers or fallback | Coverage varies by provider API and local credentials. |

Provider matrix: [docs/providers.md](./docs/providers.md)

## 🧪 Validate Locally

From the repository root, use these commands to separate environment, authentication, and UI issues:

```bash
jq . plugin.json
bash -n get-provider-usage get-copilot-usage get-claude-usage
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
./get-provider-usage "$(command -v codexbar)" "codex,claude,copilot" "cli" ./get-copilot-usage
./get-copilot-usage
./get-claude-usage
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml
```

If a provider works in the terminal but not in the panel, start with [docs/troubleshooting.md](./docs/troubleshooting.md).

## 🗂️ Project Layout

| Path | Purpose |
| ---- | ------- |
| `AiOverviewControlWidget.qml` | DankBar indicator, popout dashboard, collection orchestration, and rendering. |
| `AiOverviewControlSettings.qml` | DMS settings UI. |
| `AiOverviewControlI18n.qml` | Translation loader and lookup helpers. |
| `get-provider-usage` | Unified provider backend and fallback dispatcher. |
| `get-copilot-usage` | GitHub Copilot usage bridge. |
| `get-claude-usage` | Claude Code local analytics and usage bridge. |
| `i18n/` | Locale JSON files managed with Crowdin. |
| `.github/` | CI, CodeQL, Dependabot, funding, templates, and community health files. |

Technical overview: [docs/architecture.md](./docs/architecture.md)

## 📚 Documentation

- 🇺🇸 Main README: [README.md](./README.md)
- 🇧🇷 Portuguese README: [docs/README.pt-BR.md](./docs/README.pt-BR.md)
- 🧭 Installation: [docs/installation.md](./docs/installation.md)
- ⚙️ Configuration: [docs/configuration.md](./docs/configuration.md)
- 🤖 Providers: [docs/providers.md](./docs/providers.md)
- 🌍 Crowdin and i18n: [docs/i18n-crowdin.md](./docs/i18n-crowdin.md)
- 🧱 Architecture: [docs/architecture.md](./docs/architecture.md)
- 🩺 Troubleshooting: [docs/troubleshooting.md](./docs/troubleshooting.md)

## 🤝 Contributing

Issues, provider reports, translations, and pull requests are welcome.

- Use [issue templates](https://github.com/bernardopg/AiOverviewControl/issues/new/choose) for bugs, features, and provider requests.
- Use [discussions](https://github.com/bernardopg/AiOverviewControl/discussions) for support and general questions.
- Report vulnerabilities through the repository security flow and follow [.github/SECURITY.md](./.github/SECURITY.md).
- For translations, see [docs/i18n-crowdin.md](./docs/i18n-crowdin.md).

## 💜 Support

If AiOverviewControl helps your DMS setup, you can support ongoing maintenance through GitHub Sponsors:

[![Sponsor](https://img.shields.io/badge/Sponsor-bernardopg-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/bernardopg)

## 📄 License

Released under the terms in [LICENSE](./LICENSE).

<img width="100%" alt="" src="https://capsule-render.vercel.app/api?type=wave&color=0:22C55E,45:2563EB,100:0F172A&height=110&section=footer" />
