# Providers

`providers/get-provider-usage` dispatches every selected provider independently and returns one normalized JSON object per provider.

## Coverage matrix

| ID | Coverage | Credential or local source | Result |
| --- | --- | --- | --- |
| `codex` | Quota | `codex` login | Session and weekly rate-limit windows from `codex app-server`. |
| `claude` | Quota + local analytics | Claude Code OAuth and `~/.claude/projects` | 5-hour/7-day windows plus tokens, sessions, models, and estimated cost. |
| `copilot` | Quota snapshot | `gh` or GitHub token | Premium requests, Chat, and Completions quota from the authenticated Copilot account. |
| `gemini` | Authentication | Gemini CLI OAuth or Gemini API key | Authenticated status; quota remains in AI Studio. |
| `9router` | Local analytics | `~/.9router/db/data.sqlite` or `usage.json` | Requests, tokens, and tracked cost. |
| `openrouter` | Quota/balance | `OPENROUTER_API_KEY` | Key limit, daily usage, monthly usage, and remaining balance. |
| `deepseek` | Balance | `DEEPSEEK_API_KEY` | Account balance and granted balance. |
| `kimi` | Balance | `MOONSHOT_API_KEY` or `KIMI_API_KEY` | Available, voucher, and cash balance. |
| `minimax` | Configured status | `MINIMAX_API_KEY` | Informational status; no documented read-only quota endpoint. |
| `glm` | Configured status | `GLM_API_KEY` or `ZHIPU_API_KEY` | Informational status; no documented read-only quota endpoint. |
| `mistral` | Authentication | `MISTRAL_API_KEY` | Models API validation. |
| `ollama` | Local runtime | `OLLAMA_HOST` | Installed models and currently running models. |
| `nvidia` | Authentication | `NVIDIA_API_KEY` | NIM models API validation. |
| `cloudflare` | Authentication | Cloudflare API token | Official token verification; Workers AI usage remains in analytics. |
| `vertexai` | Authentication | `gcloud` | Active account and optional project. |
| `byteplus` | Authentication | `BYTEPLUS_API_KEY` or `ARK_API_KEY` | ModelArk models API validation. |
| `qwen` | Authentication | `DASHSCOPE_API_KEY` or `QWEN_API_KEY` | DashScope compatible models API validation. |
| `together` | Balance | `TOGETHER_API_KEY` | Credit balance. |
| `groq` | Authentication | `GROQ_API_KEY` | Models API validation. |
| `cohere` | Authentication | `COHERE_API_KEY` | Models API validation. |
| `replicate` | Authentication | `REPLICATE_API_TOKEN` | Account API validation and username. |
| `fireworks` | Authentication | `FIREWORKS_API_KEY` | Inference models API validation. |
| `ai21` | Configured status | `AI21_API_KEY` | Informational status; no documented read-only usage endpoint. |
| `perplexity` | Informational | None | Points to official billing/settings. |
| `cursor` | Informational | None | Points to Cursor settings. |
| `cline` | Informational | None | Points to the Cline client. |
| `opencode` | Informational | None | Explains that usage belongs to upstream providers. |
| `kilo` | Informational | None | Points to Kilo account usage. |
| `kiro` | Informational | None | Points to Kiro account usage. |
| `warp` | Informational | None | Points to Warp account usage. |
| `amp` | Informational | None | Points to Amp account usage. |

## Direct tests

Every provider has a `providers/get-<id>-usage` entrypoint. Examples:

```bash
./providers/get-codex-usage | jq .
./providers/get-openrouter-usage | jq .
./providers/get-ollama-usage | jq .
./providers/get-provider-health "codex,openrouter,ollama" | jq .
```

## Output schema

```json
{
  "provider": "codex",
  "source": "codex-app-server",
  "usage": {
    "identity": {
      "providerID": "codex",
      "accountEmail": "account@example.com",
      "loginMethod": "plus"
    },
    "primary": {
      "usedPercent": 25,
      "windowMinutes": 300,
      "resetsAt": "2026-06-11T01:33:15Z",
      "resetDescription": "Session"
    },
    "secondary": null,
    "tertiary": null,
    "updatedAt": "2026-06-10T20:44:55Z"
  },
  "credits": { "remaining": "0" }
}
```

Errors use `{provider, source, error:{code, kind, message}}`. A provider without a quota API uses a normal informational `usage` object rather than an error.
