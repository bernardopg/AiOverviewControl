# Provider verification

This document records the upstream surface used by each adapter. It was reviewed on 2026-06-18. Provider APIs change; re-check these links before changing an adapter. See `docs/providers.md` for the full per-provider reference (plans, billing, flagship models, changelog).

## Verified quota, balance, or billing surfaces

| Provider | Upstream source | Plugin use |
| --- | --- | --- |
| Codex | [Codex app-server](https://developers.openai.com/codex/app-server/) and generated protocol schema | `account/read` and `account/rateLimits/read`. |
| OpenRouter | [API key information](https://openrouter.ai/docs/api-reference/limits) | Limit, remaining balance, daily and monthly usage. |
| DeepSeek | [Get user balance](https://api-docs.deepseek.com/api/get-user-balance/) | Remaining account balance. |
| Kimi/Moonshot | [Balance API](https://platform.kimi.ai/docs/intro) — `GET https://api.moonshot.ai/v1/users/me/balance` | Account balance where available for the selected regional host (USD on `.ai`, CNY on `.cn`). |
| Together AI | [Credits API](https://docs.together.ai/reference/credits) | Remaining credits. |
| 9Router | Local provider-owned SQLite/JSON usage store | Requests, tokens, and tracked cost; no network request. |
| Claude Code | Provider-owned local JSONL and credentials | Local analytics. Subscription windows are best-effort because Claude Code does not document a stable public quota protocol. |
| GitHub Copilot | Authenticated `copilot_internal/user` response used by GitHub's Copilot clients | Premium, Chat, and Completions quota snapshots. This endpoint is not a documented public API and may change. |

## Verified analytics surfaces (consumption counters, not remaining quota)

| Provider | Upstream source | Plugin use |
| --- | --- | --- |
| Cloudflare | [GraphQL Analytics API](https://developers.cloudflare.com/analytics/graphql-api/) — `aiInferenceAdaptiveGroups` dataset | 7-day and latest-day requests/neurons when `CLOUDFLARE_ACCOUNT_ID` is set. Explicitly **not** a billing measure per Cloudflare's docs; graceful fallback to the token-verified note card. The dedicated Workers AI analytics tutorial was removed in 2025 — verify the node/fields via GraphQL introspection before relying on them. |

## Verified authentication or runtime surfaces

| Provider | Upstream source | Plugin use |
| --- | --- | --- |
| Gemini | [Gemini API models](https://ai.google.dev/api/models) — `GET https://generativelanguage.googleapis.com/v1beta/models` | API-key validation via `x-goog-api-key`; local Gemini CLI credentials (`~/.gemini/oauth_creds.json`) are detected. |
| Mistral | [Models API](https://docs.mistral.ai/api/#tag/models) — `GET https://api.mistral.ai/v1/models` | API-key validation. (`/v1/billing` and `/v1/usage` return `404`.) |
| Ollama | [`/api/tags`](https://docs.ollama.com/api/tags) and [`/api/ps`](https://docs.ollama.com/api/ps) | Installed and running models. |
| NVIDIA NIM | [Models API](https://docs.api.nvidia.com/nim/reference/models-1) — `GET https://integrate.api.nvidia.com/v1/models` | API-key validation. No documented balance API; credits at `build.nvidia.com/credits`. |
| Cloudflare | [Verify API token](https://developers.cloudflare.com/api/resources/user/subresources/tokens/methods/verify/) — `GET https://api.cloudflare.com/client/v4/user/tokens/verify` | Token validation. |
| Vertex AI | [gcloud authentication](https://cloud.google.com/sdk/gcloud/reference/auth/print-access-token) | Local OAuth validation and selected project label. |
| BytePlus ModelArk | [ModelArk API reference](https://docs.byteplus.com/en/docs/ModelArk/1099455) | Models API validation. |
| Qwen/DashScope | [OpenAI-compatible API](https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope) — `GET https://dashscope.aliyuncs.com/compatible-mode/v1/models` | Models API validation (best-effort; endpoint not officially documented in the OpenAI-compat surface). |
| Groq | [Models endpoint](https://console.groq.com/docs/api-reference#models) | API-key validation. |
| Cohere | [Cohere API reference](https://docs.cohere.com/reference/about) | Models API validation. |
| Replicate | [Account endpoint](https://replicate.com/docs/reference/http#account.get) | Token validation and account identity. |
| Fireworks AI | [OpenAI compatibility](https://docs.fireworks.ai/tools-sdks/openai-compatibility) | Inference models API validation. |
| Z.ai / GLM | [Z.ai API reference](https://docs.z.ai/api-reference/introduction.md) — `https://api.z.ai/api/monitor/usage/quota/limit` (global); China mirror `https://open.bigmodel.cn/api/monitor/usage/quota/limit` | `GET /api/monitor/usage/quota/limit` returns `data.limits[]` with `type`, `percentage`, `nextResetTime` (epoch ms), `remaining`, `unit`, `number`, and `data.level` (plan tier). Limits sorted by urgency (highest % timed first), mapped to primary/secondary/tertiary. Falls back to `GET /paas/v4/models` auth-only if quota endpoint unavailable. Key: `ZAI_API_KEY`; fallbacks: `GLM_API_KEY`, `ZHIPU_API_KEY`. |
| xAI (Grok) | [xAI API reference](https://docs.x.ai/) — `GET https://api.x.ai/v1/api-key` | Key validation returning `{name, api_key_blocked, api_key_disabled, team_blocked, acls, ...}`. No remaining-credits field; per-request cost in `usage.cost_in_usd_ticks`. Key: `XAI_API_KEY`. |
| MiniMax | [MiniMax API reference](https://platform.minimax.io/docs/api-reference) — `GET https://api.minimax.io/v1/models` | Models API validation (lists `MiniMax-M3`, `MiniMax-M2.7`, …). No documented balance API; dashboard at `platform.minimax.io/user-center/payment/balance`. Key: `MINIMAX_API_KEY`. |
| Kilo | [Kilo Gateway](https://kilo.ai/docs/gateway) — `GET https://api.kilo.ai/api/gateway/models` | Best-effort models probe. **The endpoint is documented as no-auth**, so a `200` is inconclusive; only a `401` reliably rejects a malformed key. No balance API; `402` on a paid call carries `metadata.buyCreditsUrl`. Key: `KILO_API_KEY`. |

## No documented read-only quota endpoint

AI21, Perplexity, Cursor, Cline, OpenCode, Kiro, Warp, and Amp do not currently provide a public, stable, read-only quota endpoint suitable for this widget. Kiro additionally has **no public API at all** (subscription-only IDE/CLI/Web with SSO login). The plugin therefore reports configured/authenticated status where possible or displays an informational card. It does not scrape dashboards or claim synthetic percentages.

## Review policy

1. Prefer an official CLI protocol or documented REST endpoint.
2. Do not call a paid inference endpoint merely to validate a key.
3. Do not scrape authenticated web dashboards.
4. Treat undocumented endpoints as unstable and label them explicitly.
5. Return an informational card when no truthful quota value can be obtained.
