# Changelog

## [Unreleased]

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
- Added `codexbar` timeout handling and safer shell interpolation in usage helpers.
- CI: restored `actions/checkout@v6.0.2` and `softprops/action-gh-release@v3.0.0` (versões corretas, não existentes antes de 2026).
- Release: corrigido `zip -r "$ZIP" -@` → `zip "$ZIP" -@` (flags `-r` e `-@` são mutuamente exclusivos).
- Release: substituídas duas etapas separadas `shogo82148/actions-upload-release-asset` pelo parâmetro `files:` nativo do `softprops/action-gh-release@v3.0.0`.
- Release: `release_name:` corrigido para `name:` (parâmetro correto da action).
- Release: adicionado `generate_release_notes: true` para notas automáticas a partir do histórico de commits.
- CI/Release: adicionados blocos `permissions` mínimos (`contents: read` e `contents: write`).

## 1.2.0 - 2026-04-30

- Added a local `get-provider-usage` backend so AiOverviewControl no longer depends on another DMS plugin for provider aggregation.
- Made `codexbar` an optional executable fallback instead of a hard plugin requirement.
- Added native/fallback provider handling for Claude, Copilot, Gemini, and OpenRouter with structured per-provider errors.
- Improved dashboard responsiveness with adaptive cards, grids, provider controls, and long-text handling.
- Made **Show Provider Errors** actually filter provider cards when disabled.
- Updated settings copy to describe local helpers, fallback source mode, and optional fallback binary behavior.
- Reworked the user documentation in Portuguese with a shorter README and focused guides under `docs/`.
- Added practical installation, configuration, provider, troubleshooting, and architecture references.
- Clarified that the plugin is self-contained in `AiOverviewControl` and uses the `codexbar` executable only as a provider fallback, not as another DMS plugin.

## 1.1.3 - 2026-04-29

- Fixed Copilot on Linux by bypassing the unsupported CodexBar `copilot --source cli` path.
- Added `get-copilot-usage`, which uses the authenticated GitHub session to read real Copilot subscription quota data.
- Mapped Copilot Premium, Chat, and Completions windows into the same provider-card data model used by the other providers.
- Updated provider-card labels so named quota windows such as Premium and Chat are shown consistently.

## 1.1.2 - 2026-04-29

- Normalized provider display logic so cards use the same current window, weekly window, account, login, credits, source, and error helpers.
- Fixed inconsistent current-vs-weekly percentage rendering in collapsed provider cards.
- Simplified CodexBar error output so unsupported providers show the real provider error instead of raw JSON.
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

- Created AiOverviewControl as a renamed and expanded successor to the DMS CodexBar widget.
- Added configurable provider sets and source modes.
- Added Linux-friendly `cli` default.
- Added partial provider failure handling.
