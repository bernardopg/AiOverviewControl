# Configuration

All settings are stored through DMS. Plugin updates do not overwrite user choices.

## Settings

| Key | Values | Default | Purpose |
| --- | --- | --- | --- |
| `languageOverride` | `auto`, `en_US`, `pt_BR`, `zh_CN`, `es_ES`, `de_DE` | `auto` | UI language. `auto` follows the system locale. |
| `providerSelection` | comma-separated IDs | `codex,claude,copilot` | Enabled providers; at least one is retained. |
| `refreshInterval` | 60000, 120000, 300000, 900000, 1800000 | 120000 | Refresh interval in milliseconds. |
| `showErrorProviders` | `true` / `false` | `true` | Keep failed provider cards visible. |
| `densityMode` | `comfortable`, `compact` | `comfortable` | Compact cards hide the preview bar; expanded details remain available. |
| `pillMode` | `auto`, `custom`, `top` | `auto` | DankBar pill providers: selected, custom list, or the most-used provider. |
| `pillProviders` | comma-separated IDs | provider selection | Provider IDs used by `custom` pill mode. |
| `pinnedProviders` | comma-separated IDs | empty | Pinned cards sort before other cards. |
| `quotaNotifications` | `true` / `false` | `true` | Enables quota threshold notifications. |
| `notifyThreshold` | 1–100 | 85 | Global notification threshold. |
| `notifyThresholds` | `provider:percent,...` | empty | Per-provider threshold overrides, for example `codex:75,claude:90`. |
| `notifyCooldownMinutes` | non-negative integer | 0 | Minutes between repeat alerts; `0` means once per quota window. |
| `historyRetention` | integer >= 50 | 2000 | Maximum history snapshots kept locally. |
| `showClaudeProjects` | `true` / `false` | `true` | Shows Claude local project analytics. |
| `showAntigravityModelDetails` | `true` / `false` | `false` | In expanded Antigravity cards, replaces concise Gemini / Claude & OpenAI family rows with individual model rows. |

## Antigravity display

The default presentation mirrors Antigravity's Models screen: **Gemini Models** and **Claude & OpenAI Models**. Each family shows the most constrained model's usage and reset, which is the safe value to act on when models share a quota pool.

One detected account stays in the normal provider-card layout. When two or more local Antigravity sessions are found, the expanded card shows one clearly labelled block per account and install. Enable **Show individual Antigravity models** only when diagnosing a model-specific difference; it intentionally adds more rows.

## Environment variables

Environment variables must be present in the process that starts DMS. Shell-only exports may not reach a graphical session.

| Provider | Variables |
| --- | --- |
| Copilot | `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN` |
| Gemini | `GEMINI_API_KEY`, `GOOGLE_API_KEY`, or `GOOGLE_GENERATIVE_AI_API_KEY` |
| OpenRouter | `OPENROUTER_API_KEY` |
| DeepSeek | `DEEPSEEK_API_KEY` |
| Kimi | `MOONSHOT_API_KEY` or `KIMI_API_KEY`; optional `MOONSHOT_API_BASE` |
| MiniMax | `MINIMAX_API_KEY` |
| GLM / Z.ai | `ZAI_API_KEY`, `GLM_API_KEY`, or `ZHIPU_API_KEY`; optional `GLM_API_BASE` |
| Mistral | `MISTRAL_API_KEY` |
| Ollama | optional `OLLAMA_HOST` |
| NVIDIA | `NVIDIA_API_KEY` |
| Cloudflare | `CLOUDFLARE_AI_TOKEN` or `CLOUDFLARE_API_TOKEN`; optional `CLOUDFLARE_ACCOUNT_ID` |
| Vertex AI | optional `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`, or `VERTEXAI_PROJECT` |
| BytePlus | `BYTEPLUS_API_KEY` or `ARK_API_KEY` |
| Qwen | `DASHSCOPE_API_KEY` or `QWEN_API_KEY`; optional `DASHSCOPE_WORKSPACE_ID` |
| Together | `TOGETHER_API_KEY` |
| Groq | `GROQ_API_KEY` |
| Cohere | `COHERE_API_KEY` |
| Replicate | `REPLICATE_API_TOKEN` |
| Fireworks | `FIREWORKS_API_KEY`; optional `FIREWORKS_ACCOUNT_ID` enables quota data |
| AI21 | `AI21_API_KEY` |
| xAI | `XAI_API_KEY` |
| Kilo | `KILO_API_KEY` |

## Health indicators

The settings page executes `providers/get-provider-health` for selected providers:

- Green: required CLI, local database, or environment variable is present.
- Amber: a prerequisite is missing.
- Neutral: informational provider or no check is applicable.

Health checks do not send network requests and never print secret values.
