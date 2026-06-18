# Provider verification

This document records the upstream surface used by each adapter. It was reviewed on 2026-06-10. Provider APIs change; re-check these links before changing an adapter.

## Verified quota, balance, or billing surfaces

| Provider | Upstream source | Plugin use |
| --- | --- | --- |
| Codex | [Codex app-server](https://developers.openai.com/codex/app-server/) and generated protocol schema | `account/read` and `account/rateLimits/read`. |
| OpenRouter | [API key information](https://openrouter.ai/docs/api-reference/limits) | Limit, remaining balance, daily and monthly usage. |
| DeepSeek | [Get user balance](https://api-docs.deepseek.com/api/get-user-balance/) | Remaining account balance. |
| Moonshot/Kimi | [Moonshot platform API](https://platform.moonshot.ai/docs/api-reference) | Account balance where available for the selected regional host. |
| Together AI | [Credits API](https://docs.together.ai/reference/credits) | Remaining credits. |
| 9Router | Local provider-owned SQLite/JSON usage store | Requests, tokens, and tracked cost; no network request. |
| Claude Code | Provider-owned local JSONL and credentials | Local analytics. Subscription windows are best-effort because Claude Code does not document a stable public quota protocol. |
| GitHub Copilot | Authenticated `copilot_internal/user` response used by GitHub's Copilot clients | Premium, Chat, and Completions quota snapshots. This endpoint is not a documented public API and may change. |

## Verified authentication or runtime surfaces

| Provider | Upstream source | Plugin use |
| --- | --- | --- |
| Gemini | [Gemini API models](https://ai.google.dev/api/models) | API-key validation; local Gemini CLI credentials are detected. |
| Mistral | [Models API](https://docs.mistral.ai/api/#tag/models) | API-key validation. |
| Ollama | [`/api/tags`](https://docs.ollama.com/api/tags) and [`/api/ps`](https://docs.ollama.com/api/ps) | Installed and running models. |
| NVIDIA NIM | [Models API](https://docs.api.nvidia.com/nim/reference/models-1) | API-key validation. |
| Cloudflare | [Verify API token](https://developers.cloudflare.com/api/resources/user/subresources/tokens/methods/verify/) | Token validation. Workers AI usage stays in official analytics because no stable REST quota endpoint is documented. |
| Vertex AI | [gcloud authentication](https://cloud.google.com/sdk/gcloud/reference/auth/print-access-token) | Local OAuth validation and selected project label. |
| BytePlus ModelArk | [ModelArk API reference](https://docs.byteplus.com/en/docs/ModelArk/1099455) | Models API validation. |
| Qwen/DashScope | [OpenAI-compatible API](https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope) | Models API validation. |
| Groq | [Models endpoint](https://console.groq.com/docs/api-reference#models) | API-key validation. |
| Cohere | [Cohere API reference](https://docs.cohere.com/reference/about) | Models API validation. |
| Replicate | [Account endpoint](https://replicate.com/docs/reference/http#account.get) | Token validation and account identity. |
| Fireworks AI | [OpenAI compatibility](https://docs.fireworks.ai/tools-sdks/openai-compatibility) | Inference models API validation. |
| Z.ai | [Z.ai API reference](https://docs.z.ai/api-reference/introduction.md) — OpenAI-compatible base `https://api.z.ai/api/paas/v4` | `GET /models` for key validation. No documented balance or quota API; subscription (GLM Coding Plan) and PAYG both directed to `z.ai/manage-apikey/billing`. Key: `ZAI_API_KEY`; fallbacks: `GLM_API_KEY`, `ZHIPU_API_KEY`. |

## No documented read-only quota endpoint

MiniMax, GLM, AI21, Perplexity, Cursor, Cline, OpenCode, Kilo, Kiro, Warp, and Amp do not currently provide a public, stable, read-only quota endpoint suitable for this widget. The plugin therefore reports configured/authenticated status where possible or displays an informational card. It does not scrape dashboards or claim synthetic percentages.

## Review policy

1. Prefer an official CLI protocol or documented REST endpoint.
2. Do not call a paid inference endpoint merely to validate a key.
3. Do not scrape authenticated web dashboards.
4. Treat undocumented endpoints as unstable and label them explicitly.
5. Return an informational card when no truthful quota value can be obtained.
