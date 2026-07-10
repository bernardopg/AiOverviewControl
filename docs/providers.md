# Providers

`providers/get-provider-usage` dispatches every selected provider independently and returns one normalized JSON object per provider. Each provider also has a `providers/get-<id>-usage` entrypoint and is covered by `providers/get-provider-health`.

This document is the authoritative reference for adapter authors. It records, for every provider:

- the **coverage level** the plugin can truthfully report,
- the **credential / local source** it reads,
- the **read-only key-validation endpoint** (zero token consumption),
- the **quota / balance API** if one exists,
- the **subscription plans** and **billing model**,
- the **dashboard URL** where usage lives,
- the **current flagship model(s)** and recent **changelog** highlights,
- and the **official documentation source** used.

Reviewed 2026-06-18. Provider APIs change; re-check the linked sources before changing an adapter.

## Coverage levels

Every provider maps to exactly one coverage level. The level dictates what the widget can truthfully render.

| Level | Meaning | Example providers |
| --- | --- | --- |
| **Quota** | Real `usedPercent` + reset window from a protocol/API. | `codex`, `copilot`, `antigravity`, `openrouter`, `zai`, `glm`, `fireworks` (with account ID) |
| **Balance** | Remaining prepaid balance / credits in real currency. | `kimi`, `deepseek` |
| **Analytics** | Consumption counters (requests/tokens/neurons/cost) with no remaining-quota value. | `cloudflare` (GraphQL), `9router`, `claude` (local) |
| **Auth** | Read-only key validation only — no usage numbers. | `gemini`, `mistral`, `nvidia`, `qwen`, `byteplus`, `groq`, `cohere`, `replicate`, `together`, `minimax`, `xai`, `kilo`, `ai21` |
| **Local runtime** | Local process / installed models. | `ollama`, `vertexai` (gcloud) |
| **Informational** | No public read-only API at all; the card just links to the dashboard. | `perplexity`, `cursor`, `cline`, `opencode`, `kiro`, `warp`, `amp` |

## Coverage matrix

The matrix below summarises the **authentication/billing surface** for every supported provider. Legend: ✅ yes &middot; ❌ no public API &middot; ⚠️ partial / dashboard-only.

<table>
<thead>
<tr>
<th>Provider</th>
<th>Coverage</th>
<th>Read-only key check</th>
<th>Quota / balance API</th>
<th>Sub. plan</th>
<th>PAYG</th>
<th>Env var</th>
<th>Dashboard</th>
<th>Docs source</th>
</tr>
</thead>
<tbody>
<!-- Reference providers -->
<tr>
<td><code>codex</code></td>
<td>Quota</td>
<td>codex <code>app-server</code></td>
<td>✅ session + weekly windows</td>
<td>✅ Plus / Pro / Team</td>
<td>✅</td>
<td><code>codex</code> login</td>
<td><a href="https://developers.openai.com/codex/app-server/">developers.openai.com</a></td>
<td><a href="https://developers.openai.com/codex/app-server/">Codex app-server</a></td>
</tr>
<tr>
<td><code>claude</code></td>
<td>Quota + local analytics</td>
<td>local <code>~/.claude</code></td>
<td>✅ 5h / 7d / weekly per-model (<code>limits[]</code>)</td>
<td>✅ Pro / Max</td>
<td>✅</td>
<td><code>claude</code> OAuth</td>
<td><code>~/.claude</code></td>
<td>local analytics</td>
</tr>
<tr>
<td><code>copilot</code></td>
<td>Quota snapshot</td>
<td><code>copilot_internal/user</code></td>
<td>✅ premium (AI credits since 2026-06) + overage; chat/completions shown only when not unlimited</td>
<td>✅ Free / Pro / Pro+ / Education / Business / Enterprise</td>
<td>—</td>
<td><code>GH_TOKEN</code></td>
<td><a href="https://github.com/settings/copilot">github.com/settings/copilot</a></td>
<td><a href="https://docs.github.com/copilot">GitHub Copilot</a></td>
</tr>
<!-- Focus providers -->
<tr>
<td><code>antigravity</code></td>
<td>Quota (Cloud Code Assist)</td>
<td>✅ local Antigravity OAuth (keyring / IDE session, auto-refreshed)</td>
<td>✅ Gemini / Claude &amp; OpenAI family quota + reset; optional per-model detail</td>
<td>✅ Antigravity plan</td>
<td>—</td>
<td><code>~/.config/Antigravity IDE</code></td>
<td>Antigravity IDE</td>
<td><code>loadCodeAssist</code> + <code>v1internal:fetchAvailableModels</code> on <code>cloudcode-pa.googleapis.com</code> (multi-account)</td>
</tr>
<tr>
<td><code>gemini</code></td>
<td>Auth</td>
<td>✅ <code>GET /v1beta/models</code></td>
<td>❌ dashboard-only</td>
<td>⚠️ tiered PAYG (no flat sub)</td>
<td>✅ prepaid credits → tiers</td>
<td><code>GEMINI_API_KEY</code></td>
<td><a href="https://aistudio.google.com">aistudio.google.com</a></td>
<td><a href="https://ai.google.dev/api/models">ai.google.dev</a></td>
</tr>
<tr>
<td><code>cloudflare</code></td>
<td>Analytics</td>
<td>✅ <code>GET /user/tokens/verify</code></td>
<td>⚠️ GraphQL analytics (not bill)</td>
<td>✅ Workers Paid $5/mo</td>
<td>✅ $0.011 / 1k neurons</td>
<td><code>CLOUDFLARE_API_TOKEN</code></td>
<td><a href="https://dash.cloudflare.com">dash.cloudflare.com</a></td>
<td><a href="https://developers.cloudflare.com/workers-ai/">developers.cloudflare.com</a></td>
</tr>
<tr>
<td><code>mistral</code></td>
<td>Auth</td>
<td>⚠️ <code>GET /v1/models</code> is public and cannot validate a key</td>
<td>❌ dashboard-only</td>
<td>✅ Vibe Pro $14.99 / Team $24.99</td>
<td>✅ per token</td>
<td><code>MISTRAL_API_KEY</code></td>
<td><a href="https://console.mistral.ai">console.mistral.ai</a></td>
<td><a href="https://docs.mistral.ai/">docs.mistral.ai</a></td>
</tr>
<tr>
<td><code>glm</code> / <code>zai</code></td>
<td>Quota</td>
<td>✅ <code>GET /api/monitor/usage/quota/limit</code></td>
<td>✅ per-window % + reset timestamp</td>
<td>✅ GLM Coding Plan $18–$160/mo</td>
<td>✅ per token</td>
<td><code>ZAI_API_KEY</code> / <code>GLM_API_KEY</code></td>
<td><a href="https://z.ai/manage-apikey/billing">z.ai/manage-apikey</a></td>
<td><a href="https://docs.z.ai/">docs.z.ai</a> / <a href="https://open.bigmodel.cn/dev/api">open.bigmodel.cn</a></td>
</tr>
<tr>
<td><code>nvidia</code></td>
<td>Auth</td>
<td>✅ <code>GET /v1/models</code></td>
<td>❌ dashboard-only</td>
<td>⚠️ rate-limited developer trial</td>
<td>✅ NVIDIA Cloud Credits</td>
<td><code>NVIDIA_API_KEY</code></td>
<td><a href="https://build.nvidia.com/credits">build.nvidia.com/credits</a></td>
<td><a href="https://docs.api.nvidia.com/nim/reference/models-1">docs.api.nvidia.com</a></td>
</tr>
<tr>
<td><code>minimax</code></td>
<td>Auth</td>
<td>✅ <code>GET /v1/models</code></td>
<td>❌ dashboard-only</td>
<td>✅ Token Plan $20/$50/$120/mo</td>
<td>✅ per token (M3 50% off)</td>
<td><code>MINIMAX_API_KEY</code></td>
<td><a href="https://platform.minimax.io">platform.minimax.io</a></td>
<td><a href="https://platform.minimax.io/docs/api-reference">platform.minimax.io/docs</a></td>
</tr>
<tr>
<td><code>kimi</code></td>
<td>Balance</td>
<td>✅ <code>GET /v1/models</code></td>
<td>✅ <code>GET /v1/users/me/balance</code></td>
<td>⚠️ top-up vouchers only</td>
<td>✅ per token (USD/CNY)</td>
<td><code>MOONSHOT_API_KEY</code> or <code>KIMI_API_KEY</code></td>
<td><a href="https://platform.kimi.ai/console">platform.kimi.ai</a></td>
<td><a href="https://platform.kimi.ai/docs/intro">platform.kimi.ai/docs</a></td>
</tr>
<tr>
<td><code>qwen</code></td>
<td>Auth</td>
<td>⚠️ <code>GET /compatible-mode/v1/models</code></td>
<td>❌ Alibaba billing console</td>
<td>✅ Coding Plan Pro $50/mo</td>
<td>✅ per token</td>
<td><code>DASHSCOPE_API_KEY</code></td>
<td><a href="https://modelstudio.console.alibabacloud.com/">modelstudio.console.alibabacloud.com</a></td>
<td><a href="https://www.alibabacloud.com/help/en/model-studio/">alibabacloud.com/help</a></td>
</tr>
<tr>
<td><code>xai</code></td>
<td>Auth</td>
<td>✅ <code>GET /v1/api-key</code></td>
<td>❌ dashboard-only (<code>usage.cost_in_usd_ticks</code> per request)</td>
<td>⚠️ prepaid credits only</td>
<td>✅ per token</td>
<td><code>XAI_API_KEY</code></td>
<td><a href="https://console.x.ai/billing">console.x.ai/billing</a></td>
<td><a href="https://docs.x.ai/">docs.x.ai</a></td>
</tr>
<tr>
<td><code>kilo</code></td>
<td>Auth</td>
<td>⚠️ <code>GET /api/gateway/models</code> (no-auth)</td>
<td>❌ dashboard-only (<code>402</code> signal)</td>
<td>✅ Kilo Pass $19/$49/$199/mo</td>
<td>✅ at-provider-cost credits</td>
<td><code>KILO_API_KEY</code></td>
<td><a href="https://app.kilo.ai/credits">app.kilo.ai</a></td>
<td><a href="https://kilo.ai/docs/gateway">kilo.ai/docs</a></td>
</tr>
<tr>
<td><code>kiro</code></td>
<td>Informational</td>
<td>❌ no public API</td>
<td>❌ no public API</td>
<td>✅ Free / Pro / Pro+ / Pro Max / Power</td>
<td>⚠️ overage $0.04/credit</td>
<td>—</td>
<td><a href="https://app.kiro.dev/settings/account">app.kiro.dev</a></td>
<td><a href="https://kiro.dev/docs/billing/">kiro.dev/docs</a></td>
</tr>
<!-- Remaining providers -->
<tr>
<td><code>9router</code></td>
<td>Local analytics</td>
<td>local SQLite/JSON</td>
<td>✅ local requests/tokens/cost</td>
<td>—</td>
<td>—</td>
<td><code>~/.9router</code></td>
<td>—</td>
<td>local store</td>
</tr>
<tr>
<td><code>openrouter</code></td>
<td>Quota/balance</td>
<td>✅ <code>GET /api/v1/key</code></td>
<td>✅ limit/daily/monthly/balance</td>
<td>—</td>
<td>✅ per token</td>
<td><code>OPENROUTER_API_KEY</code></td>
<td><a href="https://openrouter.ai/credits">openrouter.ai/credits</a></td>
<td><a href="https://openrouter.ai/docs/api-reference/limits">openrouter.ai/docs</a></td>
</tr>
<tr>
<td><code>deepseek</code></td>
<td>Balance</td>
<td>balance endpoint</td>
<td>✅ account + granted balance</td>
<td>—</td>
<td>✅ per token</td>
<td><code>DEEPSEEK_API_KEY</code></td>
<td><a href="https://platform.deepseek.com/usage">platform.deepseek.com</a></td>
<td><a href="https://api-docs.deepseek.com/api/get-user-balance/">api-docs.deepseek.com</a></td>
</tr>
<tr>
<td><code>ollama</code></td>
<td>Local runtime</td>
<td><code>GET /api/tags</code></td>
<td>✅ installed + running models</td>
<td>—</td>
<td>—</td>
<td><code>OLLAMA_HOST</code></td>
<td><a href="http://localhost:11434">localhost:11434</a></td>
<td><a href="https://docs.ollama.com/api/tags">docs.ollama.com</a></td>
</tr>
<tr>
<td><code>vertexai</code></td>
<td>Local runtime</td>
<td><code>gcloud auth</code></td>
<td>⚠️ <code>GetUsage</code> exists with separate IAM Signature V4 credentials</td>
<td>—</td>
<td>✅</td>
<td><code>gcloud</code></td>
<td><a href="https://console.cloud.google.com/vertex-ai">console.cloud.google.com</a></td>
<td><a href="https://cloud.google.com/vertex-ai">cloud.google.com/vertex-ai</a></td>
</tr>
<tr>
<td><code>byteplus</code></td>
<td>Auth</td>
<td>✅ <code>GET /api/v3/models</code></td>
<td>❌ dashboard-only</td>
<td>—</td>
<td>✅</td>
<td><code>BYTEPLUS_API_KEY</code></td>
<td><a href="https://console.byteplus.com/">console.byteplus.com</a></td>
<td><a href="https://docs.byteplus.com/en/docs/ModelArk/1099455">docs.byteplus.com</a></td>
</tr>
<tr>
<td><code>together</code></td>
<td>Auth</td>
<td>✅ <code>GET /v1/models</code></td>
<td>❌ no documented read-only credits endpoint</td>
<td>—</td>
<td>✅</td>
<td><code>TOGETHER_API_KEY</code></td>
<td><a href="https://api.together.ai/settings/api-keys">api.together.ai</a></td>
<td><a href="https://docs.together.ai/reference/models">docs.together.ai</a></td>
</tr>
<tr>
<td><code>groq</code></td>
<td>Auth</td>
<td>✅ <code>GET /v1/models</code></td>
<td>❌ dashboard-only</td>
<td>—</td>
<td>✅</td>
<td><code>GROQ_API_KEY</code></td>
<td><a href="https://console.groq.com/usage">console.groq.com</a></td>
<td><a href="https://console.groq.com/docs/api-reference">console.groq.com/docs</a></td>
</tr>
<tr>
<td><code>cohere</code></td>
<td>Auth</td>
<td>✅ models API</td>
<td>❌ dashboard-only</td>
<td>—</td>
<td>✅</td>
<td><code>COHERE_API_KEY</code></td>
<td><a href="https://dashboard.cohere.com">dashboard.cohere.com</a></td>
<td><a href="https://docs.cohere.com/reference/about">docs.cohere.com</a></td>
</tr>
<tr>
<td><code>replicate</code></td>
<td>Auth</td>
<td>✅ account endpoint</td>
<td>❌ dashboard-only</td>
<td>—</td>
<td>✅ per second</td>
<td><code>REPLICATE_API_TOKEN</code></td>
<td><a href="https://replicate.com/account">replicate.com/account</a></td>
<td><a href="https://replicate.com/docs/reference/http">replicate.com/docs</a></td>
</tr>
<tr>
<td><code>fireworks</code></td>
<td>Quota (with account ID)</td>
<td>✅ inference models API</td>
<td>✅ <code>GET /v1/accounts/{account_id}/quotas</code></td>
<td>—</td>
<td>✅</td>
<td><code>FIREWORKS_API_KEY</code>; optional <code>FIREWORKS_ACCOUNT_ID</code></td>
<td><a href="https://app.fireworks.ai">app.fireworks.ai</a></td>
<td><a href="https://docs.fireworks.ai/tools-sdks/openai-compatibility">docs.fireworks.ai</a></td>
</tr>
<tr>
<td><code>ai21</code></td>
<td>Auth</td>
<td>✅ <code>GET /studio/v1/models</code></td>
<td>❌ dashboard-only</td>
<td>—</td>
<td>✅</td>
<td><code>AI21_API_KEY</code></td>
<td><a href="https://studio.ai21.com">studio.ai21.com</a></td>
<td><a href="https://docs.ai21.com">docs.ai21.com</a></td>
</tr>
<tr>
<td><code>perplexity</code></td>
<td>Informational</td>
<td>❌</td>
<td>❌</td>
<td>✅ Pro</td>
<td>✅</td>
<td>—</td>
<td><a href="https://perplexity.ai/settings/billing">perplexity.ai/settings</a></td>
<td><a href="https://docs.perplexity.ai">docs.perplexity.ai</a></td>
</tr>
<tr>
<td><code>cursor</code></td>
<td>Informational</td>
<td>❌</td>
<td>❌</td>
<td>✅ Hobby / Pro / Business</td>
<td>—</td>
<td>—</td>
<td><a href="https://cursor.com/settings">cursor.com/settings</a></td>
<td><a href="https://cursor.com">cursor.com</a></td>
</tr>
<tr>
<td><code>cline</code></td>
<td>Informational</td>
<td>❌</td>
<td>❌</td>
<td>—</td>
<td>✅</td>
<td>—</td>
<td><a href="https://app.cline.bot">app.cline.bot</a></td>
<td><a href="https://cline.bot">cline.bot</a></td>
</tr>
<tr>
<td><code>opencode</code></td>
<td>Informational</td>
<td>❌</td>
<td>❌</td>
<td>—</td>
<td>—</td>
<td>—</td>
<td>upstream providers</td>
<td><a href="https://opencode.ai">opencode.ai</a></td>
</tr>
<tr>
<td><code>warp</code></td>
<td>Informational</td>
<td>❌</td>
<td>❌</td>
<td>✅ Warp Pro</td>
<td>—</td>
<td>—</td>
<td><a href="https://app.warp.dev">app.warp.dev</a></td>
<td><a href="https://warp.dev">warp.dev</a></td>
</tr>
<tr>
<td><code>amp</code></td>
<td>Informational</td>
<td>❌</td>
<td>❌</td>
<td>✅ Amp Pro</td>
<td>—</td>
<td>—</td>
<td><a href="https://ampcode.com">ampcode.com</a></td>
<td><a href="https://ampcode.com">ampcode.com</a></td>
</tr>
</tbody>
</table>

## Provider reference

Detailed adapter notes for the focus providers (Gemini, Cloudflare, Mistral, GLM/Z.ai, NVIDIA, MiniMax, Kimi, Qwen, xAI, Kilo, Kiro). All HTTP probes below are read-only and consume **no tokens**.

### Gemini (Google)

| | |
| --- | --- |
| **API base** | `https://generativelanguage.googleapis.com/v1beta` (OpenAI-compat: `/v1beta/openai/`). No China mirror; enterprise path is Vertex AI. |
| **Env var** | `GEMINI_API_KEY` (fallbacks `GOOGLE_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY`); also detected via local Gemini CLI (`~/.gemini/oauth_creds.json`). |
| **Auth** | Header `x-goog-api-key: <key>` (preferred) or query `?key=<key>`. |
| **Key check** | `GET /v1beta/models` → `200` lists models; `403` missing key; `400` malformed. Zero tokens. |
| **Quota / balance** | ❌ None. Usage, spend, and rate limits are dashboard-only. |
| **Plans** | Free + tiered PAYG (Tier 1 $250 cap → Tier 3 $20k+ cap, auto-upgrade by spend/age). No flat monthly API subscription. Enterprise = Gemini Enterprise Agent Platform. |
| **Billing** | Prepaid credits → pay-as-you-go per token. Batch API 50% off; cached/prompt discounts. |
| **Flagship pricing (/M tok)** | `gemini-3.5-flash` $1.50/$9.00 &middot; `gemini-3.1-pro-preview` $2.00/$12.00 (≤200k) &middot; `gemini-3.1-flash-lite` $0.25/$1.50 &middot; `gemini-2.5-pro` $1.25/$10.00. |
| **Dashboard** | [aistudio.google.com](https://aistudio.google.com) (rate limits), [console.cloud.google.com/billing](https://console.cloud.google.com/billing). |
| **Changelog** | **Gemini 3.5** Flash GA; **Gemini 3.1 Pro** preview (vibe-coding/customtools). Gemini 2.0 Flash/Flash-Lite **shut down 2026-06-01**. Imagen 4 deprecated (→ Gemini 2.5 Flash Image). Veo 3/2 → Veo 3.1. Gemini Embedding 2 (multimodal). |
| **Adapter** | `fetch_gemini_native` — API-key probe; falls back to local Gemini CLI OAuth detection. |

### Cloudflare (Workers AI)

| | |
| --- | --- |
| **API base** | `https://api.cloudflare.com/client/v4` (account-scoped AI: `/accounts/{account_id}/ai/...`; OpenAI-compat: `/accounts/{account_id}/ai/v1`). |
| **Env var** | `CLOUDFLARE_AI_TOKEN` (preferred) or `CLOUDFLARE_API_TOKEN`; `CLOUDFLARE_ACCOUNT_ID` unlocks GraphQL analytics. |
| **Auth** | `Authorization: Bearer <token>`. Token needs *Workers AI - Read/Edit*. |
| **Key check** | `GET /user/tokens/verify` → `200` `{"success":true,"result":{"status":"active"}}`. Zero neurons. |
| **Quota / balance** | ⚠️ **GraphQL analytics only** (not the bill). `POST /graphql` with `aiInferenceAdaptiveGroups` dataset scoped by `accountTag`. Returns `sum { requests neurons }` and `dimensions { date modelName taskType }`. The dedicated tutorial page was removed in 2025 — verify node/fields via introspection before relying on it. No REST "remaining neurons" endpoint. |
| **Plans** | Workers Free: 10,000 neurons/day. Workers Paid ($5/mo): same free allotment then $0.011/1k neurons. Enterprise: custom. |
| **Billing** | Per **neuron** ($0.011/1k). Per-model rates also expressed as $/M tokens (e.g. `@cf/zai-org/glm-5.2` $1.40/$4.40). |
| **Dashboard** | [dash.cloudflare.com](https://dash.cloudflare.com) → account → Workers AI. |
| **Changelog** | 2026-06-16 GLM-5.2; 2026-06-12 Kimi K2.7 Code; 2026-04-20 Kimi K2.6 (`reasoning` field, `chat_template_kwargs.thinking`); 2026-03-19 prompt caching (`x-session-affinity`); 2026-02-13 GLM-4.7-Flash; 2025-08-05 gpt-oss-120b/20b; 2024-05-17 OpenAI-compat added; unit-based neuron pricing since 2024-09. Major deprecation wave 2026-05-30 (Llama-2/3/3.1 base+AWQ, Mistral 7B, Gemma 7B/3-12B, phi-2). |
| **Adapter** | `fetch_cloudflare_native` — token verify; if `CLOUDFLARE_ACCOUNT_ID` is set, queries `aiInferenceAdaptiveGroups` for 7-day totals + latest day (graceful fallback to the token-verified note card). |

### Mistral AI

| | |
| --- | --- |
| **API base** | `https://api.mistral.ai/v1`. No regional mirror. |
| **Env var** | `MISTRAL_API_KEY`. |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | `GET /v1/models` → `200`; `401` on bad key. Zero tokens. (`/v1/billing` and `/v1/usage` return `404`.) |
| **Quota / balance** | ❌ None. Dashboard-only ("Mistral Studio dashboard offers detailed tracking of API usage"). |
| **Plans** | **Vibe** consumer/coding subs: Free / **Pro $14.99** / **Team $24.99** / Enterprise / Education $5.99. **API** = PAYG per token. Batch 50% off; cached input 10% of input price. |
| **Billing** | Per token (per 1M): `mistral-medium-3.5` $1.5/$7.5 (coding flagship) &middot; `mistral-large-3` $0.5/$1.5 &middot; `mistral-small-4` $0.1/$0.3 &middot; **`devstral-2`** $0.4/$2.0 (agentic coding) &middot; `codestral` $0.3/$0.9 (FIM) &middot; `magistral-medium` $2.0/$5.0. |
| **Dashboard** | [console.mistral.ai](https://console.mistral.ai) (keys, usage, billing). Pricing: [mistral.ai/pricing](https://mistral.ai/pricing). |
| **Changelog** | 2026-04 Mistral Medium 3.5; 2026-03 Mistral Small 4 (Apache 2.0); product restructure into **Vibe / Studio / Admin** (La Plateforme rebranded to Studio). New Workflows, Connectors, Observability. Fine-tuning + old Agents endpoints deprecated. |
| **Adapter** | `fetch_mistral_native` — `/v1/models` validation only. |

### GLM / Z.ai (Zhipu AI)

| | |
| --- | --- |
| **API base** | Global `https://api.z.ai/api/paas/v4`; Coding-Plan `https://api.z.ai/api/coding/paas/v4`; China `https://open.bigmodel.cn/api/paas/v4`. Fully OpenAI-compatible. |
| **Env var** | `ZAI_API_KEY` (fallbacks `GLM_API_KEY`, `ZHIPU_API_KEY`). |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | `GET /api/monitor/usage/quota/limit` → `200` with `success: true` and `data.limits[]`; `401`/`403` on bad key. Zero tokens. Falls back to `GET /paas/v4/models` when quota endpoint is unavailable. |
| **Quota / balance** | ✅ `/api/monitor/usage/quota/limit` returns `data.limits[]` — each limit has `type` (`TIME_LIMIT` or `TOKENS_LIMIT`), `percentage` (0–100), `nextResetTime` (epoch ms), `remaining`, `unit`, and `number`. Live cross-check against the Z.ai Usage page confirms the period unit table used by the adapter: `unit=4` → 5-hour session window, `unit=6` → weekly quota, `unit=5` → monthly web/search/reader quota, `unit=3` → total token allotment (no reset window). Also returns `data.level` (plan tier, e.g. `lite`). |
| **Plans** | PAYG per token **or** **GLM Coding Plan** (Lite $18, **Pro $72**, Max $160/mo; quarterly/annual discounts). Subscription usage exposes a 5-hour session quota, weekly token quota, and monthly Web Search / Reader / Zread quota; supported in Claude Code, Cline, OpenCode, Roo, Kilo, Crush, Goose, OpenClaw. **GLM-5.2 & GLM-5-Turbo consume 3× quota at peak (14:00–18:00 UTC+8), 2× off-peak** (1× off-peak promo through end of September). |
| **Billing** | Per 1M tokens: **`glm-5.2`** $1.40/$4.40 (cached $0.26) &middot; `glm-5`/`glm-5-turbo` $1.0–$1.2/$3.2–$4.0 &middot; `glm-4.7`/`4.6`/`4.5` $0.60/$2.20 &middot; `glm-4.7-flash` & `glm-4.5-flash` **Free** &middot; `glm-5v-turbo` (vision) $1.2/$4.0. Web Search $0.01/use. |
| **Dashboard** | [z.ai/manage-apikey](https://z.ai/manage-apikey) (keys), [/subscription](https://z.ai/manage-apikey/subscription) (Coding Plan), [/billing](https://z.ai/manage-apikey/billing) (finance). China: [open.bigmodel.cn](https://open.bigmodel.cn). |
| **Changelog** | **GLM-5.2** live (1M lossless context, 128K max output, MCP, structured output). Lineage: 4.5 → 4.6 → 4.7 → 5 → 5-Turbo → 5.1 → **5.2**. New GLM-5V-Turbo (vision coding), GLM-Image, CogVideoX-3, GLM-ASR-2512, GLM-OCR. Coding Plan restructured (legacy plans migrated by 2026-04-30). |
| **Adapter** | `fetch_glm_native` (China console, `open.bigmodel.cn`) and `fetch_zai_native` (global, `api.z.ai`). Both call `GET /api/monitor/usage/quota/limit` for real quota data; fall back to `GET /models` auth-only check if the quota endpoint is unavailable. Sorts limits by urgency (highest % first among timed windows), then maps to primary / secondary / tertiary. |

### NVIDIA (NIM / build.nvidia.com)

| | |
| --- | --- |
| **API base** | `https://integrate.api.nvidia.com/v1` (OpenAI-compatible). No regional mirror; backed by DGX Cloud. |
| **Env var** | `NVIDIA_API_KEY` (NGC personal key, `nvapi-` prefix). |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | `GET /v1/models` is a public catalog and cannot validate a key; the card truthfully reports only that a key is set. |
| **Quota / balance** | ❌ None documented. NVCF/Cloud Functions billing doc is auth-gated (`401`). Balance is dashboard-only. Practical exhaustion signal: inference returns `402`/`429`. |
| **Plans** | Rate-limited Developer trial, NVIDIA Cloud Credits (USD blocks), and NVIDIA AI Enterprise for self-hosted NIM. |
| **Billing** | **Credit-based per request** (1 credit ≈ 1 standard request; heavy models cost more). No posted $/M-token table for the hosted catalog. |
| **Dashboard** | [build.nvidia.com/credits](https://build.nvidia.com/credits). NGC keys at [org.ngc.nvidia.com](https://org.ngc.nvidia.com). |
| **Changelog** | **Nemotron-3** family (Ultra-550B, Super-120B-A12B, Nano-30B-A3B, Nano-Omni-30B). Heavy expansion into third-party frontier models (DeepSeek V4 Pro/Flash, Mistral Large 3 675B + Medium 3.5 + Small 4, MiniMax M2.7/M3, Stepfun, Z.ai GLM 5.1/4.7, Qwen3-Coder-480B). New async `202`+polling pattern for heavy endpoints. Healthcare microservices (AlphaFold2, Boltz2, OpenFold3). |
| **Adapter** | `fetch_nvidia_native` — public `/v1/models` catalogue probe; it does not claim that the key is validated. |

### MiniMax

| | |
| --- | --- |
| **API base** | `https://api.minimax.io/v1` (OpenAI-compat); Anthropic-compat `https://api.minimax.io/anthropic`. Legacy TTS host `api.minimax.chat`. No `.cn` host. |
| **Env var** | `MINIMAX_API_KEY`. Two key types: pay-as-you-go **API Key** vs Token-Plan **Subscription Key** (not interchangeable). |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | `GET /v1/models` → `200` lists `MiniMax-M3`, `MiniMax-M2.7`, `MiniMax-M2.5`… Zero tokens. |
| **Quota / balance** | ❌ None. Dashboard-only. Token-Plan usage shown as a console bar (5-hour rolling + weekly). Errors: `1004` auth failed, `1008` insufficient balance, `1002` rate limit, `1039` token limit exceeded. |
| **Plans** | **Token Plan** (replaces old "Coding Plan"): **Plus $20** / **Max $50** / **Ultra $120**/mo — full-spectrum multimodal, 5h+weekly windows, no rollover. **Credits**: $5/$25/$100 packs (1000cr = $1, 365-day). PAYG also available. |
| **Billing** | Per 1M tokens: **`MiniMax-M3`** (≤512K, **50% off**) $0.30/$1.20 (cache $0.06) &middot; >512K $0.60/$2.40 &middot; Priority tier 1.5× &middot; `MiniMax-M2.7` $0.30/$1.20 &middot; `MiniMax-M2.7-highspeed` $0.60/$2.40. Audio `speech-2.8-hd` $100/M chars; Hailuo video $0.19–$0.56/clip. |
| **Dashboard** | [platform.minimax.io](https://platform.minimax.io): keys `/user-center/basic-information/interface-key`, balance `/user-center/payment/balance`, Token Plan `/user-center/payment/token-plan`. |
| **Changelog** | **2026-06-01 MiniMax-M3** (1M ctx, adaptive thinking, coding SOTA). 2026-03-18 M2.7/M2.7-highspeed. 2026-02 M2.5. 2025-12-22 M2.1. 2025-10-27 M2 + Hailuo-2.3. Token Plan replaced Coding Plan (broader coverage, separate Subscription Key). |
| **Adapter** | `fetch_minimax_native` — `/v1/models` validation. |

### Kimi (Moonshot AI)

| | |
| --- | --- |
| **API base** | Global `https://api.moonshot.ai/v1` (USD); China `https://api.moonshot.cn/v1` (CNY). Platform rebranded: `platform.moonshot.ai` → [platform.kimi.ai](https://platform.kimi.ai) (global) / `platform.moonshot.cn` → [platform.kimi.com](https://platform.kimi.com) (China). API hosts unchanged. |
| **Env var** | `MOONSHOT_API_KEY` (fallback `KIMI_API_KEY`). Optional `MOONSHOT_API_BASE` overrides host probing. |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | `GET /v1/models` → `200`; `401` on bad key. |
| **Quota / balance** | ✅ **`GET /v1/users/me/balance`** → `200` `{data:{available_balance, voucher_balance, cash_balance}}`. USD on `.ai`, CNY on `.cn`. `available_balance = cash + voucher`. |
| **Plans** | No monthly subscription — PAYG + prepaid top-up vouchers. Top-up rebate promo (Jun–Jul 2026): ≥$100→20%, ≥$300→25%, ≥$1000→30% voucher. Rate-limit tiers scale with cumulative recharge ($1 Tier0 → $3,000 Tier5). |
| **Billing** | Per 1M tokens (256K ctx): **`kimi-k2.7-code`** $0.95/$4.00 (cache hit $0.19) &middot; `kimi-k2.7-code-highspeed` $1.90/$8.00 &middot; `kimi-k2.6` $0.95/$4.00 &middot; `kimi-k2.5` $0.60/$3.00. Automatic context caching. |
| **Dashboard** | [platform.kimi.ai/console](https://platform.kimi.ai/console) (global) / [platform.kimi.com/console](https://platform.kimi.com/console) (China). |
| **Changelog** | **`kimi-k2.7-code`** / `-highspeed` (latest coding, ~180 tok/s). `kimi-k2.6` (multimodal flagship). **`kimi-k2` series deprecated 2026-05-25**; `kimi-latest` removed 2026-01-28; `kimi-thinking-preview` removed 2025-11-11. Full OpenAPI spec at `platform.kimi.ai/docs/openapi.json`. |
| **Adapter** | `fetch_kimi_native` — balance API with global→China host probing; `displayValue` shows currency symbol. `primary` = available balance, `secondary` = voucher/cash split. |

### Qwen / DashScope (Alibaba Model Studio)

| | |
| --- | --- |
| **API base** | 5 regional modes: International (Singapore) `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`; US (Virginia) `https://dashscope-us.aliyuncs.com/compatible-mode/v1`; China (Beijing) `https://dashscope.aliyuncs.com/compatible-mode/v1`; HK `https://cn-hongkong.dashscope.aliyuncs.com/compatible-mode/v1`; EU (Frankfurt) `https://{workspace}.eu-central-1.maas.aliyuncs.com/compatible-mode/v1`. **Coding Plan** uses `https://coding-intl.dashscope.aliyuncs.com/v1` with a dedicated `sk-sp-…` key. |
| **Env var** | `DASHSCOPE_API_KEY` (fallback `QWEN_API_KEY`); optional `DASHSCOPE_WORKSPACE_ID` header. Coding Plan uses `sk-sp-…`. |
| **Auth** | `Authorization: Bearer <key>` + optional `X-DashScope-WorkSpace`. |
| **Key check** | ⚠️ `GET /compatible-mode/v1/models` is used by the adapter but is **not officially documented** in the OpenAI-compat surface — treat as best-effort. `401` confirms a bad key. |
| **Quota / balance** | ❌ None. Billing flows through Alibaba Cloud User Center (per-minute inference, per-hour batch; monthly settle). |
| **Plans** | **Coding Plan Pro $50/mo**: 6,000 req/5h, 45,000/week, 90,000/month — `qwen3.5-plus`, `kimi-k2.5`, `glm-5`, `MiniMax-M2.5`, `qwen3-coder-next/+`. Lite plan closed to new subs since 2026-03-20. Free quota (1M in+out tokens × 90 days) on International region only. |
| **Billing** | Per 1M tokens (intl, USD): `qwen3-max` $1.20/$6.00 (≤32K; doubles >128K) &middot; `qwen3.5-plus` $0.40/$2.40 (1M ctx) &middot; `qwen3.5-flash` $0.10/$0.40 &middot; `qwq-plus` $0.80/$2.40. Batch 50% off; Context Cache (input-only). CNY on China-mainland. |
| **Dashboard** | [modelstudio.console.alibabacloud.com](https://modelstudio.console.alibabacloud.com/) (intl); [bailian.console.alibabacloud.com](https://bailian.console.alibabacloud.com/) (China). Billing: Alibaba Cloud User Center. |
| **Changelog** | 2026-02 `qwen3.5-plus-2026-02-15`, `qwen3.5-flash-2026-02-23`; 2026-01-23 `qwen3-max-2026-01-23` (web-search/code-interpreter in thinking mode). New open-source `qwen3.5-{397b-a17b,120b-a10b,27b,35b-a3b}`. **Qwen-Turbo deprecated** (→ Qwen-Flash). Coding Plan Lite closed to new subs. |
| **Adapter** | `fetch_qwen_native` — `/compatible-mode/v1/models` validation. |

### xAI (Grok)

| | |
| --- | --- |
| **API base** | `https://api.x.ai/v1` (inference, OpenAI-compat). Key management: `https://management-api.x.ai` (separate, June 2025). |
| **Env var** | `XAI_API_KEY`. |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | ✅ **`GET /v1/api-key`** → `200` returns key metadata: `{redacted_api_key, name, user_id, team_id, api_key_id, api_key_blocked, api_key_disabled, team_blocked, acls, create_time, modify_time}`. `401` without key. **This is the best validator** — it also surfaces blocked/disabled state. (`GET /v1/models` also works and returns per-token prices.) |
| **Quota / balance** | ❌ No remaining-credits field on `/v1/api-key`. Account balance is dashboard-only. Per-request cost is in every response's `usage.cost_in_usd_ticks` (1 USD = 1e10 ticks) and `usage.cost_in_nano_usd` (Responses API); enable via `stream_options.include_usage:true`. |
| **Plans** | API = prepaid credits (no named tiers). `service_tier:"default"` vs `"priority"` (2× billing, higher priority — June 2026). Consumer Grok subs (Free/SuperGrok/SuperGrok Heavy) are separate from `api.x.ai`. |
| **Billing** | Per 1M tokens: **`grok-4.3`** (flagship, 1M ctx) $1.25/$2.50 &middot; `grok-4.20-0309-{reasoning,non-reasoning,multi-agent}` $1.25/$2.50 &middot; **`grok-build-0.1`** (coding, aliases `grok-code-fast-1`, `grok-code-fast`, 256K ctx) $1.00/$2.00 (cache $0.20). Batch 20–50% off. Tools billed per 1k calls (web/x search $5, code exec $5, attachment $10). Image $0.02–$0.05/img; video $0.05–$0.08/sec. |
| **Dashboard** | [console.x.ai](https://console.x.ai): keys `/team/default/api-keys`, billing `/billing`, models `/team/default/models`. Status: [status.x.ai](https://status.x.ai). |
| **Changelog** | 2026-06 Priority Processing + Files public URLs. 2026-05 **`grok-build-0.1`** coding model + Grok Build CLI + Context Compaction API + WebSocket Responses. 2026-04 `cost_in_usd_ticks` on every response. 2026-03 Grok 4.20 + Multi-agent. 2025-12 Voice Agent API GA. 2025-11 Grok 4.1 Fast + Files API GA + Remote MCP. 2025-10 agentic server-side tools GA. 2025-09 Responses API GA. 2025-07 Grok 4. **Anthropic-compat `/v1/messages` & `/v1/complete` deprecated**; `max_tokens` → `max_completion_tokens`. |
| **Adapter** | `fetch_xai_native` — `GET /v1/api-key`; surfaces key name + blocked/disabled flags in the note. |

### Kilo (kilo.ai)

| | |
| --- | --- |
| **API base** | Gateway `https://api.kilo.ai/api/gateway` (OpenAI-compat; model string is `provider/model`, e.g. `anthropic/claude-sonnet-4.5`). |
| **Env var** | `KILO_API_KEY` (JWT tied to the Kilo account). Optional headers `X-KiloCode-OrganizationId`, `X-KiloCode-TaskId`, `X-KiloCode-Version`. |
| **Auth** | `Authorization: Bearer <key>`. Anonymous access allowed **only** for `:free` models (rate-limited per IP). |
| **Key check** | ⚠️ `GET /api/gateway/models` is documented as **no-auth** — a `200` is inconclusive; a `401` indicates a malformed key. No dedicated `/api-key` validate endpoint. The reliable bad-key signal is a **`402`** on a paid call (`{error:{code:402, metadata:{buyCreditsUrl}}}`). |
| **Quota / balance** | ❌ None. Per-request `usage.cost_microdollars` (1 USD = 1e6 microdollars), `input_tokens`, `output_tokens`, `cache_*_tokens`, `is_byok`. Balance is dashboard-only. |
| **Plans** | **Kilo Code agent**: Free/OSS, Teams $15/user/mo, Enterprise. **Inference**: Auto Free / BYOK / local ($0); Kilo Gateway ($0 + PAYG at exact provider rates, **zero markup**); **Kilo Pass** — Starter $19 (≈$26.60), Pro $49 (≈$68.60), Expert $199 (≈$278.60) with up to 50% bonus credits. **KiloClaw** managed OpenClaw $55/mo. |
| **Billing** | Credit-based, **exact upstream provider rates, zero markup** (microdollar precision). Free models (`:free`) cost nothing (200 req/hour/IP → `429`). BYOK = $0 on Kilo's side. |
| **Dashboard** | [app.kilo.ai](https://app.kilo.ai): `/credits`, `/subscriptions`, `/claw`. Docs: [kilo.ai/docs](https://kilo.ai/docs). Status: [status.kilo.ai](https://status.kilo.ai). |
| **Changelog** | Agent rebuilt on Kilo CLI. **Auto Model** router (Frontier/Balanced/Free). Kilo Pass subscription with bonus credits. KiloClaw managed hosting. Kilo Marketplace (spend credits on partner plans; MiniMax first). New BYOK: Inceptron, Kimi Code, Z.ai Coding Plan, Xiaomi Token Plans. Routes 500+ models across 60+ providers (no first-party model). |
| **Adapter** | `fetch_kilo_native` — best-effort `/api/gateway/models` probe; a `401` rejects the key, otherwise falls back to the configured-status note. |

### Kiro (kiro.dev — AWS)

| | |
| --- | --- |
| **API base** | ❌ **None.** Kiro is a subscription-only agentic IDE/CLI/Web with **no public REST inference API and no API-key model**. Login is interactive SSO (GitHub / Google / AWS Builder ID / AWS IAM Identity Center). CLI install: `curl -fsSL https://cli.kiro.dev/install \| bash`. |
| **Env var** | — (no `KIRO_API_KEY`). |
| **Auth** | SSO login (not an API key). Enterprise uses AWS IAM Identity Center / SAML/SCIM. |
| **Key check** | ❌ None. |
| **Quota / balance** | ❌ None. Credits surfaced **in-product only** (IDE/CLI/Web subscription dashboard), refreshed at least every 5 minutes. |
| **Plans** | **Free** $0 (50 cr) &middot; **Pro** $20 (1,000 cr) &middot; **Pro+** $40 (2,000 cr) &middot; **Pro Max** $100 (5,000 cr, new 2026-06-10) &middot; **Power** $200 (10,000 cr). $20 sign-up bonus on first upgrade. No daily/weekly rate limits. Credits metered to 0.01, no rollover, processed on the 1st. Overage **$0.04/credit** (opt-in). GovCloud ~+20%, no Free. **HIPAA eligible** (IDE+CLI) since 2026-05-26. |
| **Billing** | Monthly sub + credit multiplier per model: Auto 1×, Claude Sonnet 4.6 1.3×, **Claude Opus 4.8 2.2×**, Haiku 4.5 0.4×, DeepSeek v3.2 0.25×, MiniMax M2.5 0.25×. Taxes not included. |
| **Dashboard** | [app.kiro.dev/settings/account](https://app.kiro.dev/settings/account). Docs: [kiro.dev/docs/billing](https://kiro.dev/docs/billing/). Pricing: [kiro.dev/pricing](https://kiro.dev/pricing/). |
| **Changelog** | 2026-06-17 CLI v2.8 (CLI v3 early access). 2026-06-12 CLI v2.7 (`/goal` loops, queue steering). 2026-06-10 **Pro Max** tier. 2026-05-29 **Claude Opus 4.8** (2.2×, 1M ctx). 2026-05-26 HIPAA eligible. CLI v2.6/v2.7 transcript export, persistent prefs. |
| **Adapter** | Informational card only (`json_note_usage kiro-local`). Links to [app.kiro.dev](https://app.kiro.dev). No scriptable surface. |

## Direct tests

Every provider has a `providers/get-<id>-usage` entrypoint and is covered by `providers/get-provider-health`. Examples:

```bash
./providers/get-codex-usage | jq .
./providers/get-openrouter-usage | jq .
./providers/get-ollama-usage | jq .
./providers/get-xai-usage | jq .
./providers/get-kimi-usage | jq .
./providers/get-provider-health "codex,openrouter,ollama,xai,kimi" | jq .
./providers/get-provider-usage "gemini,cloudflare,mistral,glm,nvidia,minimax,kimi,qwen,xai,kilo,kiro" | jq .
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

Errors use `{provider, source, error:{code, kind, message}}`. A provider without a quota API uses a normal informational `usage` object (via `json_note_usage`) rather than an error — `primary.resetDescription` carries the human label and `primary.displayValue` (optional) carries a string to render.
