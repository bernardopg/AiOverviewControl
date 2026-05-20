# Configuration

Settings live in **DMS Settings → Plugins → AiOverviewControl**. Providers can also be added and removed directly from the dashboard.

---

## Settings

### Refresh Interval

Milliseconds between automatic refreshes.

```text
60000    1 minute
120000   2 minutes   ← recommended for active monitoring
300000   5 minutes
900000   15 minutes
1800000  30 minutes
```

Increase when many providers are configured, the network is slow, or API rate limits are a concern.

### Optional fallback (codexbar path)

Absolute path to the `codexbar` executable. Leave empty to auto-detect from `PATH`, `~/.local/bin/codexbar` and `/usr/local/bin/codexbar` in that order.

Required only for providers without a native adapter: `codex`, `perplexity`, `cursor`, `kilo`, `kiro`, `warp`, `amp`, `cline`, `opencode`. All other providers use local adapters.

Example:

```text
/home/user/.local/bin/codexbar
```

### Provider Set

Comma-separated list of provider IDs. Recognized IDs:

```text
codex        claude       copilot      gemini
9router      openrouter   deepseek     kimi
mistral      glm          minimax      qwen
nvidia       cloudflare   vertexai     byteplus
ollama       perplexity   cursor       cline
opencode     kilo         kiro         warp
amp
```

Examples:

```text
claude,copilot
claude,copilot,deepseek
claude,copilot,gemini,9router,openrouter,deepseek,kimi
```

The plugin normalizes IDs to lower-case, trims spaces and removes duplicates.

### Fallback source mode

Mode passed to `codexbar` for providers that use it.

```text
cli    best default on Linux (local telemetry, no outbound requests)
auto   let codexbar choose
oauth  use OAuth where supported
api    use API tokens configured in codexbar
web    use web dashboard scraping (may be macOS-only for some providers)
```

Use `cli` for local-only providers (Codex). Use `api` when API tokens are configured in codexbar for API-based providers. Native adapters (Claude, Copilot, DeepSeek, Kimi, etc.) ignore this setting and use their own auth.

### Show Provider Errors

`true` — show error cards with the failure reason. Recommended while configuring.  
`false` — hide error cards. Use for a clean dashboard after stable configuration.

---

## Environment variables

Set these for providers with native adapters. The plugin reads them at refresh time via the shell environment that DMS inherits.

| Provider | Variable | Notes |
|----------|----------|-------|
| OpenRouter | `OPENROUTER_API_KEY` | Falls back to 9Router local DB when unset |
| DeepSeek | `DEEPSEEK_API_KEY` | `sk-...` prefix |
| Kimi / Moonshot | `MOONSHOT_API_KEY` or `KIMI_API_KEY` | Either accepted |
| MiniMax | `MINIMAX_API_KEY` | |
| GLM / Zhipu | `GLM_API_KEY` or `ZHIPU_API_KEY` | Set `GLM_API_BASE` for alt endpoint |
| Mistral | `MISTRAL_API_KEY` | Key validated only (no quota endpoint) |
| NVIDIA NIM | `NVIDIA_API_KEY` | `nvapi-...` prefix; key validated only |
| Cloudflare AI | `CLOUDFLARE_AI_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` | Both required |
| Cloudflare AI (alt) | `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` | If no dedicated AI token |
| Vertex AI | — | Uses `gcloud auth print-access-token` |
| BytePlus / Ark | `BYTEPLUS_API_KEY` or `ARK_API_KEY` | Key validated only |
| Qwen / DashScope | `DASHSCOPE_API_KEY` or `QWEN_API_KEY` | Key validated only |
| Copilot (fallback) | `COPILOT_GITHUB_TOKEN` / `GH_TOKEN` / `GITHUB_TOKEN` | Prefers `gh auth token` |
| Ollama (alt host) | `OLLAMA_HOST` | Default: `http://localhost:11434` |

Environment variables must be available to the DMS process. If DMS does not inherit your interactive shell environment, set them in your shell init file (`.profile`, `.bash_profile`, `.zshenv`) rather than `.bashrc` / `.zshrc`.

---

## Recommended configurations

### Minimal (Claude only)

```text
Provider Set:         claude
Source Mode:          cli
Refresh Interval:     120000
Show Provider Errors: true
```

### Personal AI stack

```text
Provider Set:         claude,copilot,deepseek,kimi
Source Mode:          cli
Refresh Interval:     120000
Show Provider Errors: true
```

### Local + API providers

```text
Provider Set:         claude,copilot,openrouter,deepseek,minimax,glm,mistral,ollama
Source Mode:          api
Refresh Interval:     300000
Show Provider Errors: true
```

### Minimal bar (stable, no errors)

```text
Provider Set:         claude
Source Mode:          cli
Refresh Interval:     300000
Show Provider Errors: false
```

---

## UI elements

| Element | Shows |
|---------|-------|
| DankBar pill | Percent usage of the provider closest to quota |
| Popout header | Last refresh time and active source mode |
| Overview section | Active provider count, attention count, engine info |
| Provider cards | Account, source, progress bars, reset time, remove/expand controls |
