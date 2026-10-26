# Providers

`providers/get-provider-usage` dispatches every selected provider independently and returns one normalized JSON object per provider. Most providers also expose a normalized `providers/get-<id>-usage` entrypoint, and every provider is covered by `providers/get-provider-health`. Claude's specialized helper emits `KEY=VALUE` data for the dispatcher to normalize; `pi` uses an inline dispatcher envelope plus `providers/get-pi-analytics`, and `hermes` computes its dispatcher envelope straight from `~/.hermes/state.db` (indexed, milliseconds) with `providers/get-hermes-analytics` feeding the expanded telemetry card.

This document is the authoritative reference for adapter authors. It records, for every provider:

- the **coverage level** the plugin can truthfully report,
- the **credential / local source** it reads,
- the **read-only key-validation endpoint** (zero token consumption),
- the **quota / balance API** if one exists,
- the **subscription plans** and **billing model**,
- the **dashboard URL** where usage lives,
- the **current flagship model(s)** and recent **changelog** highlights,
- and the **official documentation source** used.

Reviewed 2026-08-26. Provider APIs change; re-check the linked sources before changing an adapter.

## Coverage levels

Every provider maps to exactly one coverage level. The level dictates what the widget can truthfully render.

| Level | Meaning | Example providers |
| --- | --- | --- |
| **Quota** | Real `usedPercent` + reset window from a protocol/API. | `codex`, `copilot`, `antigravity`, `openrouter`, `zai`, `glm`, `fireworks` (with account ID), `commandcode`, `neuralwatt` (kWh subscription), `gemini` (Gemini CLI with a Code Assist Standard/Enterprise project), `ollama-cloud` (legacy session/weekly plans), `groq` (opt-in `GROQ_QUOTA_MODEL` probe), `opencode` (Zen mode), `xai` (Grok CLI / SuperGrok), `minimax` (Token Plan Subscription Key), `cursor` |
| **Balance** | Remaining prepaid balance / credits in real currency. | `kimi`, `deepseek`, `xai` (Management API prepaid), `neuralwatt` (prepaid USD), `cline` (credits), `ollama-cloud` (included monthly + purchased credits), `vercel` (AI Gateway credits) |
| **Analytics** | Consumption counters (requests/tokens/neurons/cost) with no remaining-quota value. | `cloudflare` (GraphQL), `9router`, `claude` (local), `pi` (local), `hermes` (local), `opencode` (local, default), `codex` (local, alongside its quota), `anthropic` and `openai` (Admin API month-to-date spend; a percentage only against an optional monthly budget) |
| **Auth / configured** | Validates credentials with a read-only endpoint when possible; otherwise reports only that a credential is configured and states the limitation. No usage numbers. | `gemini` (API key only), `mistral`, `nvidia` (NGC key verification), `qwen`, `byteplus`, `groq` (without `GROQ_QUOTA_MODEL`), `cohere`, `replicate`, `together`, `minimax` (PAYG `sk-api-` key), `kilo`, `ai21` |
| **Local runtime** | Local process / installed models. | `ollama`, `vertexai` (gcloud) |
| **Informational** | No public read-only API at all; the card just links to the dashboard. | `perplexity`, `kiro`, `warp`, `amp` |

## Provider kinds

Since 1.11.0 every provider also carries one or more **kinds** (independent from
the coverage level above). The kind drives the card's badge, icon, and accent
color:

| Kind | Providers | Meaning |
| --- | --- | --- |
| `provider` | everything else (default) | Standard API/account provider. |
| `agent` | `pi` | Local coding-agent harness; telemetry only, no account quota. |
| `agent,provider` | `hermes` | Dual nature: agent harness **and** provider front; the card renders as "Agent · Provider". |
| `gateway` | `9router` | Router that aggregates other providers behind one endpoint. |
| `local` | `ollama` | Local runtime, no cloud account. |

Coverage level (what data can be truthfully reported) and kind (what the thing
is) are orthogonal: for example `hermes` is Analytics coverage with kinds
`agent,provider`.

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
<td>✅ duration-labelled session / weekly windows, including weekly-only responses</td>
<td>✅ Plus / Pro / Team</td>
<td>✅</td>
<td><code>codex</code> login</td>
<td><a href="https://developers.openai.com/codex/app-server/">developers.openai.com</a></td>
<td><a href="https://developers.openai.com/codex/app-server/">Codex app-server</a></td>
</tr>
<tr>
<td><code>claude</code></td>
<td>Quota + local analytics</td>
<td>local <code>~/.claude</code> (or <code>$CLAUDE_CONFIG_DIR</code>)</td>
<td>✅ 5h / 7d / weekly per-model (<code>limits[]</code>)</td>
<td>✅ Pro / Max</td>
<td>✅</td>
<td><code>claude</code> OAuth, optional <code>CLAUDE_CONFIG_DIR</code></td>
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
<td><code>COPILOT_GITHUB_TOKEN</code>, <code>GH_TOKEN</code>, or <code>GITHUB_TOKEN</code> (the <code>gh</code> CLI token is tried first)</td>
<td><a href="https://github.com/settings/copilot">github.com/settings/copilot</a></td>
<td><a href="https://docs.github.com/copilot">GitHub Copilot</a></td>
</tr>
<!-- Focus providers -->
<tr>
<td><code>antigravity</code></td>
<td>Quota (Cloud Code Assist)</td>
<td>✅ local Antigravity OAuth (<code>agy</code> token file / keyring / IDE session, auto-refreshed)</td>
<td>✅ Gemini / Claude &amp; OpenAI 5h + weekly quota windows and resets; available-models compatibility fallback; per-account failures</td>
<td>✅ Antigravity plan</td>
<td>—</td>
<td><code>~/.gemini/antigravity-cli/antigravity-oauth-token</code> or <code>~/.config/Antigravity IDE</code></td>
<td>Antigravity IDE</td>
<td><code>loadCodeAssist</code> + <code>v1internal:retrieveUserQuotaSummary</code> on <code>daily-cloudcode-pa.googleapis.com</code>; <code>fetchAvailableModels</code> compatibility fallback (multi-account)</td>
</tr>
<tr>
<td><code>gemini</code></td>
<td>Quota (CLI) / Auth (key)</td>
<td>✅ <code>GET /v1beta/models</code></td>
<td>⚠️ Gemini CLI: <code>retrieveUserQuota</code> per model with a Code Assist Standard/Enterprise project; API keys: dashboard-only</td>
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
<td>✅ <code>GET /v1/models</code></td>
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
<td><code>ZAI_API_KEY</code> / <code>GLM_API_KEY</code> (<code>ZHIPU_API_KEY</code> also accepted; precedence depends on the adapter — see <a href="#glm--zai-zhipu-ai">GLM / Z.ai</a>)</td>
<td><a href="https://z.ai/manage-apikey/billing">z.ai/manage-apikey</a></td>
<td><a href="https://docs.z.ai/">docs.z.ai</a> / <a href="https://open.bigmodel.cn/dev/api">open.bigmodel.cn</a></td>
</tr>
<tr>
<td><code>nvidia</code></td>
<td>Auth</td>
<td>✅ <code>POST api.ngc.nvidia.com/v3/keys/get-caller-info</code></td>
<td>❌ dashboard-only</td>
<td>⚠️ rate-limited developer trial</td>
<td>✅ NVIDIA Cloud Credits</td>
<td><code>NVIDIA_API_KEY</code></td>
<td><a href="https://build.nvidia.com/credits">build.nvidia.com/credits</a></td>
<td><a href="https://docs.api.nvidia.com/nim/reference/models-1">docs.api.nvidia.com</a></td>
</tr>
<tr>
<td><code>neuralwatt</code></td>
<td>Quota + Balance</td>
<td>✅ <code>GET /v1/quota</code></td>
<td>✅ subscription kWh per billing period + per-key USD allowance</td>
<td>✅ energy subscription with included kWh</td>
<td>✅ prepaid USD credits</td>
<td><code>NEURALWATT_API_KEY</code></td>
<td><a href="https://portal.neuralwatt.com">portal.neuralwatt.com</a></td>
<td><a href="https://docs.neuralwatt.com/api/quota">docs.neuralwatt.com</a></td>
</tr>
<tr>
<td><code>anthropic</code></td>
<td>Analytics</td>
<td>—</td>
<td>⚠️ <code>GET /v1/organizations/cost_report</code> (month-to-date spend; no balance or limit for Console organizations)</td>
<td>—</td>
<td>✅ prepaid credits / invoiced</td>
<td><code>ANTHROPIC_ADMIN_KEY</code></td>
<td><a href="https://platform.claude.com/cost">platform.claude.com/cost</a></td>
<td><a href="https://platform.claude.com/docs/en/manage-claude/usage-cost-api">platform.claude.com/docs</a></td>
</tr>
<tr>
<td><code>openai</code></td>
<td>Analytics</td>
<td>—</td>
<td>⚠️ <code>GET /v1/organization/costs</code> (month-to-date spend; no balance or budget API)</td>
<td>—</td>
<td>✅ prepaid credits / invoiced</td>
<td><code>OPENAI_ADMIN_KEY</code></td>
<td><a href="https://platform.openai.com/usage">platform.openai.com/usage</a></td>
<td><a href="https://developers.openai.com/api/docs/guides/admin-apis">developers.openai.com</a></td>
</tr>
<tr>
<td><code>vercel</code></td>
<td>Balance</td>
<td>—</td>
<td>✅ <code>GET /v1/credits</code> (balance + total used)</td>
<td>—</td>
<td>✅ AI Gateway Credits</td>
<td><code>AI_GATEWAY_API_KEY</code></td>
<td><a href="https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai-gateway">vercel.com</a></td>
<td><a href="https://vercel.com/docs/ai-gateway/sdks-and-apis/rest-api#check-credit-balance">vercel.com/docs</a></td>
</tr>
<tr>
<td><code>minimax</code></td>
<td>Auth + Quota</td>
<td>✅ <code>GET /v1/models</code> (PAYG)<br>✅ <code>GET /v1/token_plan/remains</code> (Token Plan)</td>
<td>✅ 5h + weekly (Token Plan keys)</td>
<td>✅ Token Plan $20/$50/$120/mo</td>
<td>✅ per token (M3 50% off)</td>
<td><code>MINIMAX_API_KEY</code> · <code>MINIMAX_TOKEN_PLAN_KEY</code></td>
<td><a href="https://platform.minimax.io">platform.minimax.io</a></td>
<td><a href="https://platform.minimax.io/docs/api-reference">platform.minimax.io/docs</a></td>
</tr>
<tr>
<td><code>commandcode</code></td>
<td>Quota</td>
<td>✅ <code>GET /provider/v1/models</code></td>
<td>✅ <code>/alpha/billing/credits</code> (5h + weekly)</td>
<td>✅ Go / GOAT / Pro / Max / Team Pro / Provider API</td>
<td>✅ USD credit balance + per-window USD usage</td>
<td><code>COMMAND_CODE_API_KEY</code> or CLI <code>~/.commandcode/auth.json</code></td>
<td><a href="https://commandcode.ai/billing">commandcode.ai/billing</a></td>
<td><a href="https://commandcode.ai/docs/provider">Provider API docs</a></td>
</tr>
<tr>
<td><code>opencode</code></td>
<td>Quota</td>
<td>✅ <code>GET /zen/go/v1/models</code></td>
<td>✅ <code>/zen/go/v1/usage</code> (5h + weekly + monthly)</td>
<td>✅ OpenCode Go $10/mo</td>
<td>—</td>
<td><code>OPENCODE_API_KEY</code> or CLI <code>~/.local/share/opencode/auth.json</code></td>
<td><a href="https://opencode.ai/zen">opencode.ai/zen</a></td>
<td><a href="https://opencode.ai/docs/go">opencode.ai/docs/go</a></td>
</tr>
<tr>
<td><code>kimi</code></td>
<td>Balance / Quota</td>
<td>✅ <code>GET /v1/models</code></td>
<td>✅ <code>/v1/users/me/balance</code> (funds) &middot; <code>/coding/v1/usages</code> (Kimi Code 5h plus plan-supplied weekly/monthly windows)</td>
<td>✅ Kimi Code (tempo tiers)</td>
<td>✅ per token (USD/CNY)</td>
<td><code>MOONSHOT_API_KEY</code>, <code>KIMI_API_KEY</code>, or <code>KIMI_CODING_API_KEY</code></td>
<td><a href="https://www.kimi.com/code/console">Kimi Code console</a> / <a href="https://platform.kimi.ai/console">Open Platform</a></td>
<td><a href="https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/managed-usage.ts">Kimi Code CLI usage client</a> / <a href="https://platform.kimi.ai/docs/intro">Open Platform docs</a></td>
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
<td>Quota / Balance / Auth</td>
<td>✅ <code>GET /v1/api-key</code></td>
<td>✅ SuperGrok weekly/monthly via CLI billing; prepaid via Management API</td>
<td>✅ SuperGrok / SuperGrok Heavy; API prepaid</td>
<td>✅ per token (API)</td>
<td><code>grok login</code>, <code>XAI_API_KEY</code>, <code>XAI_MANAGEMENT_KEY</code></td>
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
<td><code>pi</code></td>
<td>Local analytics</td>
<td>local JSONL session logs</td>
<td>✅ local cost/tokens — no quota API (pi has no rate limits)</td>
<td>—</td>
<td>—</td>
<td>—</td>
<td>—</td>
<td>local store</td>
</tr>
<tr>
<td><code>hermes</code></td>
<td>Local analytics</td>
<td>local SQLite state (<code>~/.hermes/state.db</code>)</td>
<td>✅ local sessions/tokens/cost per model and project — the agent side; provider billing (Nous Portal / routed providers) stays on the portal</td>
<td>—</td>
<td>—</td>
<td>—</td>
<td>—</td>
<td><a href="https://github.com/NousResearch/hermes-agent">NousResearch/hermes-agent</a></td>
</tr>
<tr>
<td><code>openrouter</code></td>
<td>Quota/balance</td>
<td>✅ <code>GET /api/v1/key</code></td>
<td>✅ limit/daily/monthly/balance + free-model requests/day</td>
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
<td><code>ollama-cloud</code></td>
<td>Balance / Quota</td>
<td>—</td>
<td>✅ <code>GET https://ollama.com/api/balance</code> (included monthly credits or legacy session/weekly limits, purchased credits)</td>
<td>✅ Free / Pro / Max with included credits</td>
<td>✅ purchased credits</td>
<td><code>OLLAMA_API_KEY</code></td>
<td><a href="https://ollama.com/settings">ollama.com/settings</a></td>
<td><a href="https://docs.ollama.com/api/balance">docs.ollama.com</a></td>
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
<td>Auth + opt-in Quota</td>
<td>✅ <code>GET /v1/models</code></td>
<td>⚠️ requests/day + tokens/minute from <code>x-ratelimit-*</code> headers of a 1-token probe (opt-in)</td>
<td>—</td>
<td>✅</td>
<td><code>GROQ_API_KEY</code></td>
<td><a href="https://console.groq.com/dashboard/usage">console.groq.com</a></td>
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
<td><a href="https://www.perplexity.ai/settings">perplexity.ai/settings</a></td>
<td><a href="https://docs.perplexity.ai">docs.perplexity.ai</a></td>
</tr>
<tr>
<td><code>cursor</code></td>
<td>Quota</td>
<td>local IDE session or <code>cursor-agent</code> <code>auth.json</code></td>
<td>✅ billing-cycle Cursor Models and Other Models</td>
<td>✅ Hobby / Pro / Business</td>
<td>✅ on-demand when enabled</td>
<td>—</td>
<td><a href="https://cursor.com/settings">cursor.com/settings</a></td>
<td><code>cursor.com/api/usage-summary</code> (dashboard session)</td>
</tr>
<tr>
<td><code>cline</code></td>
<td>Balance</td>
<td>✅ <code>GET /api/v1/users/me</code></td>
<td>❌ ClinePass windows not read yet (only an undocumented dashboard endpoint)</td>
<td>✅ ClinePass plan + billing period</td>
<td>✅ credits (micro-USD)</td>
<td><code>CLINE_API_KEY</code> or Cline CLI sign-in</td>
<td><a href="https://app.cline.bot/dashboard/account?tab=credits">app.cline.bot</a></td>
<td><a href="https://docs.cline.bot/enterprise-solutions/api-reference">docs.cline.bot</a></td>
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

## Local fallbacks and aliases

**OpenRouter → 9Router local fallback.** When `OPENROUTER_API_KEY` is unset,
the dispatcher serves the card from the local 9Router store instead
(`fetch_9router_native openrouter openrouter soft`); the account label reads
"openrouter via 9router (local)" so locally routed data is never mistaken for
upstream OpenRouter API quota. With the variable set, the real
`/api/v1/key` snapshot is used.

**Aliases.** The dispatcher (`get-provider-usage`) and health checker
(`get-provider-health`) accept these case-insensitive aliases:

| Canonical | Aliases |
| --- | --- |
| `commandcode` | `cmd`, `cmdcode` |
| `antigravity` | `agy` |
| `kimi` | `moonshot` |
| `glm` | `zhipu` |
| `zai` | `z.ai` |
| `nvidia` | `nim` |
| `vertexai` | `vertex` |
| `byteplus` | `ark`, `modelark` |
| `qwen` | `dashscope`, `alibaba` |
| `xai` | `grok` |
| `anthropic` | `anthropic-api` |
| `openai` | `openai-api` |
| `vercel` | `ai-gateway` |

## Provider reference

Detailed adapter notes for the focus providers (Gemini, Cloudflare, Mistral, GLM/Z.ai, NVIDIA, MiniMax, Kimi, Qwen, xAI, Kilo, Kiro). All HTTP probes below are read-only and consume **no tokens**.

### Gemini (Google)

| | |
| --- | --- |
| **API base** | `https://generativelanguage.googleapis.com/v1beta` (OpenAI-compat: `/v1beta/openai/`). No China mirror; enterprise path is Vertex AI. |
| **Env var** | `GEMINI_API_KEY` (fallbacks `GOOGLE_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY`); also detected via local Gemini CLI (`~/.gemini/oauth_creds.json`). |
| **Auth** | Header `x-goog-api-key: <key>` (preferred) or query `?key=<key>`. |
| **Key check** | `GET /v1beta/models` → `200` lists models; `403` missing key; `400` malformed. Zero tokens. |
| **Quota / balance** | Gemini CLI sign-in: `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` for the Code Assist project, then `POST …/v1internal:retrieveUserQuota` with `{project}` returns one bucket per model (`remainingFraction`, `resetTime`, `modelId`, `tokenType`), the same calls the CLI makes (`packages/core/src/code_assist/server.ts` in google-gemini/gemini-cli). `GOOGLE_CLOUD_PROJECT` (or `GOOGLE_CLOUD_PROJECT_ID`) overrides the project. Google no longer offers Code Assist for individuals to the Gemini CLI (`ineligibleTiers[].reasonCode` `UNSUPPORTED_CLIENT`, re-checked 2026-10-26); such an account has no project, and the card shows Google's reason. API keys: ❌ none, usage and rate limits are dashboard-only. |
| **Plans** | Free + tiered PAYG (Tier 1 $250 cap → Tier 3 $20k+ cap, auto-upgrade by spend/age). No flat monthly API subscription. Enterprise = Gemini Enterprise Agent Platform. |
| **Billing** | Prepaid credits → pay-as-you-go per token. Batch API 50% off; cached/prompt discounts. |
| **Flagship pricing (/M tok)** | `gemini-3.5-flash` $1.50/$9.00 &middot; `gemini-3.1-pro-preview` $2.00/$12.00 (≤200k) &middot; `gemini-3.1-flash-lite` $0.25/$1.50 &middot; `gemini-2.5-pro` $1.25/$10.00. |
| **Dashboard** | [aistudio.google.com](https://aistudio.google.com) (rate limits), [console.cloud.google.com/billing](https://console.cloud.google.com/billing). |
| **Changelog** | **Gemini 3.5** Flash GA; **Gemini 3.1 Pro** preview (vibe-coding/customtools). Gemini 2.0 Flash/Flash-Lite **shut down 2026-06-01**. Imagen 4 deprecated (→ Gemini 2.5 Flash Image). Veo 3/2 → Veo 3.1. Gemini Embedding 2 (multimodal). |
| **Adapter** | `fetch_gemini_native` — with `~/.gemini/oauth_creds.json`, renews an expired access token in memory with the CLI's public installed-app client (the file is never written; `GEMINI_CLI_OAUTH_CLIENT_ID`/`GEMINI_CLI_OAUTH_CLIENT_SECRET` override it) and shows the three most used model buckets as daily windows. Without a project it reports the ineligibility reason, unless an API key is set; then, and when the sign-in cannot be renewed, it falls back to the API-key probe or the sign-in note. |

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
| **Env var** | Per adapter: `fetch_zai_native` (global card) uses `ZAI_API_KEY` → `GLM_API_KEY` → `ZHIPU_API_KEY`; `fetch_glm_native` (China console card) uses `GLM_API_KEY` → `ZHIPU_API_KEY` → `ZAI_API_KEY`. Any one key drives both cards. |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | `GET /api/monitor/usage/quota/limit` → `200` with `success: true` and `data.limits[]`; `401`/`403` on bad key. Zero tokens. Falls back to `GET /paas/v4/models` when quota endpoint is unavailable. |
| **Quota / balance** | ✅ `/api/monitor/usage/quota/limit` returns `data.limits[]` — each limit has `type` (`TIME_LIMIT` or `TOKENS_LIMIT`), `percentage` (0–100), `nextResetTime` (epoch ms), `remaining`, `unit`, and `number`. Live cross-check against the Z.ai Usage page confirms the period unit table used by the adapter: `unit=4` → 5-hour session window, `unit=6` → weekly quota, `unit=5` → monthly web/search/reader quota, `unit=3` → total token allotment (no reset window). Also returns `data.level` (plan tier, e.g. `lite`). |
| **Plans** | PAYG per token **or** **GLM Coding Plan** (Lite $18, **Pro $72**, Max $160/mo; quarterly/annual discounts). Subscription usage exposes a 5-hour session quota, weekly token quota, and monthly Web Search / Reader / Zread quota; supported in Claude Code, Cline, OpenCode, Roo, Kilo, Crush, Goose, OpenClaw. **GLM-5.2 & GLM-5-Turbo consume 3× quota at peak (14:00–18:00 UTC+8), 2× off-peak** (1× off-peak promo through end of September). |
| **Billing** | Per 1M tokens: **`glm-5.2`** $1.40/$4.40 (cached $0.26) &middot; `glm-5`/`glm-5-turbo` $1.0–$1.2/$3.2–$4.0 &middot; `glm-4.7`/`4.6`/`4.5` $0.60/$2.20 &middot; `glm-4.7-flash` & `glm-4.5-flash` **Free** &middot; `glm-5v-turbo` (vision) $1.2/$4.0. Web Search $0.01/use. |
| **Dashboard** | [API keys](https://z.ai/manage-apikey/apikey-list), [subscription](https://z.ai/manage-apikey/subscription) (Coding Plan), and [billing](https://z.ai/manage-apikey/billing) (finance). China: [open.bigmodel.cn](https://open.bigmodel.cn). |
| **Changelog** | **GLM-5.2** live (1M lossless context, 128K max output, MCP, structured output). Lineage: 4.5 → 4.6 → 4.7 → 5 → 5-Turbo → 5.1 → **5.2**. New GLM-5V-Turbo (vision coding), GLM-Image, CogVideoX-3, GLM-ASR-2512, GLM-OCR. Coding Plan restructured (legacy plans migrated by 2026-04-30). |
| **Adapter** | `fetch_glm_native` (China console, `open.bigmodel.cn`) and `fetch_zai_native` (global, `api.z.ai`). Both call `GET /api/monitor/usage/quota/limit` for real quota data; fall back to `GET /models` auth-only check if the quota endpoint is unavailable. Sorts limits by urgency (highest % first among timed windows), then maps to primary / secondary / tertiary. |

### NVIDIA (NIM / build.nvidia.com)

| | |
| --- | --- |
| **API base** | `https://integrate.api.nvidia.com/v1` (OpenAI-compatible). No regional mirror; backed by DGX Cloud. |
| **Env var** | `NVIDIA_API_KEY` (NGC personal key, `nvapi-` prefix). |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | `POST https://api.ngc.nvidia.com/v3/keys/get-caller-info` with the key as the `credentials` form field — the endpoint the official `ngc` CLI uses. An invalid or revoked key returns `401`; a valid one returns the key `type` (`PERSONAL_KEY` / `SERVICE_KEY`), `orgName` and, for personal keys, the owner. The key is sent in the request body from stdin, never in argv or the URL. `GET /v1/models` is public and answers `200` to any key, so it is no longer used. |
| **Quota / balance** | ❌ None documented (re-checked 2026-10-26). build.nvidia.com no longer gives trial credits: trial usage is limited by per-model rate limits that NVIDIA does not publish, and there is no per-account rate-limit or credits API; the current limit is visible only on build.nvidia.com. Practical exhaustion signal: inference returns `402`/`429`. |
| **Plans** | Rate-limited Developer trial, NVIDIA Cloud Credits (USD blocks), and NVIDIA AI Enterprise for self-hosted NIM. |
| **Billing** | **Credit-based per request** (1 credit ≈ 1 standard request; heavy models cost more). No posted $/M-token table for the hosted catalog. |
| **Dashboard** | [build.nvidia.com/credits](https://build.nvidia.com/credits). NGC keys at [org.ngc.nvidia.com](https://org.ngc.nvidia.com). |
| **Changelog** | **Nemotron-3** family (Ultra-550B, Super-120B-A12B, Nano-30B-A3B, Nano-Omni-30B). Heavy expansion into third-party frontier models (DeepSeek V4 Pro/Flash, Mistral Large 3 675B + Medium 3.5 + Small 4, MiniMax M2.7/M3, Stepfun, Z.ai GLM 5.1/4.7, Qwen3-Coder-480B). New async `202`+polling pattern for heavy endpoints. Healthcare microservices (AlphaFold2, Boltz2, OpenFold3). |
| **Adapter** | `fetch_nvidia_native` — NGC caller-info key verification. When the key service is unreachable the card degrades to an unverified "key set" note instead of an error. |

### MiniMax

| | |
| --- | --- |
| **API base** | `https://api.minimax.io/v1` (OpenAI-compat); Anthropic-compat `https://api.minimax.io/anthropic`. `api.minimaxi.com` is the same backend under the older international hostname and works with `MINIMAX_API_BASE`. Legacy TTS host `api.minimax.chat`. No `.cn` host. |
| **Env var** | `MINIMAX_TOKEN_PLAN_KEY` (Token Plan Subscription Key, `sk-cp-...`) takes precedence; legacy `MINIMAX_API_KEY` is honoured too. Pay-as-you-go **API Keys** (`sk-api-...`) and Token-Plan **Subscription Keys** (`sk-cp-...`) are not interchangeable. Optional `MINIMAX_API_BASE` retargets both read-only endpoints at a gateway or mirror. |
| **Auth** | `Authorization: Bearer <key>`. |
| **Key check** | **Token Plan** — `GET /v1/token_plan/remains` → `200` returns `model_remains[]` (5h + weekly percent, Unix-ms reset). **PAYG** — `GET /v1/models` → `200` lists `MiniMax-M3`, `MiniMax-M2.7`, `MiniMax-M2.5`… Zero tokens. |
| **Quota / balance** | **Token Plan** — the `general` bucket of `model_remains[]` when it is readable, otherwise the first readable bucket: `current_interval_remaining_percent` (5h), `model_remains[].current_weekly_remaining_percent` (7-day), `end_time` / `weekly_end_time` (Unix-ms reset). The percent fields report what **remains**, and the counts fallback (`total - usage`) is only used when the percent is absent. Window minutes 300 / 10080; the UI keeps the existing `null` label so the localised 5h/weekly header is reused. Availability is decided **per window**, never per bucket: `status == 2` → 100% used; `status == 3` with a zero counted quota (the window is not part of the plan) omits that window entirely, so a capped 5h interval never hides a real weekly figure and no card ever fabricates an `Unlimited` or 0% line. A bucket with no readable window at all is skipped, and when no bucket is readable the adapter surfaces a provider error. **PAYG** — dashboard-only; balance at `platform.minimax.io/user-center/payment/balance`. Errors: `1004` auth failed, `1008` insufficient balance, `1002` rate limit, `1039` token limit exceeded. |
| **Plans** | **Token Plan** (replaces old "Coding Plan"): **Plus $20** / **Max $50** / **Ultra $120**/mo — full-spectrum multimodal, 5h+weekly windows, no rollover. **Credits**: $5/$25/$100 packs (1000cr = $1, 365-day). PAYG also available. |
| **Billing** | Per 1M tokens: **`MiniMax-M3`** (≤512K, **50% off**) $0.30/$1.20 (cache $0.06) &middot; >512K $0.60/$2.40 &middot; Priority tier 1.5× &middot; `MiniMax-M2.7` $0.30/$1.20 &middot; `MiniMax-M2.7-highspeed` $0.60/$2.40. Audio `speech-2.8-hd` $100/M chars; Hailuo video $0.19–$0.56/clip. |
| **Dashboard** | [platform.minimax.io](https://platform.minimax.io): keys `/user-center/basic-information/interface-key`, balance `/user-center/payment/balance`, Token Plan `/user-center/payment/token-plan`. |
| **Changelog** | **2026-06-01 MiniMax-M3** (1M ctx, adaptive thinking, coding SOTA). 2026-03-18 M2.7/M2.7-highspeed. 2026-02 M2.5. 2025-12-22 M2.1. 2025-10-27 M2 + Hailuo-2.3. Token Plan replaced Coding Plan (broader coverage, separate Subscription Key). |
| **Adapter** | `fetch_minimax_native` — routes to **Token Plan** (`/v1/token_plan/remains`) for `MINIMAX_TOKEN_PLAN_KEY` or `sk-cp-` `MINIMAX_API_KEY`; uses **PAYG** (`/v1/models`) for `sk-api-` keys. When a Token Plan probe fails and a separate `sk-api-` key is configured, the card degrades to the PAYG auth-only view instead of blanking the provider; a `sk-cp-` key is never replayed against `/v1/models`. Token Plan key is **never** used to run paid inference. |

### Command Code

| | |
| --- | --- |
| **API base** | `https://api.commandcode.ai/provider/v1` (OpenAI/Anthropic-compatible); quota `https://api.commandcode.ai/alpha/billing/credits` (Bearer, no cookies). |
| **Credentials** | `COMMAND_CODE_API_KEY` (preferred when available to DMS), or the `apiKey` in CLI-owned `~/.commandcode/auth.json` after `cmd login`. Both are the same Provider API key used for `/provider/v1/models`, `/alpha/whoami`, `/alpha/billing/credits`. |
| **Auth** | `Authorization: Bearer ***` |
| **Quota / balance** | `/alpha/billing/credits` returns `windowLimits.fiveHour` (5h USD used/cap, Unix-ms `resetAt`), `windowLimits.weekly` (7-day USD used/cap, Unix-ms `resetAt`), and `credits.monthlyCredits` (remaining USD this billing cycle). `/alpha/billing/subscriptions` exposes `planId` (e.g. `individual-goat`) and `currentPeriodEnd`. |
| **Plans** | **Go** $1 / $10 credit &middot; **GOAT** $10 / $70 credit, 5h $14 / weekly $35 &middot; **Pro** $20 / $80 credit, 5h $16 / weekly $40 &middot; **Max 10×** $100 / $150 credit, 5h $45 / weekly $90 &middot; **Max 20×** $200 / $300 credit, 5h $90 / weekly $180 &middot; **Team Pro** $40 / $40 credit, 5h $12 / weekly $24 &middot; **Provider API** $15 + pay-as-you-go. |
| **Billing** | Per-token, no markup on the Provider plan. Credits roll over and never expire. Window caps are USD ceilings — model deals (e.g. `minimax-m3` 2×, `google/gemini-3.7-flash` 50% off, `mimo-v2.5-pro` 99% off) apply automatically. |
| **Stability** | The `/alpha/` namespace is **experimental** — no documented versioned contract, can change without notice. Adapter degrades to the documented `/provider/v1/models` endpoint on alpha failure and emits a clearly-labeled "quota endpoint unavailable" note; it never fabricates a percentage. |
| **Dashboard** | [commandcode.ai/billing](https://commandcode.ai/billing) — billing, plan, and credit top-ups. |
| **Adapter** | `fetch_commandcode_native` — `/alpha/billing/credits` + `/alpha/whoami` + `/alpha/billing/subscriptions`, with documented-endpoint fallback. |

### Groq

| | |
| --- | --- |
| **API base** | `https://api.groq.com/openai/v1` (OpenAI-compatible). |
| **Env var** | `GROQ_API_KEY`; optional `GROQ_QUOTA_MODEL` (e.g. `openai/gpt-oss-120b`) and `GROQ_QUOTA_TTL` (seconds, default `1800`). |
| **Key check** | `GET /models`. |
| **Quota** | No usage, spend or limits API (checked 2026-10-13; the console's usage and limits pages are UI-only). Limits are per organization **and per model**, and Groq reports them only as `x-ratelimit-*` headers on a served completion: `limit/remaining/reset-requests` are **requests per day**, `limit/remaining/reset-tokens` are **tokens per minute**. Rejected requests (400/404) carry no headers. The daily counter refills continuously (1,000/day refills one request every 86.4 s), so `reset-requests` is the time until it is full again, not midnight. |
| **Probe** | Opt-in. With `GROQ_QUOTA_MODEL` set, the adapter sends one `max_completion_tokens: 1` completion (`"."` as the prompt, about 70 tokens) to that model at most every `GROQ_QUOTA_TTL` seconds and caches the headers in `groq-rate-limits-<model>.json`. At the default 30 minutes that is 48 requests a day, counted against the same limit it reports (about 5% of the 1,000 RPD of `openai/gpt-oss-120b` on the free plan). Usage by other apps on the same key and model, such as a dictation tool, shows up in the remaining count. A 429 with nothing left reads as 100%. |
| **Not shown** | RPM, TPD and audio-seconds limits (no header carries them). |
| **Dashboard** | [console.groq.com/dashboard/usage](https://console.groq.com/dashboard/usage), [limits](https://console.groq.com/settings/limits). |
| **Adapter** | `fetch_groq_native` / `groq_rate_limit_probe`. |

### Neuralwatt

| | |
| --- | --- |
| **API base** | `https://api.neuralwatt.com/v1` (OpenAI-compatible inference). |
| **Env var** | `NEURALWATT_API_KEY` (`sk-` prefix; create at [portal.neuralwatt.com](https://portal.neuralwatt.com) → Dashboard → API Keys). |
| **Auth** | `Authorization: Bearer <key>`. |
| **Quota / balance** | `GET /v1/quota` returns everything in one read-only call: `balance` (prepaid USD, `credits_remaining_usd` / `total_credits_usd`, no reset), `subscription` (`kwh_included` / `kwh_used`, `current_period_end`, `in_overage`, `status`; `null` without a subscription) and `key.allowance` (per-key `limit_usd` / `spent_usd` per `daily` / `weekly` / `monthly` period, `blocked`; `null` unless budget control is on). `subscription.kwh_used` is the billed basis (consumed × pricing multiplier), so it is what counts against the allowance. Limit: 1 request/second per customer (`429`). |
| **Card** | Primary: subscription kWh for the billing period (100% while in overage), resetting at `current_period_end`. Then the prepaid balance as `remaining / total`, then the per-key allowance (100% when `blocked`). A prepaid-only account shows the balance first. A non-active subscription status (`past_due`, `paused`, …) is appended to the account line. |
| **Not shown** | `GET /v1/usage/energy` (daily energy and carbon) — the card has no daily chart for this provider. |
| **Dashboard** | [portal.neuralwatt.com](https://portal.neuralwatt.com). |
| **Adapter** | `fetch_neuralwatt_native` — one `/v1/quota` call per refresh. |

### Ollama Cloud

| | |
| --- | --- |
| **API base** | `https://ollama.com` (`OLLAMA_CLOUD_API_BASE` overrides it for tests). |
| **Env var** | `OLLAMA_API_KEY` (create at [ollama.com/settings/keys](https://ollama.com/settings/keys)). |
| **Auth** | `Authorization: Bearer <key>`. |
| **Quota / balance** | `GET /api/balance` — `included` is either the monthly credits (`balance_usd`, `allowance_usd`, `period.until`) or, on legacy plans, `session` and `weekly` limits (`remaining_percent`, `resets_at`); `purchased.balance_usd` is the bought credit. 10 requests per minute per user, shared across keys and devices; `429` carries `Retry-After`. |
| **Card** | Monthly plans: included credits used against the allowance, resetting at `period.until`. Legacy plans: session (5 h) and weekly windows. Then the purchased credits. |
| **Dashboard** | [ollama.com/settings](https://ollama.com/settings). |
| **Adapter** | `fetch_ollama_cloud_native` — one `/api/balance` call per refresh. Separate from the local `ollama` card, which reads the local server. |

### Anthropic API (Claude Console)

| | |
| --- | --- |
| **API base** | `https://api.anthropic.com` (`ANTHROPIC_ADMIN_API_BASE` overrides it for tests). |
| **Env var** | `ANTHROPIC_ADMIN_KEY` (fallback `ANTHROPIC_ADMIN_API_KEY`): an Admin API key (`sk-ant-admin…`) from an organization; regular API keys cannot read cost data. Optional `ANTHROPIC_MONTHLY_BUDGET_USD`. |
| **Auth** | `x-api-key: <key>` and `anthropic-version: 2023-06-01`. |
| **Quota / balance** | ⚠️ `GET /v1/organizations/cost_report?starting_at=<month start>&bucket_width=1d&limit=31` — daily buckets with `results[].amount` in cents as decimal strings, `has_more`/`next_page` pagination. There is no balance or spend-limit endpoint for Console organizations (the Spend Limits API is Claude Enterprise only). Priority Tier costs are not in the cost report. |
| **Card** | Month-to-date spend (UTC month) and today's spend. With `ANTHROPIC_MONTHLY_BUDGET_USD` the month row becomes a percentage of that budget. Claude subscription limits stay on the `claude` card. |
| **Dashboard** | [platform.claude.com/cost](https://platform.claude.com/cost). |
| **Adapter** | `fetch_anthropic_native` — one request per refresh, following `next_page` at most twice. |

### OpenAI API (Platform)

| | |
| --- | --- |
| **API base** | `https://api.openai.com` (`OPENAI_ADMIN_API_BASE` overrides it for tests). |
| **Env var** | `OPENAI_ADMIN_KEY`: an Admin API key from [platform.openai.com/settings/organization/admin-keys](https://platform.openai.com/settings/organization/admin-keys). Optional `OPENAI_MONTHLY_BUDGET_USD`. |
| **Auth** | `Authorization: Bearer <key>`. |
| **Quota / balance** | ⚠️ `GET /v1/organization/costs?start_time=<month start, unix>&bucket_width=1d&limit=31` — daily buckets with `results[].amount.value` in USD, `has_more`/`next_page` pagination. No balance or budget endpoint. |
| **Card** | Month-to-date spend (UTC month) and today's spend; with `OPENAI_MONTHLY_BUDGET_USD` the month row becomes a percentage. ChatGPT plan limits stay on the `codex` card. |
| **Dashboard** | [platform.openai.com/usage](https://platform.openai.com/usage). |
| **Adapter** | `fetch_openai_native` — one request per refresh, following `next_page` at most twice. |

### Vercel AI Gateway

| | |
| --- | --- |
| **API base** | `https://ai-gateway.vercel.sh/v1` (`AI_GATEWAY_API_BASE` overrides the host for tests). |
| **Env var** | `AI_GATEWAY_API_KEY` — an AI Gateway API key; a plain Vercel access token is rejected. |
| **Auth** | `Authorization: Bearer <key>`. |
| **Quota / balance** | `GET /v1/credits` → `{"balance": "95.50", "total_used": "4.50"}` (USD strings): the team's AI Gateway Credits balance and lifetime spend. Budgets (`/ai-gateway/budgets/list`) need a Vercel access token and are not read. |
| **Card** | Balance (the bar fills only when it is used up) and total used. |
| **Dashboard** | [vercel.com → AI Gateway](https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai-gateway). |
| **Adapter** | `fetch_vercel_native` — one `/v1/credits` call per refresh. |

### Cline

| | |
| --- | --- |
| **API base** | `https://api.cline.bot/api/v1` — the account API the Cline CLI and IDE use ([reference](https://docs.cline.bot/enterprise-solutions/api-reference)). |
| **Credentials** | `CLINE_API_KEY` (app.cline.bot → Settings → API Keys), or the Cline CLI sign-in in `${CLINE_DATA_DIR:-~/.cline/data}/settings/providers.json` while its access token is unexpired. The plugin never refreshes that token: a refresh can rotate the refresh token, and the plugin does not write into Cline's data directory. The access token lasts about one hour, and the CLI renews it whenever it runs (`cline config` is enough). Run `cline` once to renew an expired sign-in, or use `CLINE_API_KEY` for a credential that does not expire. |
| **Quota / balance** | `GET /users/me` → user id and organizations; `GET /users/{id}/balance`, or `GET /organizations/{orgId}/balance` when an organization is active (the account Cline bills). `balance` is micro-USD — the Cline CLI divides it by 1,000,000. `GET /users/me/plan` → ClinePass plan name and `currentPeriodEnd` (404 `no plan history found for user` without a subscription). `GET /users/{id}/usages?limit=200&cursor=<nextToken>` (or `/organizations/{orgId}/members/{memberId}/usages`) → the request log, newest first: `createdAt`, `aiModelTypeName` (`cline-free` for free models), `totalTokens`, `creditsUsed` (micro-USD; 0 for free models) and `costUsd` (list price, not billed). Responses may be wrapped in `{success, data}`. |
| **Card** | Credits balance (no total exists, so the bar fills only when depleted); today's requests, tokens, free-model requests and billed credits, from local midnight (at most 5 pages, shown as `≥N` when cut); and, with a subscription, the plan with its renewal date. Free models have a daily per-model limit, but Cline reports it only as a `429 Free limit reached on model … Try again in …` at inference time, with no number; ClinePass likewise has no usage-limit endpoint. |
| **Dashboard** | [app.cline.bot](https://app.cline.bot/dashboard/account?tab=credits). |
| **Adapter** | `fetch_cline_native`. |

### OpenCode

Two independent modes. The **local** mode is the default whenever an OpenCode
database exists, because OpenCode is commonly driven against third-party and
free-tier providers with no Zen subscription — the Zen quota endpoint would
only report an entitlement error there. Set `OPENCODE_USAGE_SOURCE=api` to
force the Zen path.

| | |
| --- | --- |
| **Local source** | `${OPENCODE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode}/opencode.db` (SQLite, read-only). The schema is detected per database. v1 assistant rows live in `message` joined to `session`, carrying flat `providerID`/`modelID`; v2 (2026) uses `session_message` (`type = 'assistant'`) joined to `session_v2`, with the model nested under `model.{id,providerID}`. Both shapes carry `tokens` and `cost`. In an upgraded database, legacy-only v1 sessions remain visible, while a session id also present in v2 is read from v2 alone rather than double-counted. Only usage metadata is read, never message content. Costs come from whatever OpenCode recorded — a missing cost makes the window unknown (`—`) rather than `$0`. |
| **Local adapter** | `fetch_opencode_native` (local branch) + `providers/get-local-analytics opencode`, cached 120s. |

#### OpenCode Go (Zen quota mode)

| | |
| --- | --- |
| **API base** | `https://opencode.ai/zen/go/v1` — OpenCode Zen's Go-plan quota surface, alongside the OpenAI-compatible `/zen/v1` inference API. |
| **Credentials** | `OPENCODE_API_KEY` (preferred when available to DMS), or the `key` in CLI-owned `${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json` (saved by `opencode auth login`). The adapter follows this XDG path on Linux, the plugin's supported platform. The same key created in OpenCode Studio/Zen drives both inference and quota introspection. |
| **Auth** | `Authorization: Bearer ***` |
| **Quota / balance** | `/zen/go/v1/usage` returns `rollingUsage` (5h window), `weeklyUsage`, and `monthlyUsage`, each `{status, resetInSec, usagePercent}` — percentages are computed server-side, so the adapter never derives them from raw byte/token counts. The adapter accepts a quota response only when all three windows have valid percentage/reset values; otherwise it falls back to auth-only status. `resetInSec` is seconds-from-now, converted to an absolute ISO 8601 timestamp. `useBalance: true` is rendered as **balance fallback enabled**; the endpoint does not return the balance amount, so none is invented. |
| **Plans** | **OpenCode Go** $10/mo — $12 of usage per 5-hour window, $30 weekly, $60 monthly. |
| **Billing** | Flat monthly subscription; no PAYG surfaced through this endpoint. |
| **Stability** | The `/zen/go/` namespace shipped alongside the Go plan (opencode PR #16513) and has no documented versioned contract. Adapter degrades to `/zen/go/v1/models` (auth-only) on failure and emits a clearly-labeled "quota endpoint unavailable" note; it never fabricates a percentage. A missing/invalid key returns `401 AuthError`; a valid key without a Go subscription returns `403 EntitlementError` — both surface as hard errors, not soft notes. |
| **Dashboard** | [opencode.ai/zen](https://opencode.ai/zen) — Zen usage and Go plan management. |
| **Adapter** | `fetch_opencode_native` (API branch) — `/zen/go/v1/usage`, with `/zen/go/v1/models` fallback. |

### Kimi (Moonshot AI)

See [domain and live-schema verification](kimi-domains-research.md) for the
first-party `.com` Code endpoint and separate Moonshot Open Platform hosts.
`kimi-code` is independently selectable; selecting `kimi` with both an Open
Platform key and `KIMI_CODING_API_KEY` returns separate balance/subscription
cards. A single subscription key preserves the legacy `kimi` behavior.

| | |
| --- | --- |
| **Two systems** | Kimi exposes **two independent quota surfaces with non-interchangeable keys.** ① **Open Platform** (prepaid *balance*): `sk-xxx` key on `api.moonshot.ai`/`.cn`. ② **Kimi Code / Coding Plan** (subscription *quota*): `sk-kimi-xxx` key on `api.kimi.com/coding/v1` — the same data the Kimi CLI `/usage` command reads. The adapter routes by key (see **Env var** / **Adapter**). |
| **API base** | Open Platform — Global `https://api.moonshot.ai/v1` (USD); China `https://api.moonshot.cn/v1` (CNY). Kimi Code — `https://api.kimi.com/coding/v1`; the first-party CLI also recognizes global `https://api.kimi.ai/coding/v1`. Override with `KIMI_CODE_BASE_URL` (`KIMI_BASE_URL` remains a plugin alias). Platform rebranded: `platform.moonshot.ai` → [platform.kimi.ai](https://platform.kimi.ai) (global) / `platform.moonshot.cn` → [platform.kimi.com](https://platform.kimi.com); API hosts unchanged. |
| **Env var** | Balance: `MOONSHOT_API_KEY` (fallback `KIMI_API_KEY`); optional `MOONSHOT_API_BASE` overrides host probing. Kimi Code: `KIMI_CODING_API_KEY`, **or** a `KIMI_API_KEY`/`MOONSHOT_API_KEY` carrying the `sk-kimi-` prefix; optional `KIMI_CODE_BASE_URL` (`KIMI_BASE_URL` alias). An explicit coding key wins over the balance path. |
| **Auth** | `Authorization: Bearer <key>` (both systems). Coding Plan requests also send `User-Agent: KimiCLI/1.6`. |
| **Key check** | Balance: `GET /v1/models` → `200`; `401` on bad key. Coding Plan: the `/usages` probe doubles as the key check (`401`/`403` = wrong key type, `404` = wrong base URL). |
| **Quota / balance** | Balance: ✅ **`GET /v1/users/me/balance`** → `{data:{available_balance, voucher_balance, cash_balance}}` (USD on `.ai`, CNY on `.cn`; `available_balance = cash + voucher`). Kimi Code: CLI-owned **`GET /coding/v1/usages`** → exact counted `limits[]` (including 5h) plus plan-supplied ratio pools `usages.limit_5h`, `limit_7d`, and `limit_month_total` (`used_ratio`, `reset_time`). `limit_month_code` is the code share of the combined monthly total, not another allowance. The card prefers the exact 5h count, shows the combined monthly pool when present, and never invents an absent weekly limit. |
| **Plans** | **Open Platform** remains prepaid PAYG. Kimi Code membership entitlement and model permission are shown by the Kimi Code console, but `/usages` does not return a reliable plan name or model entitlement; the adapter deliberately does not guess either. Its quota windows are plan-dependent: a current Pro account can expose a 5h frequency count plus a monthly pool, with no weekly window. |
| **Billing** | Per 1M tokens (256K ctx): **`kimi-k2.7-code`** $0.95/$4.00 (cache hit $0.19) &middot; `kimi-k2.7-code-highspeed` $1.90/$8.00 &middot; `kimi-k2.6` $0.95/$4.00 &middot; `kimi-k2.5` $0.60/$3.00. Automatic context caching. |
| **Dashboard** | Balance: [platform.kimi.ai/console](https://platform.kimi.ai/console) (global) / [platform.kimi.com/console](https://platform.kimi.com/console) (China). Kimi Code: [Kimi Code console](https://www.kimi.ai/code/console); the card's open-console action chooses this URL for `source: kimi-code`. |
| **Changelog** | **`kimi-k3`** (max quality) and **`kimi-k2.7-code`** / `-highspeed` (routine coding, ~180 tok/s). `kimi-k2.6` (multimodal flagship). **`kimi-k2.5` + `moonshot-v1` retire 2026-08-31** → migrate to `kimi-k2.7-code` or `kimi-k3`. **`kimi-k2` series deprecated 2026-05-25**; `kimi-latest` removed 2026-01-28; `kimi-thinking-preview` removed 2025-11-11. Full OpenAPI spec at `platform.kimi.ai/docs/openapi.json`. |
| **Adapter** | `fetch_kimi_native` routes by key: `sk-kimi-`/`KIMI_CODING_API_KEY` → `fetch_kimi_code_native` (Kimi Code `GET /usages`; exact counted 5h plus API-supplied weekly/monthly ratio pools, `source: kimi-code`); otherwise the balance API with global→China host probing (`source: kimi-api`, `primary` = available balance, `secondary` = voucher/cash split). The contract is tracked in [Kimi Code usage research](kimi-code-usage-research.md). |

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
| **API base** | Inference: `https://api.x.ai/v1`. Grok Build CLI billing: `https://cli-chat-proxy.grok.com/v1` (override `GROK_CLI_CHAT_PROXY_BASE_URL`). Management: `https://management-api.x.ai`. |
| **Env var** | `grok login` writes `~/.grok/auth.json` (or `$GROK_HOME/auth.json`). Optional `XAI_API_KEY` (inference). Prepaid API credits: `XAI_MANAGEMENT_KEY` or `XAI_MANAGEMENT_API_KEY`, plus `XAI_TEAM_ID`. Optional `XAI_REFRESH_COOLDOWN` (seconds, default `300`). |
| **Auth** | SuperGrok: `Authorization: Bearer <CLI token>` + `x-xai-token-auth: xai-grok-cli`. The adapter delegates expired OIDC token renewal to the installed Grok CLI. Inference / Management: `Authorization: Bearer <key>`. |
| **Key check** | ✅ **`GET /v1/api-key`** for inference keys → `{redacted_api_key, name, user_id, team_id, api_key_id, api_key_blocked, api_key_disabled, team_blocked, acls, …}`. `401` without key; invalid keys often return HTTP 400 (`invalid-argument`). |
| **Quota / balance** | ✅ SuperGrok / Grok Build: `GET {cli-proxy}/billing?format=credits` — `config.creditUsagePercent` (omitted percent on a valid `currentPeriod` is 0%), weekly/monthly window from `currentPeriod.type` / `.end`. Plan label from `{cli-proxy}/settings` → `subscription_tier_display`. ✅ API prepaid: `GET https://management-api.x.ai/v1/billing/teams/{team_id}/prepaid/balance` — `total.val` is an inverted USD-cent ledger (a $12.50 top-up is `"-1250"`). The ledger settles behind the console, so mid-cycle spend can read slightly high. ❌ Inference `XAI_API_KEY` has no remaining-credits field. |
| **Plans** | Consumer Grok subs (Free / SuperGrok / SuperGrok Heavy) are separate from `api.x.ai`. API = prepaid credits (no named tiers). `service_tier:"default"` vs `"priority"` (2× billing, higher priority — June 2026). |
| **Billing** | Per 1M tokens: **`grok-4.3`** (flagship, 1M ctx) $1.25/$2.50 &middot; `grok-4.20-0309-{reasoning,non-reasoning,multi-agent}` $1.25/$2.50 &middot; **`grok-build-0.1`** (coding, aliases `grok-code-fast-1`, `grok-code-fast`, 256K ctx) $1.00/$2.00 (cache $0.20). Batch 20–50% off. Tools billed per 1k calls (web/x search $5, code exec $5, attachment $10). Image $0.02–$0.05/img; video $0.05–$0.08/sec. |
| **Dashboard** | [console.x.ai](https://console.x.ai): keys `/team/default/api-keys`, management keys, billing `/billing`, models `/team/default/models`. Status: [status.x.ai](https://status.x.ai). |
| **Changelog** | 2026-06 Priority Processing + Files public URLs. 2026-05 **`grok-build-0.1`** coding model + Grok Build CLI + Context Compaction API + WebSocket Responses. 2026-04 `cost_in_usd_ticks` on every response. 2026-03 Grok 4.20 + Multi-agent. 2025-12 Voice Agent API GA. 2025-11 Grok 4.1 Fast + Files API GA + Remote MCP. 2025-10 agentic server-side tools GA. 2025-09 Responses API GA. 2025-07 Grok 4. **Anthropic-compat `/v1/messages` & `/v1/complete` deprecated**; `max_tokens` → `max_completion_tokens`. |
| **Adapter** | `fetch_xai_native` — prefers Grok CLI billing, renews refreshable OIDC sessions through `grok models` (at most once per `XAI_REFRESH_COOLDOWN`), then falls back to Management API prepaid balance and `GET /v1/api-key` auth-only. It retries billing once only for `401` or `403`. |

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

### Codex local telemetry

Alongside the `app-server` quota windows, the Codex card shows a local
telemetry panel built from `~/.codex/sessions/**/*.jsonl` (and
`archived_sessions/`), honouring `CODEX_HOME`.

| | |
| --- | --- |
| **Source** | `event_msg` / `token_count` events. Only usage counters, `cwd`, and the model name are read — never prompt or response content. |
| **Cumulative counters** | `total_token_usage` is cumulative for the session and is re-emitted unchanged on turns that add no tokens. The adapter sums **positive deltas** between consecutive snapshots, so repeated values are not double-counted and a counter reset (a new total lower than the previous one) restarts from zero instead of producing a negative row. `last_token_usage` is deliberately unused: it is also repeated. |
| **Cost** | Codex sessions record tokens, not money. Each row is priced at its model's list price from LiteLLM's public table (the one the Hermes and Claude adapters use, refreshed once a day; `AIOC_NO_LITELLM=1` keeps the last snapshot): uncached input, cached input and output at their own rates. Under a Plus/Pro subscription this is what the same tokens would cost on the API, not a charge, as on the Claude card. A model with no list price stays unknown (`—`), and a window containing one reports `—` rather than a partial sum. |
| **Bucketing** | Rows are bucketed by the event's own local calendar day (via `TZ`), unlike pi/Hermes which bucket a whole session to its start day. |
| **Adapter** | `providers/get-local-analytics codex`, cached 120s. |

### Codex backend launch discipline

Every `codex app-server` startup runs a marketplace refresh round; when an
upgrade keeps being interrupted, each round leaves git temp directories under
`~/.codex/.tmp/` that Codex itself does not clean up (upstream issues:
[openai/codex#30620](https://github.com/openai/codex/issues/30620),
[#36093](https://github.com/openai/codex/issues/36093)). A quota poll must
therefore launch as few backends as possible:

- **Direct stdio mode.** Each cache refresh starts `codex app-server` and sends
  newline-delimited JSON-RPC over stdin. `codex app-server proxy` is a raw byte
  relay to the daemon's **WebSocket** Unix socket; it does not translate JSONL
  into WebSocket frames. Sending JSONL through it silently receives no replies,
  so this adapter does not use that proxy. A future daemon client would need a
  proper WebSocket handshake and framed messages.
- **Single-flight.** A `flock` on
  `~/.cache/AiOverviewControl/codex-usage.lock` serializes launches; an
  invocation arriving while another refresh runs serves the cached snapshot,
  or waits up to `CODEX_LOCK_WAIT` seconds (default 8) before returning a
  structured error.
- **Freshness gate.** A cached snapshot younger than `CODEX_FRESH_TTL` seconds
  (default 60) is answered directly — widget reload bursts no longer spawn
  anything.
- **Graceful teardown.** The backend exits on its own when stdin closes; the
  adapter waits briefly for that self-exit before falling back to
  SIGTERM/SIGKILL, so startup work in flight is not orphaned mid-clone.

To reclaim disk from already-leaked staging clones (safe when no Codex session
is running):

```bash
find ~/.codex/.tmp/marketplaces/.staging -mindepth 1 -maxdepth 1 \
  -type d -name 'marketplace-upgrade-*' -exec rm -rf {} +
find ~/.codex/.tmp -mindepth 1 -maxdepth 1 -type d -name 'git-*' -exec rm -rf {} +
```

## Utility scripts

Beyond the per-provider adapters, `providers/` ships these utilities:

- `get-local-analytics <codex|opencode>` — local harness telemetry (7-day chart, top models, top projects, per-window token breakdown), cached 120s. Shares its windowing with `scripts/local-analytics.jq`.
- `local-cost-common` — sourced helper building the Hermes cost SQL and the LiteLLM per-model pricing (`litellm-prices.json`), so the summary and analytics adapters cannot drift on which ledger rows count as a known cost or how the rest is priced.
- `get-usage-history` — prints the local usage history written by the dispatcher (`~/.cache/AiOverviewControl/usage-history.jsonl`), trimmed by `AIOC_HISTORY_MAX`.
- `export-usage-history` — copies that history to CSV or JSONL (see [configuration](configuration.md#exporting-usage-history)).
- `get-provider-wrapper` — shared single-provider wrapper behind the `get-<id>-usage` entrypoints.
- `send-quota-alert` — deduplicated desktop notification sender used by quota alerts (`flock` + `notify-send`, falling back to `dms notify`).

## Direct tests

Every provider is covered by `providers/get-provider-health`. Most providers also have a normalized `providers/get-<id>-usage` entrypoint; use the dispatcher for Claude and `providers/get-pi-analytics` for pi. Examples:

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
