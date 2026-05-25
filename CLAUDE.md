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
| `providers/get-provider-usage` | Unified shell backend — dispatches per-provider, returns JSON array |
| `providers/get-copilot-usage` | GitHub Copilot bridge via `gh auth token` or env tokens |
| `providers/get-claude-usage` | Claude Code analytics from `~/.claude` JSONL logs + optional OAuth |
| `plugin.json` | Plugin metadata, capabilities, permissions |

## Data Flow

1. Widget calls `providers/get-provider-usage` with `providerSelection`, `sourceMode`, optional `codexbarPath`, optional Copilot helper path.
2. Script dispatches per provider — local bridges first, `codexbar` fallback for others.
3. Returns JSON array. Each item: `{ provider, source, usage, credits, error }`.
4. Widget normalizes and renders cards. Errors become isolated cards — do not suppress healthy providers.
5. Provider with highest `usedPercent` drives the compact DankBar indicator.
6. For `claude`, widget may also spawn `providers/get-claude-usage` for 5h/7d windows, token counts, cost estimates.

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
~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-provider-usage \
  "$(command -v codexbar)" "codex,claude,copilot" "cli" \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-copilot-usage

# Test individual bridges
~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-claude-usage

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

## Provider Matrix

| ID | Name | Source | Env vars required | API endpoint |
|----|------|--------|-------------------|--------------|
| `codex` | Codex | codexbar → 9router fallback | — | codexbar CLI |
| `claude` | Claude | OAuth local + JSONL | `~/.claude/.credentials.json` | `api.anthropic.com/api/oauth/usage` |
| `copilot` | Copilot | GitHub API | `gh auth login` or `COPILOT_GITHUB_TOKEN` | `api.github.com/copilot_internal/user` |
| `gemini` | Gemini | OAuth local or API key | `GEMINI_API_KEY` or `~/.gemini/oauth_creds.json` | Validates key only |
| `openrouter` | OpenRouter | REST API | `OPENROUTER_API_KEY` | `openrouter.ai/api/v1/auth/key` |
| `9router` | 9Router | SQLite local | — | `~/.9router/db/data.sqlite` |
| `deepseek` | DeepSeek | REST API | `DEEPSEEK_API_KEY` | `api.deepseek.com/user/balance` |
| `kimi` | Kimi | REST API | `MOONSHOT_API_KEY` or `KIMI_API_KEY` | `api.moonshot.cn/v1/users/me/balance` |
| `mistral` | Mistral | API key validation only | `MISTRAL_API_KEY` | `api.mistral.ai/v1/models` (no quota endpoint) |
| `glm` | GLM/Zhipu | REST API | `GLM_API_KEY` or `ZHIPU_API_KEY` | `bigmodel.cn/api/monitor/usage/quota/limit` |
| `minimax` | MiniMax | REST API | `MINIMAX_API_KEY` | `minimax.io/v1/token_plan/remains` |
| `qwen` | Qwen | API key validation only | `DASHSCOPE_API_KEY` or `QWEN_API_KEY` | No quota endpoint — UI only |
| `nvidia` | NVIDIA NIM | API key validation only | `NVIDIA_API_KEY` | No quota endpoint — UI only |
| `cloudflare` | Cloudflare AI | REST API | `CLOUDFLARE_AI_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | `api.cloudflare.com/v4/accounts/{id}/ai/usage` |
| `vertexai` | Vertex AI | gcloud OAuth | `gcloud auth login` | gcloud local auth check |
| `byteplus` | BytePlus Ark | API key validation only | `BYTEPLUS_API_KEY` or `ARK_API_KEY` | No quota endpoint — UI only |
| `ollama` | Ollama | Local HTTP | `OLLAMA_HOST` (default: localhost:11434) | `localhost:11434/api/tags` |
| `perplexity` | Perplexity | codexbar or note | — | No public quota endpoint |
| `cursor` | Cursor | codexbar or note | — | No public quota endpoint |
| `cline` | Cline | note | — | No REST endpoint |
| `opencode` | OpenCode | note | — | Proxy only, no billing |
| `kilo` | Kilo | codexbar or note | — | No public quota endpoint |
| `kiro` | Kiro | codexbar or note | — | No public quota endpoint |
| `warp` | Warp | codexbar or note | — | No public quota endpoint |
| `amp` | Amp | codexbar or note | — | No public quota endpoint |

**Providers not implemented (no API, ToS issues):** Antigravity (Google, ToS violation risk).

## Design Constraints

- Plugin must be self-contained — no imports from other DMS plugins.
- Per-provider isolation: one provider failure must not hide others.
- New provider bridges must output `provider/source/usage/credits/error` schema.
- Collection timeout: 45 seconds. Exceeded → show timeout error, discard stale output.
- Follow DMS theme tokens and Quickshell UI patterns for visual consistency.

## Design Context

### Users
Power users and developers using Dank Material Shell as a daily desktop control surface. They need to glance at AI assistant quota health while switching between CLIs, editors, and providers.

### Brand Personality
Refined, premium, calm. The interface should feel like a dependable shell instrument: compact, readable, and direct, without marketing-style decoration.

### Aesthetic Direction
Dark, token-driven DMS styling with restrained provider accents. Prefer layered surfaces, precise spacing, and a premium control-surface feel that adapts from narrow popouts to larger desktop panels without hiding core actions.

### Design Principles
- Make provider health scannable first, details second.
- Keep every dependency local to AiOverviewControl unless it is an explicit external CLI/API fallback.
- Use responsive component reflow instead of fixed desktop-only rows.
- Treat errors as actionable provider states, not global failure.
- Preserve DMS theme tokens and interaction patterns for consistency with the shell.
- Keep motion subtle, purposeful, and calm.
