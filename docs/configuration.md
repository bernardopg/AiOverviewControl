# Configuration

All settings are stored through Dux Shell. Plugin updates do not overwrite user choices.

## Settings

| Key | Values | Default | Purpose |
| --- | --- | --- | --- |
| `languageOverride` | `auto`, `en_US`, `pt_BR`, `zh_CN`, `es_ES`, `de_DE` | `auto` | UI language. `auto` follows the system locale. |
| `providerSelection` | comma-separated IDs | `codex,claude,copilot` | Enabled providers; at least one is retained. |
| `refreshInterval` | 60000, 120000, 300000, 900000, 1800000 | 120000 | Refresh interval in milliseconds. |
| `showErrorProviders` | `true` / `false` | `true` | Keep failed provider cards visible. |
| `densityMode` | `comfortable`, `compact` | `comfortable` | Compact cards hide the preview bar; expanded details remain available. |
| `pillMode` | `auto`, `custom`, `top` | `auto` | Bar pill providers: measurable providers, an explicit compact subset, or the most-used provider. |
| `pillProviders` | comma-separated IDs | provider selection | Strict provider subset used by `custom` pill mode. The settings UI exposes this as provider chips and never falls back to every tracked provider. |
| `claudeProfiles` | JSON object (stored as a string) | `{}` | Up to 16 named Claude accounts, keyed by unique `claude-...` provider IDs; each entry contains `name` and an absolute `configDir`. Manage them under **Claude profiles** in settings. |
| `barWindowOverrides` | `provider:slot,...` | empty | Per-provider bar usage window, for example `claude:secondary`. Slot is `primary`, `secondary`, `tertiary`, `highest` (most-constrained), `all`, or several windows joined with `+`, such as `claude:primary+secondary`. A provider without a pair uses the automatic window (**Automatic** in Settings): the primary window, unless the primary still has room while a later window is used up (100% or more), in which case that window is shown, so an account blocked by its weekly limit reads 100% rather than an idle 5 hour window's 0%. `primary` keeps the primary window even then. With more than one window the pill tags each percentage with its length (`5h 45% / 7d 80%`), and the `top`/`auto` pill modes rank the provider by the highest of them. The card header and its ring follow the automatic window too; card bodies list every window, and sorting, the hero, the fleet rollup and history keep the primary window. Notifications follow the displayed window by default (`notifyWindowScope` = `displayed`). Windows missing from the payload are skipped; when none of the chosen windows exists, the primary window is shown. |
| `pillTooltip` | `true` / `false` | `true` | Hovering the bar pill shows the provider, the quota window the percentage came from, and the reset. With one provider in the pill it also appends `resets in ...`. |
| `pillShowNames` | `true` / `false` | `true` | Show each provider's name in the horizontal bar pill. `false` keeps only the logo and percentage; the tooltip still names the provider. Vertical bars never show names. |
| `showRemainingQuota` | `true` / `false` | `false` | Show remaining quota (`100 − used`) in bar percentages, tooltips and dashboard quota bars/rings. Labels in the dashboard and tooltip identify remaining quota. Colors, provider ranking, fleet load/peak, historical charts, notifications and analytics shares still use consumption. |
| `pillCompact` | `true` / `false` | `false` | Tighter bar pill: drops the padding spaces around the `·` separator between providers and shrinks the gap between logo, name, and percentage (vertical bars: the gap between providers). |
| `pinnedProviders` | comma-separated IDs | empty | Pinned cards sort before other cards. |
| `providerLogoColor` | QML color string | current Dux Shell primary color | Monochrome tint used for provider logos and notification icons. |
| `quotaNotifications` | `true` / `false` | `true` | Enables quota threshold notifications. |
| `notifyThreshold` | 75, 85, or 95 | 85 | Global notification threshold. Per-provider `notifyThresholds` overrides accept any value from 1–100. |
| `notifyThresholds` | `provider:percent,...` | empty | Per-provider threshold overrides, for example `codex:75,claude:90`. Settings validates the CSV inline: malformed pairs, unknown or duplicated providers, providers that are not tracked, and percentages outside 1–100 are reported as you type. |
| `notifyWindowScope` | `displayed`, `all`, `primary` | `displayed` | Which quota windows raise alerts. `displayed` follows `barWindowOverrides` — without an override it is the automatic window, which is the primary one unless a later window is used up, and every window of a multi-window override raises its own alert. `all` also alerts on Claude's 7 day, Codex's weekly, and every other secondary window. `primary` restores the pre-1.12 primary-only behaviour. Each window keeps its own dedupe key, so one provider can alert on both of its windows without either replacing the other. |
| `notifyCooldownMinutes` | 0, 60, 360, or 1440 | 0 | Minutes between repeat alerts; `0` means once per quota window. |
| `historyRetention` | 500, 2000, or 10000 | 2000 | Maximum history snapshots kept locally. |
| `showClaudeProjects` | `true` / `false` | `true` | Shows Claude local project analytics. |
| `showAntigravityModelDetails` | `true` / `false` | `false` | In expanded Antigravity cards, replaces concise Gemini / Claude & OpenAI family rows with individual model rows. |

### Analytics currency

`costCurrency` defaults to `USD` and accepts `USD`, `EUR`, `BRL`, `GBP`, `CAD`,
`CNY`, `JPY`, `AUD` or `CHF`. It changes estimated analytics cost display only;
amounts stored/exported and provider-native balances remain unchanged. Missing
exchange rates fall back to explicitly labeled USD. `AIOC_NO_FX=1` prevents rate
requests. See [currency.md](currency.md).

## Exporting usage history

The local store (`${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl/usage-history.jsonl`)
is trimmed to `historyRetention` snapshots, so long-term data needs a copy.
Settings offers **Export usage history** with two formats, and the same script
is runnable directly:

```bash
./providers/export-usage-history csv     # spreadsheet-friendly
./providers/export-usage-history jsonl   # raw store
./providers/export-usage-history csv ~/some/directory
```

It prints the absolute path of the file it wrote on stdout and writes it
`0600`. The destination defaults to the XDG download directory, then
`~/Downloads`, then `$HOME`.

## Resetting

**Reset plugin settings** in Settings restores every key in this table to its
default, including tracked providers, pins, notification thresholds, and
bar window overrides. It is a two-step confirmation and never touches the
recorded usage history.

## Multiple Claude accounts

In settings, open **Claude profiles** and enter a unique provider ID (for example
`claude-work`), display name and **absolute** `CLAUDE_CONFIG_DIR` directory. Sign in
first with `CLAUDE_CONFIG_DIR=/absolute/path claude auth login --claudeai`.
Adding a profile automatically tracks it; its chip can later disable it without
removing the saved profile. **Remove** deletes the profile and its active selection,
pin, custom-pill and alert/window overrides, but not credentials, caches or history.
To change a profile's directory, remove it and add it again. Use a new ID for a
different account to keep historical data separate. Resetting settings clears all
profile definitions. Paths are literal, not shell expressions: `~` and `$HOME` are
not expanded. IDs use lowercase letters, digits, `_` or `-` after `claude-` (1–56
characters; the first must be a letter or digit). Names are 1–80 characters.

When upgrading from a version without Claude profiles, restart Dux Shell once
(`dms restart`) so Qt discovers the new JavaScript module; later profile changes
only require a refresh.

The ordinary `claude` provider still uses the shell's `CLAUDE_CONFIG_DIR`, or
`~/.claude` by default. Additional profiles have their own cards, quota windows,
readiness, pins, window choices, notifications and IPC focus targets. Every Claude
provider, the default one and each profile, also gets its own full **Claude Code
details** panel (tier, session/weekly/scoped windows, daily bars, costs, model and
project breakdown, all-time totals), built from that provider's own config
directory. Account snapshots and transcript caches live under
`AiOverviewControl/claude-profiles/<canonical-directory-sha256>/`; pricing and CLI
version caches are shared. Old unscoped account snapshots are not trusted.

The dispatcher and health helper also accept these definitions through
`AIOC_CLAUDE_PROFILES`, for example:

```bash
AIOC_CLAUDE_PROFILES='{"claude-work":{"name":"Claude Work","configDir":"/home/user/.claude-work"}}' \
  providers/get-provider-usage claude,claude-work | jq .
```

Credentials stay in their own directory and are sent only to Anthropic's OAuth
usage API. No token is stored in plugin settings.

## Antigravity display

The preferred `retrieveUserQuotaSummary` presentation mirrors Antigravity's quota screen: **Gemini Models** and **Claude & OpenAI Models**, each with separate 5-hour and weekly windows. The compact card uses the most constrained reported window, while the expanded card keeps all four truthful windows. If that endpoint is unavailable, the adapter falls back to `fetchAvailableModels`; that compatibility view groups models by family and uses the least remaining model in each family. Internal placeholder entries are never displayed.

One detected account stays in the normal provider-card layout. When two or more local Antigravity sessions are found, the expanded card shows one clearly labelled block per account and install. If one session fails while another succeeds, the card remains live and shows a partial-account warning with the failed stage and reason. Enable **Show individual Antigravity models** only when diagnosing a model-specific difference; it intentionally adds more rows.

## Environment variables

Environment variables must be present in the process that starts Dux Shell. Shell-only exports (including `~/.zshenv`) may not reach a graphical session. For a systemd-managed Dux Shell session, either run `cmd login` for Command Code (the plugin safely reads its CLI-owned `~/.commandcode/auth.json` fallback), or import an already-exported key and restart Dux Shell:

```bash
systemctl --user import-environment COMMAND_CODE_API_KEY
systemctl --user restart dms.service
```

For a durable environment-variable setup, configure your display manager or user-service environment rather than relying on an interactive shell.

### Keys from the keyring

A provider key can come from the freedesktop keyring instead, read at the moment of use. Give the provider a lookup spec and the adapter runs `secret-tool lookup` with those words whenever the environment has no key:

```bash
AIOC_VAULT_OPENROUTER="service openrouter username quota"
AIOC_VAULT_ZAI="service zai username quota"
AIOC_VAULT_GLM="service glm username quota"
AIOC_VAULT_OPENCODE="service opencode username quota"
```

Store the key under the same attributes first, for example:

```bash
secret-tool store --label="OpenRouter quota" service openrouter username quota
```

The spec names the attributes the entry is stored under, so it is not a secret and can live in the display manager's or the user service's environment file, such as `~/.config/environment.d/90-dms.conf`. It is split on whitespace and never glob-expanded, so it must be a list of attribute/value pairs, and no attribute or value can contain a space; a spec with an odd number of words is ignored. The key never enters the process environment or a command line: it reaches `curl` through the same `--config` pipe as an exported key, and it is never cached or logged. An exported key still wins, so an existing setup keeps working unchanged.

The adapters refresh in the background, so a lookup must never raise an unlock prompt. Before reading the key, the adapter asks the Secret Service (`SearchItems` over D-Bus through `busctl`, which never prompts) where the entry lives; when it sits only in a locked collection, or does not exist, no lookup runs and the card reports the missing key until the keyring is unlocked. The login keyring is normally unlocked at sign-in, so this only matters for a separate collection or a keyring locked by hand. When the Secret Service cannot be asked, the lookup still runs, bounded by `AIOC_VAULT_TIMEOUT` in seconds (default 3), so a keyring that does not answer delays one refresh rather than blocking it. Readiness accepts a spec without asking the keyring anything, so opening the settings never raises a prompt.

## Provider readiness labels

The settings health check describes whether the plugin can run an adapter in the current shell process; it is not a claim that the provider publishes a quota API.

- **Ready** means the required CLI, local session, database, or environment variable was found.
- **Missing** names the credential or executable that Dux Shell cannot see. In particular, a key exported only by an interactive shell is invisible when Dux Shell was started by the graphical session.
- **Informational** means the provider does not expose a stable public read-only quota surface. The plugin can still show a card that points to the official usage page.
- **Checking…** is transient while the asynchronous readiness command runs. Provider changes made during a running check are queued and checked immediately afterward.

| Provider | Variables |
| --- | --- |
| Copilot | `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN`; `AIOC_NO_DOH_FALLBACK=1` disables the `dns.google` DNS-over-HTTPS fallback used to resolve an alternate `api.github.com` edge after a regional route fails (TLS hostname verification stays enabled either way) |
| Antigravity | No environment variable is normally required. Credentials are discovered from `~/.gemini/antigravity-cli/antigravity-oauth-token`, the desktop keyring, or the IDE state database. Optional `ANTIGRAVITY_API_BASE_URL` retargets Cloud Code Assist (and turns the local language server path off); `ANTIGRAVITY_QUOTA_METHOD` can pin the compatibility method for diagnostics. While the Antigravity app runs, its local language server answers for the account it is signed in to; `ANTIGRAVITY_NO_LOCAL_RPC=1` skips it and asks the cloud endpoint for every account. |
| Gemini | Gemini CLI sign-in (`~/.gemini/oauth_creds.json`) for per-model quota with a Code Assist Standard or Enterprise project; optional `GOOGLE_CLOUD_PROJECT` (or `GOOGLE_CLOUD_PROJECT_ID`) selects the project. Otherwise `GEMINI_API_KEY`, `GOOGLE_API_KEY`, or `GOOGLE_GENERATIVE_AI_API_KEY` for a key check. The CLI token is renewed in memory only; `GEMINI_CLI_OAUTH_CLIENT_ID`, `GEMINI_CLI_OAUTH_CLIENT_SECRET`, `GEMINI_CLI_TOKEN_URL` and `GEMINI_CODE_ASSIST_ENDPOINT` override the CLI's defaults for diagnostics |
| OpenRouter | `OPENROUTER_API_KEY`, or `AIOC_VAULT_OPENROUTER` for a keyring entry |
| OpenCode | `OPENCODE_API_KEY`, or `AIOC_VAULT_OPENCODE` for a keyring entry; otherwise the CLI's `~/.local/share/opencode/auth.json` |
| DeepSeek | `DEEPSEEK_API_KEY` |
| Kimi | Balance: `MOONSHOT_API_KEY` or `KIMI_API_KEY` (optional `MOONSHOT_API_BASE`). Kimi Code subscription quota: `KIMI_CODING_API_KEY` (or a `sk-kimi-` prefixed `KIMI_API_KEY`; optional `KIMI_CODE_BASE_URL`; legacy `KIMI_BASE_URL` also accepted) |
| MiniMax | `MINIMAX_TOKEN_PLAN_KEY` (Token Plan Subscription Key, `sk-cp-...`) — backward-compatible: a `sk-cp-` value in `MINIMAX_API_KEY` is also recognised. PAYG `sk-api-` keys stay on `MINIMAX_API_KEY` and surface auth-only; set both to keep an auth-only card when the Token Plan endpoint is unreachable. Optional `MINIMAX_API_BASE` retargets both read-only endpoints at a gateway or mirror. |
| Command Code | `COMMAND_CODE_API_KEY`, or the `apiKey` saved by `cmd login` in `~/.commandcode/auth.json` |
| GLM / Z.ai | `ZAI_API_KEY`, `GLM_API_KEY`, or `ZHIPU_API_KEY`; or a keyring entry through `AIOC_VAULT_ZAI` (Z.ai card) or `AIOC_VAULT_GLM` (GLM card); optional `GLM_API_BASE` |
| Mistral | `MISTRAL_API_KEY` |
| Ollama | optional `OLLAMA_HOST`; requires the `ollama` CLI in PATH |
| Ollama Cloud | `OLLAMA_API_KEY` |
| Hermes | optional `HERMES_HOME` (defaults to `~/.hermes`); `AIOC_NO_LITELLM=1` disables the daily LiteLLM fetch that prices rows the ledger left unresolved (they then reuse the last snapshot, or stay unknown with none) |
| Claude Code | optional `CLAUDE_CONFIG_DIR` (defaults to `~/.claude`); `AIOC_NO_LITELLM=1` disables the daily LiteLLM pricing fetch from `raw.githubusercontent.com` (cost fields then reuse the last cached snapshot, or report 0.00 with none) |
| NVIDIA | `NVIDIA_API_KEY` (verified against NGC) |
| Neuralwatt | `NEURALWATT_API_KEY` |
| Anthropic API | `ANTHROPIC_ADMIN_KEY` (or `ANTHROPIC_ADMIN_API_KEY`), an Admin API key from a Claude Console organization; optional `ANTHROPIC_MONTHLY_BUDGET_USD` shows the month's spend as a percentage of that amount |
| OpenAI API | `OPENAI_ADMIN_KEY`, an organization Admin API key; optional `OPENAI_MONTHLY_BUDGET_USD` shows the month's spend as a percentage of that amount |
| Vercel AI Gateway | `AI_GATEWAY_API_KEY` (an AI Gateway API key, not a Vercel access token) |
| Cline | `CLINE_API_KEY`, or an unexpired Cline CLI sign-in in `${CLINE_DATA_DIR:-~/.cline/data}/settings/providers.json` |
| Cloudflare | `CLOUDFLARE_AI_TOKEN` or `CLOUDFLARE_API_TOKEN`; optional `CLOUDFLARE_ACCOUNT_ID` |
| Vertex AI | requires `gcloud auth print-access-token` to succeed at collection time; the readiness chip checks only that the `gcloud` CLI is in `PATH`. Optional `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`, or `VERTEXAI_PROJECT` enrich the reported identity |
| BytePlus | `BYTEPLUS_API_KEY` or `ARK_API_KEY` |
| Qwen | `DASHSCOPE_API_KEY` or `QWEN_API_KEY`; optional `DASHSCOPE_WORKSPACE_ID` |
| Together | `TOGETHER_API_KEY` |
| Groq | `GROQ_API_KEY`; optional `GROQ_QUOTA_MODEL` turns on the rate-limit probe (one 1-token completion to that model per `GROQ_QUOTA_TTL` seconds, default `1800`) |
| Cohere | `COHERE_API_KEY` |
| Replicate | `REPLICATE_API_TOKEN` |
| Fireworks | `FIREWORKS_API_KEY`; optional `FIREWORKS_ACCOUNT_ID` enables quota data |
| AI21 | `AI21_API_KEY` |
| xAI | `grok login` (`~/.grok/auth.json` or `$GROK_HOME`) for SuperGrok usage. Keep the Grok CLI installed so the adapter can renew its short-lived OIDC access token. Optional `XAI_API_KEY` (inference auth-only). Prepaid API credits: `XAI_MANAGEMENT_KEY` or `XAI_MANAGEMENT_API_KEY`, plus `XAI_TEAM_ID`. Optional `GROK_CLI_CHAT_PROXY_BASE_URL` overrides the CLI billing host, and `XAI_REFRESH_COOLDOWN` (seconds, default `300`) how soon a failed token renewal may be retried. |
| Grok Bot | No environment variable is normally required: sign in to the Grok Bot desktop app, and the adapter reads its session from `${XDG_CONFIG_HOME:-~/.config}/Grok Bot/sand-secrets.json`. Optional `GROKBOT_CONFIG_DIR` points at another app data directory (an empty value disables discovery); `GROKBOT_API_URL` retargets the `GetSandUsageStatus` request for diagnostics and receives the session token, so point it only at a host you trust. A session whose key lives in the desktop keyring (Electron safeStorage `v11`) cannot be read: start Grok Bot with `--password-store=basic` and sign in again, or the card shows the app's last saved reading. |
| Kilo | `KILO_API_KEY` |

## Health indicators

The settings page executes `providers/get-provider-health` for selected providers:

- Green: required CLI, local database, or environment variable is present.
- Amber: a prerequisite is missing.
- Neutral: informational provider or no check is applicable.

Health checks do not send network requests and never print secret values.

Quota notifications require `flock` in the shell process environment. They use `notify-send` (libnotify) when it is installed and fall back to `dms notify` otherwise; the fallback cannot replace an earlier popup in place, set urgency or open the provider card on click. Antigravity readiness accepts a valid `agy` token file, `secret-tool` for keyring-backed sessions, or `sqlite3` plus a readable IDE state database.
