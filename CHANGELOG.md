# Changelog

## [Unreleased]

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
