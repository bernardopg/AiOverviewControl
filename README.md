<div align="center">

<img src="./docs/assets/logo.png" alt="AiOverviewControl mascot" width="140" />

# AiOverviewControl

**Every AI quota you pay for, live in your DankBar.**

A [DankMaterialShell](https://github.com/duxlabs-dev/dux-shell) plugin that tracks
quota, billing, authentication, and local usage for 43 AI providers — locally, honestly,
with no external service.

[![Release](https://img.shields.io/github/v/release/bernardopg/AiOverviewControl?color=8B5CF6&label=release)](https://github.com/bernardopg/AiOverviewControl/releases/latest)
[![DMS](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fbernardopg%2FAiOverviewControl%2Fmain%2Fplugin.json&query=%24.requires_dms&label=DMS&color=7C3AED)](./docs/installation.md)
[![CI](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml/badge.svg)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml)
[![Security](https://github.com/bernardopg/AiOverviewControl/actions/workflows/security.yml/badge.svg)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/bernardopg/AiOverviewControl/badge)](https://scorecard.dev/viewer/?uri=github.com/bernardopg/AiOverviewControl)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15913/badge)](https://www.bestpractices.dev/projects/15913)
[![providers](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fbernardopg%2FAiOverviewControl%2Fmain%2Fdocs%2Fbadges.json&query=%24.providers&label=providers&color=8B5CF6)](./docs/providers.md)
[![languages](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fbernardopg%2FAiOverviewControl%2Fmain%2Fdocs%2Fbadges.json&query=%24.languages&label=languages&color=00BFA5)](./docs/i18n-crowdin.md)
[![Downloads](https://img.shields.io/github/downloads/bernardopg/AiOverviewControl/total?color=0EA5E9&label=downloads)](https://github.com/bernardopg/AiOverviewControl/releases)
[![License](https://img.shields.io/github/license/bernardopg/AiOverviewControl?color=64748B)](./LICENSE)

[**Demo**](#-demo) · [**Install**](#-quick-start) · [**Screenshots**](#-a-closer-look) · [**Providers**](./docs/providers.md) · [**Docs**](#-documentation) · [**Support**](#-support-the-project) · [Português](./docs/README.pt-BR.md)

<br />

<img src="./docs/assets/banner.jpg" alt="AiOverviewControl" width="100%" />

</div>

## 🎬 Demo

<div align="center">

<img src="./docs/assets/demo.gif" alt="AiOverviewControl demo" width="100%" />

<sub><a href="./docs/assets/demo.mp4">Full-quality MP4</a></sub>

</div>

## ✨ Why AiOverviewControl

You pay for Claude, Codex, Copilot, OpenRouter… and each one hides its quota in a
different dashboard, CLI, or API. AiOverviewControl reads every provider
**independently and on your machine**, then shows one overview.

It reports measured data when a real source exists, and says plainly when a
provider is authentication-only or informational. No dashboard scraping. No
invented percentages.

## 🚀 Features

<table>
<tr>
<td width="50%" valign="top">

**📊 One dashboard, 43 providers**<br />
Quota, balance, analytics, and auth status side by side, with a fleet overview
of average load, hottest provider, and next reset.

</td>
<td width="50%" valign="top">

**🎯 A pill that tells the truth**<br />
Pick which quota window each provider shows in the bar, or follow the
most-constrained one, as used or as remaining quota. Hover for the window
and reset time. Crowded bar? Drop the names and tighten the spacing.

</td>
</tr>
<tr>
<td valign="top">

**🤖 Deep local telemetry**<br />
Claude, Codex, 9Router, pi, and Hermes add token, cost, model, and project
analytics with a seven-day chart — read from data already on your disk. Track
several Claude accounts side by side, each from its own `CLAUDE_CONFIG_DIR`.
Claude and Codex also show credits, extra usage and limit resets, and can
redeem a held reset after a confirmation.

</td>
<td valign="top">

**🔔 Quota alerts**<br />
Desktop notifications at 75, 85, or 95% — or per-provider thresholds — updated
in place instead of spamming. Click one to open that provider's card. A
DankDash card keeps the busiest providers in the overview.

</td>
</tr>
<tr>
<td valign="top">

**🛡️ Private and resilient**<br />
Secrets are never shown. One failing provider never hides the healthy ones.
No paid endpoints are called to test a key.

</td>
<td valign="top">

**🌍 Five languages**<br />
English, Português (Brasil), Español, Deutsch, and 简体中文 — including every
label the provider adapters emit.

</td>
</tr>
</table>

## 📸 A closer look

<table>
<tr>
<td align="center" width="50%"><img src="./docs/assets/settings.png" alt="Settings window" /><br /><sub><b>Settings window</b> — also available in DMS Settings → Plugins</sub></td>
<td align="center" width="50%"><img src="./docs/assets/about.png" alt="About window" /><br /><sub><b>About</b> — version, developer, and ways to support the project</sub></td>
</tr>
</table>

## ⚡ Quick start

> [!IMPORTANT]
> AiOverviewControl 2.0 requires **DMS 2.0 or newer**. On DMS 1.6, stay on
> [1.22.0](https://github.com/bernardopg/AiOverviewControl/releases/tag/v1.22.0)
> until your distribution ships DMS 2.0.

**1. Install** from the DMS plugin store:

```bash
dms plugins install aiOverviewControl
```

Or search for **AiOverviewControl** in DMS Settings → Plugins, or in the
[DMS plugin directory](https://duxlabs.dev/plugins).

**2. Add the widget** to a DankBar section in DMS settings.

**3. Sign in** to the providers you use. The default set needs:

```bash
command -v bash jq curl codex claude gh
codex login && claude auth status && gh auth status
```

Open the ⚙ settings window to enable more providers — each one shows whether
its CLI or credential is ready.

> [!TIP]
> Bind the dashboard to a shortcut: `dms ipc call aiOverviewControl toggle`.
> See [Usage](./docs/usage.md#ipc-commands) for all commands.

Prefer a release archive or a git checkout? See [Installation](./docs/installation.md).

## 🧩 Providers

| Coverage           | What you get                             | Examples                                                |
| ------------------ | ---------------------------------------- | ------------------------------------------------------- |
| **Quota**          | Real usage % and reset time              | Codex, Copilot, Antigravity, OpenRouter, Z.ai, GLM, xAI, Gemini CLI |
| **Balance**        | Remaining prepaid credit                 | Kimi, DeepSeek, Neuralwatt, Cline, Ollama Cloud, Vercel AI Gateway |
| **Analytics**      | Tokens, cost, and models from local data or spend reports | Claude, 9Router, pi, Hermes, Cloudflare, Anthropic API, OpenAI API |
| **Authentication** | Credential check, no usage numbers       | Gemini, Mistral, Qwen, Groq, Cohere                     |
| **Local runtime**  | Local models and sessions                | Ollama, Vertex AI                                       |
| **Informational**  | A link to the official usage page        | Cursor, Kiro, Warp, Perplexity                          |

The full list, data sources, and credentials are in [Providers](./docs/providers.md).

> **Privacy:** every credential is sent only to its own provider's official API.
> The plugin makes exactly two optional third-party calls, both documented with
> opt-outs (`AIOC_NO_LITELLM=1`, `AIOC_NO_DOH_FALLBACK=1`), and writes caches
> only under `${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl/`. See
> [Network endpoints](./docs/usage.md#network-endpoints) and the
> [Antigravity access mechanism](./docs/usage.md#antigravity-access-mechanism).

## 📚 Documentation

For the latest release, start with the [2.0.0 changes guide](./docs/releases/2.0.0.md).
See [cost currency and privacy](./docs/currency.md), [runtime module boundaries](./docs/refactoring.md),
and [protected PR/release rules](./docs/repository-rules.md).

|                                              |                                                      |
| -------------------------------------------- | ---------------------------------------------------- |
| [Usage](./docs/usage.md)                     | Pill, popout, cards, keyboard, IPC, history, privacy |
| [Installation](./docs/installation.md)       | Store, archive, and git installs; upgrades           |
| [Configuration](./docs/configuration.md)     | Every setting, environment variables, health checks  |
| [Providers](./docs/providers.md)             | Coverage matrix and per-provider data sources        |
| [Troubleshooting](./docs/troubleshooting.md) | Missing cards, credentials, notifications            |
| [Architecture](./docs/architecture.md)       | Runtime flow and the adapter contract                |
| [Translations](./docs/i18n-crowdin.md)       | Locales and Crowdin                                  |
| [Contributing](./CONTRIBUTING.md)            | Local checks and conventions                         |
| [Governance](./GOVERNANCE.md)                | Decisions, roles, code review, continuity            |
| [Roadmap](./docs/roadmap.md)                 | What is planned for the next year, and what is not   |
| [Security model](./docs/security.md)         | Security requirements and assurance case             |
| [Security policy](./.github/SECURITY.md)     | Reporting vulnerabilities, verifying releases        |
| [Code of conduct](./CODE_OF_CONDUCT.md)      | Contributor Covenant 2.1                             |
| [Changelog](./CHANGELOG.md)                  | Release history                                      |

## 💜 Support the project

The [DMS plugin directory](https://duxlabs.dev/plugins) ranks plugins by the 👍
reactions on their registry issue. One reaction is the most useful thing you can
do — it decides whether other DankMaterialShell users ever find the plugin.

<div align="center">

[![Upvote on DMS Plugins](https://img.shields.io/badge/DMS%20Plugins-%F0%9F%91%8D%20upvote-8B5CF6?style=for-the-badge)](https://github.com/duxlabs-dev/dux-plugin-registry/issues/358)
[![Star on GitHub](https://img.shields.io/github/stars/bernardopg/AiOverviewControl?style=for-the-badge&color=FFC400&label=star)](https://github.com/bernardopg/AiOverviewControl/stargazers)

[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/bernardopg)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?style=for-the-badge&logo=kofi&logoColor=white)](https://ko-fi.com/bernardopg)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/wctwom9emu)

</div>

Found a bug or have an idea? [Open an issue](https://github.com/bernardopg/AiOverviewControl/issues/new/choose).

## 👥 Contributors

<div align="center">

<!-- CONTRIBUTORS:START - generated by scripts/render-contributors -->

<a href="https://github.com/bernardopg" title="bernardopg"><img src="https://avatars.githubusercontent.com/u/69475128?v=4&s=112" width="56" height="56" alt="bernardopg" /></a>
<a href="https://github.com/gtheys" title="gtheys"><img src="https://avatars.githubusercontent.com/u/527237?v=4&s=112" width="56" height="56" alt="gtheys" /></a>
<a href="https://github.com/Luna161" title="Luna161"><img src="https://avatars.githubusercontent.com/u/268031236?v=4&s=112" width="56" height="56" alt="Luna161" /></a>
<a href="https://github.com/arqueon" title="arqueon"><img src="https://avatars.githubusercontent.com/u/66568719?v=4&s=112" width="56" height="56" alt="arqueon" /></a>
<a href="https://github.com/goulartdev" title="goulartdev"><img src="https://avatars.githubusercontent.com/u/16469407?v=4&s=112" width="56" height="56" alt="goulartdev" /></a>
<a href="https://github.com/emmsixx" title="emmsixx"><img src="https://avatars.githubusercontent.com/u/56744133?v=4&s=112" width="56" height="56" alt="emmsixx" /></a>
<a href="https://github.com/Murat65536" title="Murat65536"><img src="https://avatars.githubusercontent.com/u/99989538?v=4&s=112" width="56" height="56" alt="Murat65536" /></a>
<a href="https://github.com/ReillyBrogan" title="ReillyBrogan"><img src="https://avatars.githubusercontent.com/u/4309817?v=4&s=112" width="56" height="56" alt="ReillyBrogan" /></a>
<a href="https://github.com/gouwazi" title="gouwazi"><img src="https://avatars.githubusercontent.com/u/23072555?v=4&s=112" width="56" height="56" alt="gouwazi" /></a>
<a href="https://github.com/UN-9BOT" title="UN-9BOT"><img src="https://avatars.githubusercontent.com/u/111110804?v=4&s=112" width="56" height="56" alt="UN-9BOT" /></a>
<a href="https://github.com/SkippySteve" title="SkippySteve"><img src="https://avatars.githubusercontent.com/u/69158610?v=4&s=112" width="56" height="56" alt="SkippySteve" /></a>
<a href="https://github.com/ianptkcs" title="ianptkcs"><img src="https://avatars.githubusercontent.com/u/162713721?v=4&s=112" width="56" height="56" alt="ianptkcs" /></a>

<!-- CONTRIBUTORS:END -->

Contributions are welcome — start with [CONTRIBUTING.md](./CONTRIBUTING.md).

</div>

---

<div align="center">
<sub>MIT License · made with 💜 for the <a href="https://github.com/duxlabs-dev/dux-shell">DankMaterialShell</a> community</sub>
</div>
