# Providers

AiOverviewControl queries each provider independently. A single provider failure produces an error card without affecting healthy providers.

The local backend is `get-provider-usage`. It prefers native adapters and falls back to `codexbar` only for providers without one.

---

## Provider Matrix

| ID | Display name | Auth env var(s) | Endpoint / method | Quota available | Notes |
|----|-------------|-----------------|-------------------|-----------------|-------|
| `codex` | Codex / ChatGPT | — | `codexbar usage` | via codexbar | Requires codexbar. |
| `claude` | Claude | — | `get-claude-usage` + `codexbar` | ✓ (5 h / 7 d windows) | Uses local JSONL + OAuth. |
| `copilot` | GitHub Copilot | `COPILOT_GITHUB_TOKEN` / `GH_TOKEN` / `GITHUB_TOKEN` | `GET api.github.com/copilot_internal/user` | ✓ (Premium / Chat / Completions) | Prefers `gh auth token`. |
| `gemini` | Gemini | `GEMINI_API_KEY` / `GOOGLE_API_KEY` / `GOOGLE_GENERATIVE_AI_API_KEY` | codexbar or `~/.gemini` credentials | via codexbar | Accepts local OAuth creds. |
| `9router` | 9Router | — | `~/.9router/db/data.sqlite` (local SQLite) | ✓ (today / week by provider) | Local DB only; no API key needed. |
| `openrouter` | OpenRouter | `OPENROUTER_API_KEY` | `GET openrouter.ai/api/v1/auth/key` | ✓ (credits remaining) | Falls back to 9Router local DB. |
| `deepseek` | DeepSeek | `DEEPSEEK_API_KEY` | `GET api.deepseek.com/user/balance` | ✓ (CNY balance: total / topped-up / granted) | |
| `kimi` / `moonshot` | Kimi | `MOONSHOT_API_KEY` / `KIMI_API_KEY` | `GET api.moonshot.cn/v1/users/me/balance` | ✓ (available / voucher / cash CNY) | |
| `minimax` | MiniMax | `MINIMAX_API_KEY` | `GET www.minimax.io/v1/token_plan/remains` | ✓ (token quota remaining) | |
| `glm` / `zhipu` | GLM | `GLM_API_KEY` / `ZHIPU_API_KEY` | `GET bigmodel.cn/api/monitor/usage/quota/limit` | ✓ (quota used / limit) | Set `GLM_API_BASE` to override base URL. |
| `mistral` | Mistral | `MISTRAL_API_KEY` | `GET api.mistral.ai/v1/models` (key validation) | ✗ (no quota endpoint) | Shows note-card directing to console.mistral.ai. |
| `ollama` | Ollama | — | `GET {OLLAMA_HOST}/api/tags` (default `http://localhost:11434`) | ✗ (no global quota) | Lists loaded models. Set `OLLAMA_HOST` to override. |
| `nvidia` / `nim` | NVIDIA NIM | `NVIDIA_API_KEY` | `GET integrate.api.nvidia.com/v1/models` (key validation) | ✗ (no quota endpoint) | Shows note-card directing to build.nvidia.com. |
| `cloudflare` | Cloudflare AI | `CLOUDFLARE_AI_TOKEN` / `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` | `GET api.cloudflare.com/client/v4/accounts/{id}/ai/usage` | ✓ (neurons used / limit) | Both vars required. |
| `vertexai` / `vertex` | Vertex AI | via `gcloud auth print-access-token` | gcloud CLI check | ✗ (no programmatic quota) | Shows note-card if authenticated; error if not. |
| `byteplus` / `ark` / `modelark` | BytePlus Ark | `BYTEPLUS_API_KEY` / `ARK_API_KEY` | `GET ark.ap-southeast.bytepluses.com/api/v3/models` (key validation) | ✗ (no balance endpoint) | Shows note-card directing to console.byteplus.com. |
| `qwen` / `dashscope` / `alibaba` | Qwen | `DASHSCOPE_API_KEY` / `QWEN_API_KEY` | `GET dashscope.aliyuncs.com/compatible-mode/v1/models` (key validation) | ✗ (no public balance endpoint) | Shows note-card directing to dashscope.console.aliyun.com. |
| `perplexity` | Perplexity | — | `codexbar usage` | via codexbar | Requires codexbar. |
| `cursor` | Cursor | — | `codexbar usage` | via codexbar | Requires codexbar. |
| `kilo` | Kilo Code | — | `codexbar usage` | via codexbar | Requires codexbar. |
| `kiro` | Kiro | — | `codexbar usage` | via codexbar | Requires codexbar. |
| `warp` | Warp | — | `codexbar usage` | via codexbar | Requires codexbar. |
| `amp` | Amp | — | `codexbar usage` | via codexbar | Requires codexbar. |
| `cline` | Cline | — | `codexbar usage` | via codexbar | Requires codexbar. |
| `opencode` | OpenCode | — | `codexbar usage` | via codexbar | Requires codexbar. |

---

## Provider details

### Claude

Two data sources merged:

1. `get-claude-usage` — local JSONL analytics + OAuth subscription windows
2. `codexbar usage --provider claude` — fallback for the main usage card

Local files read:

```text
~/.claude/.credentials.json         OAuth token
~/.claude/projects/**/*.jsonl       per-session usage logs
~/.claude/pricing-cache.json        LiteLLM model prices (auto-refreshed)
~/.claude/usage-cache.json          aggregated token counts (auto-refreshed)
```

Test:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
```

### Copilot

Auth priority:

```text
gh auth token
COPILOT_GITHUB_TOKEN
GH_TOKEN
GITHUB_TOKEN
```

API: `GET https://api.github.com/copilot_internal/user` with `X-Github-Api-Version: 2025-04-01`.

Windows surfaced: Premium, Chat, Completions.

Test:

```bash
gh auth status
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

### 9Router vs OpenRouter

These are two distinct providers sharing no code:

| | 9Router | OpenRouter |
|-|---------|-----------|
| ID | `9router` | `openrouter` |
| Data source | Local SQLite `~/.9router/db/data.sqlite` | REST API `openrouter.ai/api/v1/auth/key` |
| Auth | None | `OPENROUTER_API_KEY` |
| Fallback | — | Uses 9Router local DB when no key is set |

### DeepSeek

```bash
export DEEPSEEK_API_KEY=sk-...
curl -s https://api.deepseek.com/user/balance \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" | jq .
```

Balance fields: `balance_infos[0].{total_balance,topped_up_balance,granted_balance}` in CNY.

### Kimi (Moonshot)

```bash
export MOONSHOT_API_KEY=sk-...   # or KIMI_API_KEY
curl -s https://api.moonshot.cn/v1/users/me/balance \
  -H "Authorization: Bearer $MOONSHOT_API_KEY" | jq .
```

Balance fields: `data.{available_balance,voucher_balance,cash_balance}` in CNY.

### MiniMax

```bash
export MINIMAX_API_KEY=...
curl -s https://www.minimax.io/v1/token_plan/remains \
  -H "Authorization: Bearer $MINIMAX_API_KEY" | jq .
```

### GLM (Zhipu AI)

```bash
export GLM_API_KEY=...   # or ZHIPU_API_KEY
curl -s https://bigmodel.cn/api/monitor/usage/quota/limit \
  -H "Authorization: Bearer $GLM_API_KEY" | jq .
```

Set `GLM_API_BASE` to use an alternative base URL (e.g. `open.bigmodel.cn`).

### Mistral

No public balance/quota endpoint. Key is validated via `GET https://api.mistral.ai/v1/models`. The card shows a note directing to [console.mistral.ai](https://console.mistral.ai).

```bash
export MISTRAL_API_KEY=...
curl -s https://api.mistral.ai/v1/models \
  -H "Authorization: Bearer $MISTRAL_API_KEY" | jq '.data | length'
```

### Ollama

No global quota. Lists models loaded locally via `/api/tags`. Set `OLLAMA_HOST` for non-default host.

```bash
curl -s http://localhost:11434/api/tags | jq '.models[].name'
```

### NVIDIA NIM

No public balance endpoint. Key validated via `GET https://integrate.api.nvidia.com/v1/models`. Card shows note directing to [build.nvidia.com](https://build.nvidia.com).

```bash
export NVIDIA_API_KEY=nvapi-...
curl -s https://integrate.api.nvidia.com/v1/models \
  -H "Authorization: Bearer $NVIDIA_API_KEY" | jq '.data | length'
```

### Cloudflare AI

Requires both `CLOUDFLARE_ACCOUNT_ID` and a token with `AI Gateway:Read` permission.

```bash
export CLOUDFLARE_ACCOUNT_ID=...
export CLOUDFLARE_AI_TOKEN=...
curl -s "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/ai/usage" \
  -H "Authorization: Bearer $CLOUDFLARE_AI_TOKEN" | jq '.result'
```

Fields: `neurons_used`, `neurons_limit`.

### Vertex AI

Requires `gcloud` CLI and an active authenticated session. No programmatic quota endpoint — shows authenticated note-card or auth-error card.

```bash
gcloud auth print-access-token
gcloud config get-value project
```

### BytePlus ModelArk

No public balance endpoint. Key validated via models list. Card shows note directing to [console.byteplus.com](https://console.byteplus.com).

```bash
export BYTEPLUS_API_KEY=...   # or ARK_API_KEY
curl -s https://ark.ap-southeast.bytepluses.com/api/v3/models \
  -H "Authorization: Bearer $BYTEPLUS_API_KEY" | jq '.data | length'
```

### Qwen (DashScope / Alibaba)

No public balance endpoint via DashScope compatible-mode API. Key validated via models list. Card shows note directing to [dashscope.console.aliyun.com](https://dashscope.console.aliyun.com).

```bash
export DASHSCOPE_API_KEY=sk-...   # or QWEN_API_KEY
curl -s https://dashscope.aliyuncs.com/compatible-mode/v1/models \
  -H "Authorization: Bearer $DASHSCOPE_API_KEY" | jq '.data | length'
```

---

## Testing the full backend

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage \
  "$(command -v codexbar)" \
  "claude,copilot,deepseek,kimi,minimax,glm,mistral,ollama" \
  "cli" \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

---

## Choosing a provider list

Start small:

```text
claude,copilot
```

Add one provider at a time. If a card shows an error:

1. Expand the card and read the message.
2. Run the test command for that provider (see sections above).
3. Set the required env var or configure auth.
4. Remove the provider from the list if it is unsupported in your environment.
