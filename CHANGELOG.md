# Changelog

## [Unreleased]

## 1.4.9 - 2026-06-24

### Features
- **Cross-provider fleet overview**: the hero now shows an aggregate rollup whenever two or more providers resolve, complementing the single focused-provider view. It surfaces the fleet's average primary-window load (with a progress ring), the hottest provider and its load, how many providers sit at or above 80%, and the soonest reset across all live providers. Percent load is the only unit comparable across heterogeneous providers, so the rollup summarizes quota pressure rather than fabricating a cross-provider monetary total. The `fleetNextResetLabel` countdown re-evaluates on the same stale-tick cadence as the rest of the hero. New i18n keys `rollup.*` added across all five bundles.

## 1.4.8 - 2026-06-24

### UI
- `MetricTile` left accent bar is now a contained, fully-rounded indicator (vertically centered, inset from the edges) instead of a sharp full-height stripe — matching the v1.4.5 provider-card treatment and eliminating the rounded-clip corner bleed.

### i18n
- Dropped the orphan `card.engine` key from all five bundles (unused since the v1.4.5 hero rework replaced the Engine label).
- Added the missing `card.resets_in` key (referenced by the widget but absent from every bundle, so it had been falling back to the English string) across `en`, `pt_BR`, `es_ES`, `de_DE`, `zh_CN`. Key parity preserved (131 keys each).

### Internal
- Removed dead `barText` and `providerEngineLabel` properties from the widget — both were left unreferenced after the v1.4.5 hero rework (ring → per-window bars, Engine → Resets).
- Provider dispatch-coverage CI check no longer emits spurious warnings: the case parser now accepts dotted aliases (e.g. `z.ai`, which previously broke the regex and made `zai` look unrouted), distinguishes canonical providers from documented aliases, and ignores the dedicated non-stub adapters (claude/copilot/codex). Coverage now reports clean: 0 missing dispatch, 0 missing stub.

## 1.4.7 - 2026-06-24

### Providers
- **GitHub Copilot — quota field fixes**: the API now returns `unlimited: true` with `remaining: 0, entitlement: 0` for Chat and Completions when there is no cap. The old display function was rendering "0 / 0 remaining" for those windows. Chat and Completions are now suppressed when `unlimited == true` and `entitlement == 0` — they carry no signal and only cluttered the UI.
- **`resetsAt` now populated**: the adapter was reading `$q.reset_date` from per-snapshot fields, but that field does not exist. The actual reset date is `quota_reset_date_utc` at the top level of the response. All three windows now use it.
- **Overage count surfaced**: `premium_interactions.overage_count > 0` is appended to the display value as `(+N overage)`.
- **`has_quota: false` handling**: when the API signals the quota is exhausted via `has_quota: false`, `usedPercent` is forced to 100.
- **`unlimited` guard on `used_percent`**: unlimited windows always return `usedPercent: 0` regardless of the `percent_remaining` value.

## 1.4.6 - 2026-06-24

### Providers
- **Z.ai / GLM — real quota tracking**: both `zai` and `glm` adapters now call `GET /api/monitor/usage/quota/limit` instead of the auth-only `/models` endpoint. The response exposes `data.limits[]` — each limit carries `type` (`TIME_LIMIT` / `TOKENS_LIMIT`), `percentage` (0–100), `nextResetTime` (epoch ms), `remaining`, `unit`, and `number`. Limits are sorted by urgency (highest % among timed windows first) and mapped to primary / secondary / tertiary. `data.level` (e.g. `lite`) is surfaced as the credits field. Falls back to auth-only `/models` check when the quota endpoint is unavailable.
- Coverage level for `zai` and `glm` promoted from **Auth** → **Quota** in the provider matrix.

### Fixes
- `providerSubtitle` in the QML widget showed "reinicia" (without a reset time) when a provider returned `resetsAt: null`. `formatTimeUntil(null)` returns `""`, not `"—"`, so the `!== "—"` guard passed; the reset label was then rendered with an empty time. Fixed by checking `reset && reset !== "—"` so providers with no reset window correctly show "sem janela de reset".

## 1.4.5 - 2026-06-19

### Fixes
- Popout scrollbar no longer overlaps the content: the bar is now anchored full-height to the right edge with a reserved gutter, so cards never render underneath it (was a floating bar with a negative margin sitting on top of the content).

### UI
- Provider cards calmed: inactive cards now recede (lower accent overlay, border, and side indicator) so the hovered/focused/expanded card stands out — usage hierarchy reads by state instead of every card competing at once.
- The left accent stripe was replaced with a contained, rounded active indicator that grows when the card is expanded — no more sharp corners bleeding past the card's rounded edges.
- Account / Login / Credits moved from large metric boxes to compact inline pills (`InfoPill`), reclaiming vertical space and reducing visual clutter; Credits hides when unavailable.
- Hero overview reworked: removed the decorative background blobs, the title now names the focused provider (no longer duplicating the popout header), and the single decorative usage ring was replaced with per-window usage bars (label · value · reset, colored by usage level) — surfacing windows like Premium requests / Chat / Completions at a glance. Window labels now prefer the provider's `resetDescription`.

## 1.4.4 - 2026-06-18

### Features
- New **xAI (Grok)** provider (`xai`): validates `XAI_API_KEY` via the documented `GET /v1/api-key` endpoint (zero token consumption), surfacing the key name and blocked/disabled state. xAI signals invalid keys as HTTP 400 (`invalid-argument`), which is now handled. Falls back to `/v1/models`. Aliases: `xai`, `grok`.
- **Kilo** upgraded from informational to telemetry: validates `KILO_API_KEY` against the Kilo Gateway `GET /api/gateway/models` (best-effort — the endpoint is documented as no-auth, so only a `401` reliably rejects a key).
- **GLM** upgraded to live key validation: `GLM_API_KEY`/`ZHIPU_API_KEY` is now probed against `open.bigmodel.cn/api/paas/v4/models` (was a configured-status note).
- **MiniMax** upgraded to live key validation: `MINIMAX_API_KEY` is now probed against `api.minimax.io/v1/models` (was a configured-status note).
- **Kimi** host-probing comments updated for the platform rebrand (`platform.moonshot.ai` → `platform.kimi.ai` global, `platform.moonshot.cn` → `platform.kimi.com` China; API hosts unchanged).
- `providers/get-provider-health` now recognizes `xai` (`XAI_API_KEY`) and `kilo` (`KILO_API_KEY`).

### Fixes
- **Z.ai (`zai`) registered in the UI**: the provider was added in 1.4.3 (backend adapter, wrapper, dispatcher) but was never listed in the QML provider selectors, name/icon/accent/console-URL maps, so it was invisible to users. Now selectable in Settings and the dashboard, with its own icon, accent, and `z.ai/manage-apikey/billing` console link.
- Stale dashboard URLs refreshed: `kimi`/`moonshot` → `platform.kimi.ai/console` (rebrand), `minimax` → balance page, `kilo` → `app.kilo.ai/credits`, `kiro` → `app.kiro.dev/settings/account`.

### Documentation
- `docs/providers.md` rewritten: HTML coverage matrix with checkmarks (read-only key check, quota/balance API, subscription plan, PAYG, env var, dashboard, docs source) for all 33 providers, plus detailed per-provider reference sections for the 11 focus providers (Gemini, Cloudflare, Mistral, GLM/Z.ai, NVIDIA, MiniMax, Kimi, Qwen, xAI, Kilo, Kiro) covering base URL, auth, key-check endpoint, quota API, plans, billing/flagship pricing, dashboard, and 2025–2026 changelog highlights.
- `docs/provider-verification.md` reviewed 2026-06-18: added xAI, MiniMax, Kilo, Cloudflare GraphQL analytics surfaces; split quota-vs-auth surfaces; refreshed Kimi/Z.ai/Zhipu entries.
- `README.md` coverage model expanded and provider count badge bumped to 33.

## 1.4.3 - 2026-06-18

### Features
- New **Z.ai** provider (`zai`): validates API key via the OpenAI-compatible `GET /models` endpoint (no token consumption). Supports both subscription (GLM Coding Plan) and pay-as-you-go billing modes. Set `ZAI_API_KEY` to enable; falls back to `GLM_API_KEY` / `ZHIPU_API_KEY`. Billing visible at z.ai/manage-apikey/billing.

## 1.4.2 - 2026-06-12

### Fixes
- Vertical bar pill no longer overflows: entries show only the percentage, colored by provider accent, while the usage-severity color moves to the new progress-ring pill icon (#4, thanks @arqueon).
- `providers/get-codex-usage` now reports the real plugin version in the app-server `clientInfo` payload (was stuck at 1.4.0).

### UI
- Bar pill icon replaced with a live progress ring reflecting the hero provider's usage; pinned providers now take priority as the hero provider (#4, thanks @arqueon).
- The duplicated pill ring canvas was extracted into a shared `PillProgressRing` component.

### Documentation
- README redesigned: project banner, animated demo (GIF + MP4), refreshed dashboard/expanded-card/telemetry screenshots, DankBar pill capture, feature grid, screenshot gallery, and collapsible validation section (`docs/assets/`).
- `docs/README.pt-BR.md` rewritten as a full mirror of the English README (was stuck describing 1.3).
- `screenshot.png` updated to the current 1.4.1 dashboard (previous capture showed a pre-1.4 layout).

## 1.4.1 - 2026-06-11

### Fixes
- Quota alerts no longer fire repeatedly: notification state is persisted on disk (flock-guarded), so duplicate widget instances (multi-monitor bars), plugin reloads, and shell restarts cannot re-send the same alert inside its quota window (`providers/send-quota-alert`).
- Fixed `ReferenceError: cardMouse is not defined` — the provider card hover state referenced a MouseArea that had lost its id.

### Features
- Richer quota notifications: provider-aware title ("quota exhausted" at 100%), body with window label, remaining quota (`displayValue`) and reset countdown, `critical` urgency at 100%, and daemon-side replacement (`notify-send -r` + synchronous hint) so repeats update the existing bubble instead of stacking.
- New "Re-alert interval" setting (`notifyCooldownMinutes`): 0 alerts once per quota window (default); 60/360/1440 re-alert after that many minutes while usage stays above the threshold.
- 9Router telemetry section on the dashboard card: calendar-aligned 7-day cost chart with per-day hover (cost + requests), today/week/month totals, week token in/out, top models by 7-day cost, and routed-provider breakdown (`providers/get-9router-analytics`, reads `~/.9router/db/data.sqlite` with `usage.json` fallback).

### Localization
- Crowdin project synced with the repository: Spanish (`es-ES`) and German (`de`) added as target languages (previously only `pt-BR` and `zh-CN`), source `en.json` re-uploaded, and all four local translation bundles pushed.

## 1.4.0 - 2026-06-11

### Features
- Sparkline history points now carry timestamps; hovering shows percent and time per snapshot.
- Burn-rate forecast extended to the Claude 7-day window (warns only when on track to exhaust before reset).
- Per-model cost split: weekly model bars show tokens and estimated cost per family (`WEEK_MODEL_COSTS`).
- Keyboard navigation on provider cards: Tab focus with ring, Enter/Space expand, Delete remove, P pin, R retry; accessible names/descriptions.

### Quality
- CI integration test for the usage-history pipeline: empty-cache contract, sort/group aggregation, and dispatcher snapshot append.

### Providers
- Cloudflare: documented Workers AI GraphQL analytics (`aiInferenceAdaptiveGroups`) showing 7-day and latest-day requests/neurons when `CLOUDFLARE_ACCOUNT_ID` is set, with graceful fallback to the token-verified note card.
- OpenRouter: top-models breakdown (30 days, `/api/v1/activity`) in the tertiary window, falling back to monthly spend when unavailable.

### Settings & i18n
- Configurable usage-history retention (500/2000/10000 snapshots) passed to the dispatcher via `AIOC_HISTORY_MAX`.
- Per-provider notification threshold overrides (`claude:90,codex:75`).
- Pin/unpin providers directly from the settings provider rows.
- New Spanish (es_ES) and German (de_DE) locales with full key parity; CI and release workflows now validate all four non-English locales.
- Release checklist added at `docs/release-checklist.md`.

## 1.3.0 - 2026-06-11

### Architecture
- Removed the external aggregation executable and its settings, detection, dispatcher arguments, documentation, and diagnostics.
- Added a native Codex adapter using the official `codex app-server` protocol and `account/rateLimits/read`.
- Preserved Copilot quota collection through the authenticated GitHub session without an external aggregator.
- Added provider prerequisite health checks and a truthful coverage model: quota, local analytics, authentication, or informational.

### Providers
- Replaced undocumented Cloudflare, Cohere, Fireworks, MiniMax, GLM, and AI21 quota claims with documented authentication checks or explicit informational states.
- Added Ollama `/api/ps` running-model status alongside `/api/tags`.
- Added upstream verification policy and source links in `docs/provider-verification.md`.

### UI and settings
- Added compact and comfortable dashboard density modes.
- Added provider filtering when more than eight cards are visible.
- Rebuilt settings around provider health, telemetry coverage, informational coverage, and plugin-managed diagnostics.
- Removed obsolete source mode and external-binary path controls.
- Redesigned the popout hero: animated circular progress gauge, status eyebrow with live pulse, badge row, and a stat band (active/attention/engine/last sync) replacing the metric tiles.
- Added status filter chips (All/Live/Issues) with counts above the provider list; the name filter now appears from six providers.
- Provider cards gained an animated expand/collapse, a usage ring around the provider icon, and a rotating chevron.
- Added an indeterminate loading bar at the top of the popout while fetching.
- Redesigned settings: gradient hero with icon tile, version pill, health summary chips, and a re-check health action; section headers with icons and dividers; provider chips animate on hover; selected providers show colored health status pills; diagnostics commands render in monospace.
- Provider cards sort by usage (highest first) with failed providers at the end.
- Claude daily bars show per-day tokens and cost on hover, with animated bar heights.
- Added expand-all/collapse-all toggle next to the provider list header.
- Bar pill entries gained a usage-colored status dot and percent, replacing flat text.
- Diagnostics commands gained a one-click copy button (wl-copy) with confirmation feedback.

### Features
- Desktop notifications when a provider crosses a configurable usage threshold (75/85/95%), de-duplicated per reset window.
- Claude 5h burn-rate forecast: warns "At this pace: 100% in Xm" when the window will be exhausted before reset.
- Claude projected month cost tile based on average daily spend; turns red when projecting 1.5× current spend.
- Usage history: the dispatcher records snapshots to `~/.cache/AiOverviewControl/usage-history.jsonl`; expanded cards render a sparkline via the new `get-usage-history` helper.
- Trend arrows on cards (up/down vs the previous snapshot).
- Pin providers (star) to keep them at the top of the list, persisted in settings.
- "Open console" button on expanded cards deep-links to each provider's usage page.
- Per-provider retry badge on failed cards re-fetches only that provider.
- New "top" pill mode shows only the most critical provider in the bar.
- Top Claude projects of the week (by real session `cwd`) with token bars, toggleable via the restored `showClaudeProjects` setting.

### Quality
- Updated CI for the new dispatcher contract, health schema, and a regression check preventing the removed dependency from returning.
- Rebuilt English, Brazilian Portuguese, and Simplified Chinese locale bundles with key parity.

### Fixes
- Claude analytics now bucket session timestamps by local day instead of UTC, fixing shifted daily bars and undercounted today cost/tokens in non-UTC timezones.
- Claude pricing now matches single-number model versions (e.g. `claude-fable-5`), which previously priced whole families at $0; pricing cache is invalidated via a schema marker.
- Claude quota falls back to the last good snapshot on transient API failures (429, 5xx, network) instead of erroring the card; auth failures still surface.
- Claude card shows 5h/7d reset countdowns and an "Extra usage on" badge.
- Provider health checks now recognize dispatcher aliases (`moonshot`, `zhipu`, `nim`, `vertex`, `ark`, `modelark`, `dashscope`, `alibaba`).
- Gemini API key moved from the URL query string to the `x-goog-api-key` header so it no longer leaks via process listings.
- DeepSeek balance fields are stringified defensively so numeric API responses cannot break JSON output.
- `MOONSHOT_API_BASE` override is now exclusive: no silent fallback to the China host when an explicit base is set.
- Messages without a timestamp are excluded from Claude weekly aggregation instead of being miscounted.
- Removed the unused USD→EUR exchange-rate fetch and dead `costCurrency`/`showClaudeProjects` settings references.

## 1.2.4 - 2026-05-26

### Dashboard — UX
- Added stale-data indicator per provider card: a warning badge appears when the last refresh is older than 2× the configured refresh interval.
- Added `updatedAt` timestamp footer on each expanded provider card, with a warning tint when data is stale.
- Stale state is detected via a lightweight 10 s tick timer (`staleClock`) so cards update reactively without polling every frame.
- Stale indicator also surfaces in the popout header detail line ("Stale since {time} · {source}").

### Claude Analytics
- Split the "Today" metric tile into two separate tiles: **Today tokens** and **Today cost**, so both figures are visible at a glance without truncation.
- Claude card grid now uses a 4-column layout at ≥ 760 px and a 2-column layout at 520–759 px (was: 1 or 3).

### Providers — New
- **Together AI** (`together`): `GET https://api.together.xyz/v1/credits` with `TOGETHER_API_KEY` — shows credit balance.
- **Groq** (`groq`): key validation via models endpoint; note-card directing to console.groq.com/usage (no public quota API).
- **Cohere** (`cohere`): `GET https://api.cohere.ai/v1/users/me` with `COHERE_API_KEY` — surfaces `trial_credits` balance.
- **Replicate** (`replicate`): `GET https://api.replicate.com/v1/account` with `REPLICATE_API_TOKEN` — confirms auth and surfaces username.
- **Fireworks AI** (`fireworks`): `GET https://api.fireworks.ai/v1/account/billing` with `FIREWORKS_API_KEY` — shows credit balance.
- **AI21** (`ai21`): `GET https://api.ai21.com/studio/v1/usage` with `AI21_API_KEY` — shows monthly tokens used/quota window.
- Added all 6 providers to `availableProviderOptions`, `providerName()`, `iconForProvider()`, `providerAccent()`, and `allProviders` in Settings.
- Added 6 new stub scripts (`get-together-usage`, `get-groq-usage`, `get-cohere-usage`, `get-replicate-usage`, `get-fireworks-usage`, `get-ai21-usage`).

### Quality
- Expanded `shellcheck` CI step to cover all `providers/get-*` scripts (previously only the 3 main helpers were checked).

## 1.2.3 - 2026-05-22

### Dashboard — UX
- Multi-provider pill: DankBar indicator now shows up to 3 provider accents when multiple providers are near their limit.
- UI layout fixes: resolved card overflow and misaligned progress bars in narrow popout widths.
- Pill settings: added pill display options (single/multi accent, label visibility) to the Settings panel.

### Providers — New
- **Warp** (`warp`): provider note-card.
- **Qwen / DashScope** (`qwen`): key validation via DashScope compatible-mode models endpoint; note-card (no public balance API).
- **Vertex AI** (`vertexai`): `gcloud auth print-access-token` check; note-card (no programmatic quota endpoint).
- Added all 3 providers to `availableProviderOptions`, `providerName()`, `iconForProvider()`, `providerAccent()`, and `allProviders` in Settings.

## 1.2.2 - 2026-05-20

### UI/UX
- Translated all user-visible widget strings to Portuguese (status titles, subtitles, metric labels, error messages, button labels, empty states).
- Day-of-week labels in Claude daily bars now use Portuguese abbreviations (Seg/Ter/Qua/Qui/Sex/Sáb/Dom).
- Provider count chip now pluralizes correctly ("1 exibido" vs "2 exibidos").
- "Refresh" button relabeled "Atualizar"; "CLI" button (detect binary) relabeled "Detectar" for clarity.
- "Provider control" section renamed "Gerenciar provedores"; "Add provider" button → "Adicionar".
- Metric tiles renamed: Active→Ativos, Attention→Atenção, Engine→Motor, Account→Conta, Credits→Créditos.
- Claude Code details section: Week→Semana, 5h window label unchanged, Today→Hoje, Month→Mês, "Models this week"→"Modelos esta semana".
- `pendingProviderId` default now binds to first entry of `availableProviderOptions` instead of hardcoded `"gemini"`.
- `removeProvider` fallback when list empties now uses first `availableProviderOptions` entry instead of hardcoded `"9router"`.
- Fixed dynamic path resolution in widget (`getPluginPath(pluginId)` with lowercase fallback) so scripts resolve correctly on case-sensitive filesystems regardless of install path.
- Redesigned Settings panel: interactive provider chips, live env-var reference table, collapsible sections, diagnostic commands, auth reference, source mode hints, and DankToggle for error visibility.

### Providers
- Fixed 9Router displaying as "OpenRouter" in the dashboard (`providerName()` mapping corrected to `"9router": "9Router"`).
- Gave 9Router a distinct icon (`"share"`) and accent color to visually separate it from OpenRouter.
- Added `fetch_openrouter_native` → 9Router local DB as silent fallback when `OPENROUTER_API_KEY` is unset.
- Added 12 new provider adapters in `get-provider-usage`:
  - **DeepSeek** — balance endpoint (`api.deepseek.com/user/balance`), CNY fields.
  - **Kimi (Moonshot)** — balance endpoint (`api.moonshot.cn/v1/users/me/balance`), CNY fields.
  - **MiniMax** — token-plan endpoint (`www.minimax.io/v1/token_plan/remains`).
  - **GLM / Zhipu AI** — quota endpoint (`bigmodel.cn/api/monitor/usage/quota/limit`); `GLM_API_BASE` override.
  - **Mistral** — key validation via models endpoint; note-card (no quota API).
  - **Ollama** — local `/api/tags` model list; `OLLAMA_HOST` override.
  - **NVIDIA NIM** — key validation via models endpoint; note-card (no quota API).
  - **Cloudflare AI** — neurons usage endpoint; requires `CLOUDFLARE_ACCOUNT_ID`.
  - **Vertex AI** — `gcloud` auth check; note-card (no quota API).
  - **BytePlus ModelArk** — key validation via models endpoint; note-card (no quota API).
  - **Qwen / DashScope / Alibaba** — key validation via models endpoint; note-card (no quota API).
- Added 12 new provider entries to `availableProviderOptions` in the QML widget.
- Added `providerName`, `iconForProvider`, and `providerAccent` mappings for all new providers.
- Rewrote `docs/providers.md` with full 25-provider matrix, auth methods, env vars, and test commands.
- Rewrote `docs/architecture.md` to document all fetch functions and updated data flow diagram.
- Rewrote `docs/configuration.md` with env var reference table and per-provider source recommendations.
- Rewrote `docs/troubleshooting.md` with per-provider debugging sections for all new providers.
- Rewrote `TODO.md` with organized categories and current state reflecting v1.2.x.

## 1.2.1 - 2026-05-08

- Added `9router`/OpenRouter-compatible provider handling in the dashboard and provider helper.
- Improved provider refresh behavior when provider selection changes.
- Polished provider cards, metric tiles, overview styling, hover states, and displayed provider counts.
- Fixed Claude daily totals to use the current weekday instead of a hard-coded weekday index.
- Fixed the plugin author metadata.
- Added external-helper timeout handling and safer shell interpolation in usage helpers.
- CI: restored `actions/checkout@v6.0.2` and `softprops/action-gh-release@v3.0.0` (versões corretas, não existentes antes de 2026).
- Release: corrigido `zip -r "$ZIP" -@` → `zip "$ZIP" -@` (flags `-r` e `-@` são mutuamente exclusivos).
- Release: substituídas duas etapas separadas `shogo82148/actions-upload-release-asset` pelo parâmetro `files:` nativo do `softprops/action-gh-release@v3.0.0`.
- Release: `release_name:` corrigido para `name:` (parâmetro correto da action).
- Release: adicionado `generate_release_notes: true` para notas automáticas a partir do histórico de commits.
- CI/Release: adicionados blocos `permissions` mínimos (`contents: read` e `contents: write`).

## 1.2.0 - 2026-04-30

- Added a local `get-provider-usage` backend so AiOverviewControl no longer depends on another DMS plugin for provider aggregation.
- Made the provider aggregator optional instead of a hard plugin requirement.
- Added native/fallback provider handling for Claude, Copilot, Gemini, and OpenRouter with structured per-provider errors.
- Improved dashboard responsiveness with adaptive cards, grids, provider controls, and long-text handling.
- Made **Show Provider Errors** actually filter provider cards when disabled.
- Updated settings copy to describe local helpers, fallback source mode, and optional fallback binary behavior.
- Reworked the user documentation in Portuguese with a shorter README and focused guides under `docs/`.
- Added practical installation, configuration, provider, troubleshooting, and architecture references.
- Clarified that the plugin is self-contained in `AiOverviewControl`.

## 1.1.3 - 2026-04-29

- Fixed Copilot on Linux by using the authenticated GitHub session directly.
- Added `get-copilot-usage`, which uses the authenticated GitHub session to read real Copilot subscription quota data.
- Mapped Copilot Premium, Chat, and Completions windows into the same provider-card data model used by the other providers.
- Updated provider-card labels so named quota windows such as Premium and Chat are shown consistently.

## 1.1.2 - 2026-04-29

- Normalized provider display logic so cards use the same current window, weekly window, account, login, credits, source, and error helpers.
- Fixed inconsistent current-vs-weekly percentage rendering in collapsed provider cards.
- Simplified aggregator error output so unsupported providers show the real provider error instead of raw JSON.
- Added a dashboard provider manager with an **Add provider** button.
- Added per-card remove controls and a custom provider list field in settings.

## 1.1.1 - 2026-04-29

- Increased dashboard scale from a compact utility panel to a larger floating control surface.
- Enlarged provider cards, icons, metric tiles, progress bars, and dashboard summary typography.
- Added collapsed-card progress previews so each provider card has useful status at rest.
- Tightened runtime guards for providers that return errors without usage data.
- Removed AiOverviewControl QML warnings caused by rendering account metrics for unsupported providers.

## 1.1.0 - 2026-04-29

- Reworked the popout into a larger provider dashboard.
- Added foldable provider cards with provider-specific accents.
- Integrated Claude Code usage analytics into AiOverviewControl.
- Added daily activity, model mix, token consumption, and Claude subscription limit details.
- Disabled the separate `claudeCodeUsage` widget locally.
- Added project documentation, changelog, and TODO tracking.

## 1.0.0 - 2026-04-29

- Created AiOverviewControl as a renamed and expanded AI usage widget.
- Added configurable provider sets and source modes.
- Added Linux-friendly `cli` default.
- Added partial provider failure handling.
