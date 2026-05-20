# Architecture

AiOverviewControl is a self-contained widget plugin for Dank Material Shell (DMS). All UI, helper scripts and metadata live inside the plugin directory with no runtime dependency on other DMS plugins.

## File layout

```text
plugin.json                         Plugin metadata
AiOverviewControlWidget.qml         Main widget UI and logic
AiOverviewControlSettings.qml       Settings panel
get-provider-usage                  Unified provider backend (bash)
get-claude-usage                    Claude Code analytics backend (bash)
get-copilot-usage                   GitHub Copilot bridge (bash)
docs/                               Documentation
CHANGELOG.md
LICENSE
README.md
TODO.md
```

## Plugin metadata

`plugin.json` declares:

- `id`: `aiOverviewControl`
- `type`: `widget`
- `component`: `./AiOverviewControlWidget.qml`
- `settings`: `./AiOverviewControlSettings.qml`
- capabilities: `dankbar-widget`, `process`
- permissions: read/write settings, execute processes

## Data flow

```
QML widget
  │
  ├─ on load: check get-provider-usage executable
  │
  ├─ refresh()
  │    │
  │    └─ spawn: get-provider-usage <codexbar> <providers> <sourceMode> <copilot-helper>
  │              │
  │              ├─ copilot       → get-copilot-usage
  │              ├─ claude        → codexbar usage  ──fallback──→ get-claude-usage
  │              ├─ gemini        → codexbar usage  ──fallback──→ GEMINI_API_KEY / ~/.gemini
  │              ├─ 9router       → ~/.9router/db/data.sqlite (SQLite, no API)
  │              ├─ openrouter    → OPENROUTER_API_KEY  ──fallback──→ 9router local DB
  │              ├─ deepseek      → api.deepseek.com/user/balance
  │              ├─ kimi/moonshot → api.moonshot.cn/v1/users/me/balance
  │              ├─ minimax       → www.minimax.io/v1/token_plan/remains
  │              ├─ glm/zhipu     → bigmodel.cn/api/monitor/usage/quota/limit
  │              ├─ mistral       → api.mistral.ai/v1/models (key validation only)
  │              ├─ ollama        → {OLLAMA_HOST}/api/tags
  │              ├─ nvidia/nim    → integrate.api.nvidia.com/v1/models (key validation)
  │              ├─ cloudflare    → api.cloudflare.com/…/ai/usage
  │              ├─ vertexai      → gcloud auth print-access-token (check only)
  │              ├─ byteplus/ark  → ark.ap-southeast.bytepluses.com/api/v3/models (key validation)
  │              ├─ qwen/dashscope→ dashscope.aliyuncs.com/…/models (key validation)
  │              └─ others        → codexbar usage --provider <id>
  │
  └─ claude extra analytics
       └─ spawn: get-claude-usage   → ~/.claude/projects/**/*.jsonl + OAuth API
```

## Provider output schema

Every provider item in the JSON array must conform to:

```json
{
  "provider": "string",
  "source": "string",
  "usage": {
    "identity": {
      "accountEmail": "string",
      "loginMethod": "string"
    },
    "primary":   { "usedPercent": 0, "windowMinutes": 0, "resetsAt": "...", "resetDescription": "...", "remaining": 0, "unlimited": false, "hasQuota": true, "displayValue": "..." },
    "secondary": { ... },
    "tertiary":  { ... },
    "updatedAt": "ISO8601"
  },
  "credits": {
    "remaining": 0,
    "currency": "USD"
  },
  "error": null
}
```

Error path (replaces `usage` and `credits`):

```json
{
  "provider": "string",
  "source": "string",
  "error": {
    "code": "string",
    "message": "string"
  }
}
```

Providers without a quota API use `json_note_usage` which fills `usage.primary` with `unlimited: true` and a `displayValue` note string. This is distinct from an error.

## Provider count

25 provider IDs are registered in `availableProviderOptions`:

```text
codex, claude, copilot, gemini, 9router, openrouter,
deepseek, kimi, mistral, glm, minimax, qwen, nvidia,
cloudflare, vertexai, byteplus, ollama, perplexity,
cursor, cline, opencode, kilo, kiro, warp, amp
```

## QML processes

`AiOverviewControlWidget.qml` uses `Quickshell.Io Process` to:

- detect local helpers and optional `codexbar` path on load
- run `get-provider-usage` on each refresh
- run `get-claude-usage` for Claude extra analytics

Process timeout: 45 seconds. Exceeded timeout produces a timeout error card and discards partial output.

## Persisted settings

```text
refreshInterval       ms between automatic refreshes
codexbarPath          absolute path to codexbar binary (optional)
providerSelection     comma-separated provider ID list
sourceMode            cli | auto | oauth | api | web
showErrorProviders    boolean — show/hide error cards
```

These are stored in the DMS settings store and are not overwritten by plugin updates.

## Helper scripts

### `get-provider-usage`

Arguments: `<codexbar-path> <provider-csv> <source-mode> <copilot-helper-path>`

Iterates providers sequentially. Each provider dispatched by `fetch_provider()` case statement. Helper functions:

- `fetch_copilot_native()` — calls `get-copilot-usage`
- `fetch_claude_native()` — reads `get-claude-usage` output
- `fetch_gemini_native()` — GEMINI_API_KEY or `~/.gemini` credentials
- `fetch_9router_native()` — SQLite query via `sqlite3`
- `fetch_openrouter_native()` — OPENROUTER_API_KEY REST call
- `fetch_deepseek_native()` — DEEPSEEK_API_KEY balance endpoint
- `fetch_kimi_native()` — MOONSHOT_API_KEY / KIMI_API_KEY balance endpoint
- `fetch_minimax_native()` — MINIMAX_API_KEY token-plan endpoint
- `fetch_glm_native()` — GLM_API_KEY / ZHIPU_API_KEY quota endpoint
- `fetch_mistral_native()` — MISTRAL_API_KEY key validation → note-card
- `fetch_ollama_native()` — local /api/tags → model list
- `fetch_nvidia_native()` — NVIDIA_API_KEY key validation → note-card
- `fetch_cloudflare_native()` — CLOUDFLARE_AI_TOKEN + CLOUDFLARE_ACCOUNT_ID
- `fetch_vertexai_native()` — gcloud auth check → note-card
- `fetch_byteplus_native()` — BYTEPLUS_API_KEY / ARK_API_KEY key validation → note-card
- `fetch_qwen_native()` — DASHSCOPE_API_KEY / QWEN_API_KEY key validation → note-card
- `try_codexbar()` — codexbar fallback for any provider
- `json_note_usage()` — structured note card for providers without quota APIs
- `json_error()` — structured error card

### `get-claude-usage`

- Reads `~/.claude/.credentials.json` for OAuth token
- Calls `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`
- Parses `five_hour.utilization`, `seven_day.utilization`, `resets_at`
- Scans `~/.claude/projects/**/*.jsonl` via `jq` + `awk` for token counts and cost estimates
- Fetches LiteLLM model prices and USD→EUR rate if network available
- Caches results in `~/.claude/usage-cache.json` and `~/.claude/pricing-cache.json`
- Output: KEY=VALUE pairs consumed by QML

### `get-copilot-usage`

- Auth: `gh auth token` → `COPILOT_GITHUB_TOKEN` → `GH_TOKEN` → `GITHUB_TOKEN`
- API: `GET https://api.github.com/copilot_internal/user` with `X-Github-Api-Version: 2025-04-01`
- Maps `quota_snapshots.{premium_interactions,chat,completions}` to primary/secondary/tertiary windows
- Output: single JSON provider item

## Plugin isolation

No imports from other DMS plugins at runtime. External dependencies:

- DMS APIs and UI components
- Quickshell (processes and UI primitives)
- Optional `codexbar` executable for Codex and codexbar-only providers
- Provider CLIs (`gcloud`, `gh`, `sqlite3`) when relevant
- `curl`, `jq`, `bash` — assumed present on Linux

Removing or disabling another DMS plugin does not break this widget.

## Maintenance principles

- Keep per-provider isolation: one provider failure must not affect others.
- Output from every `fetch_*` function must be valid JSON matching the provider schema.
- Use `json_note_usage` for providers with no quota API rather than returning an error.
- Document env vars, endpoints and test commands in [providers.md](./providers.md) for every new provider.
- Run `shellcheck get-provider-usage get-claude-usage get-copilot-usage` before committing changes to helper scripts.
