# TODO

Roadmap and backlog for **AiOverviewControl**.

**Legend** — Effort: `S` (≤1h) · `M` (≤half-day) · `L` (multi-day).
Impact: `★` nice-to-have · `★★` solid win · `★★★` high value.
Open items are ordered quick-wins-first within each section. Completed items
stay one release cycle, then move to `CHANGELOG.md`.

---

## ⚡ Quick wins / cleanup (do next)

_(Cleared in v1.4.8 — see Recently shipped below.)_

## Dashboard — UX

- [ ] **Notification click action** — open the popout focused on the offending provider. `M · ★★★`
- [ ] **Drag-to-reorder pinned providers** in the dashboard (beyond star pin). `L · ★`

## Providers — Data & Auth

- [ ] **NVIDIA** — surface quota-window info if NIM adds a balance endpoint (monitor changelog). `M · ★★`
- [ ] **Mistral** — surface `is_default_key` flag and rate-limit headers when a quota endpoint exists. `M · ★★`
- [ ] **BytePlus/Ark** — surface `remaining_tokens` per model when the API exposes per-model quotas. `M · ★★`
- [ ] **Codex** — record credit-balance history alongside rate-limit snapshots. `M · ★★`

## Telemetry & History

- [ ] **History export** — button to dump `usage-history.jsonl` (or CSV) from Settings. `S · ★`

## Claude Analytics

- [ ] **Cost currency option** — USD-only today; reintroduce currency conversion only with a real `costCurrency` setting wired end to end (the old Frankfurter EUR lookup was removed as dead code). `M · ★`

## Settings

- [ ] **Threshold validation/feedback** — validate the per-provider `notifyThresholds` CSV inline and show parse errors. `S · ★★`
- [ ] **Reset-to-defaults** action for plugin settings. `S · ★`

## Quality / CI

- [ ] **QML smoke test** — headless instantiate of the three QML files with stub data to catch binding-loop / undefined-property regressions. `L · ★★`

## Packaging / Marketplace

- [ ] **Plugin marketplace metadata** — add when the DMS plugin registry format is finalized. `M · ★★`
- [ ] **Install/update docs for tagged releases** — point users at the release zip/sha256 flow. `S · ★`

---

## ✅ Recently shipped — v1.4.12 (2026-06-26)

- **Provider tracking audit** — fixed Z.ai/GLM weekly-vs-daily unit decoding, GLM `ZAI_API_KEY` fallback, OpenRouter→9Router local fallback labeling, Codex subscription-credit display, stable two-decimal currency formatting, quota-only history snapshots, and quota-only fleet average load.

## ✅ Recently shipped — v1.4.11 (2026-06-24)

- **Navigable hero overview** — click the fleet rollup's peak provider or the hero usage bars to expand + scroll to that provider's card (`focusProvider(id)`). Folds in the "make hero window bars interactive" item.

## ✅ Recently shipped — v1.4.10 (2026-06-24)

- **QML lint hard gate** — CI installs Qt5 `qmllint` and runs it as a required step (syntax verification, no `qs.*` import noise). New `CONTRIBUTING.md` documents the `modelData`/singleton-freeze gotchas (folds in the "guard modelData gotcha" item via the contributor note).
- **Guided hero empty/error state** — contextual hint (loading / all-errored / no-data) fills the hero's window-bar slot instead of leaving it blank.

## ✅ Recently shipped — v1.4.9 (2026-06-24)

- **Aggregate cross-provider view** — hero fleet overview (avg load ring, peak provider, at-risk count ≥80%, soonest reset) shown when ≥2 providers resolve. Summarizes quota pressure in comparable % units instead of faking a cross-provider monetary total.

## ✅ Recently shipped — v1.4.8 (2026-06-24)

Quick-win cleanup pass:
- Removed dead `barText` + `providerEngineLabel` properties (orphaned by the v1.4.5 hero rework).
- Fixed i18n keys: dropped orphan `card.engine`, added missing `card.resets_in` across all 5 bundles (parity preserved).
- Rounded the `MetricTile` left accent bar (contained indicator, no corner bleed).
- Silenced dispatch-coverage CI noise: parser now handles dotted aliases (`z.ai`) and canonical-vs-alias distinction; reports 0 missing.

Dropped: "Refresh screenshots" quick-win (descoped).

## ✅ Recently shipped — v1.4.5 (2026-06-19)

UI polish pass (see `CHANGELOG.md` for detail):
- Popout scrollbar gutter (no content overlap).
- Inactive provider cards recede; active/hover/expanded stands out.
- Left accent stripe → contained rounded active indicator.
- Account/Login/Credits boxes → inline `InfoPill`s.
- Hero ring → per-window usage bars (label · value · reset); labels prefer `resetDescription`.

## ✅ Done (earlier releases)

<details><summary>Providers — Data &amp; Auth</summary>

- [x] Cloudflare Workers AI analytics via GraphQL `aiInferenceAdaptiveGroups` (7-day, with token-verified fallback).
- [x] OpenRouter top-models breakdown (30d via `/api/v1/activity`).
- [x] Removed global source mode; every provider owns one explicit adapter path.
- [x] MiniMax/GLM configured-status reporting (replaced undocumented quota calls).
- [x] Ollama `/api/ps` running-model status + `/api/tags`.
- [x] Qwen/DashScope optional `DASHSCOPE_WORKSPACE_ID` scoping.
- [x] Vertex AI `GOOGLE_CLOUD_PROJECT` labeling + `gcloud` auth check.
- [x] Copilot prerequisite health + authenticated GitHub-session quota adapter.
- [x] Gemini key via `x-goog-api-key` header (not query string).
- [x] Kimi exclusive `MOONSHOT_API_BASE` override (no silent `.cn` fallback).
- [x] Health checks recognize dispatcher aliases.

</details>

<details><summary>Telemetry &amp; History</summary>

- [x] Configurable history retention (`historyRetention` → `AIOC_HISTORY_MAX`).
- [x] Per-provider notification thresholds (`notifyThresholds` CSV).
- [x] Snapshot timestamps in sparkline payload with hover values.
- [x] Burn-rate forecast for the Claude 7-day window.
- [x] Usage history JSONL + `get-usage-history` aggregation.
- [x] Sparklines and trend arrows on cards.
- [x] Desktop notifications on threshold crossing, de-duplicated per reset window.

</details>

<details><summary>Dashboard — UX</summary>

- [x] Keyboard navigation (Tab/Enter/Space/Delete/P/R) with focus ring + a11y names.
- [x] Compact/comfortable density modes.
- [x] Stale-data indicator per card + `updatedAt` footer.
- [x] Status filter chips (All/Live/Issues) + name filter.
- [x] Usage-sorted list (pinned first, failures last).
- [x] Pin providers (persisted) + per-card retry badge.
- [x] "Open console" deep links; expand-all/collapse-all; animated chevron.
- [x] Hero status eyebrow + stat band; indeterminate loading bar.
- [x] "top" pill mode + usage-colored pill dots.

</details>

<details><summary>Claude Analytics</summary>

- [x] Per-model cost split (`WEEK_MODEL_COSTS`).
- [x] Today's tokens/cost tiles; local-day bucketing.
- [x] Pricing matches single-number model versions; cache schema marker.
- [x] Stale-cache fallback on transient OAuth failures.
- [x] 5h burn-rate forecast + projected-month tile; reset countdowns + extra-usage badge.
- [x] Top 5 weekly projects by session `cwd` (`showClaudeProjects`).
- [x] Per-day tokens/cost on daily-bar hover.

</details>

<details><summary>Settings / Quality / Packaging</summary>

- [x] Visual pin editor; threshold-override field; custom provider list; prerequisite health rows.
- [x] Quota notification toggle + threshold dropdown; `showClaudeProjects` toggle; health summary chips; copy-diagnostics button.
- [x] Integration test for `get-usage-history`; smoke tests for claude/provider scripts.
- [x] es_ES + de_DE bundles with parity, wired into CI/release checks.
- [x] `shellcheck` in CI; Actions pinned to SHAs; i18n parity in release workflow.
- [x] Release checklist (`docs/release-checklist.md`); release workflow publishes zip/tar.gz/sha256.

</details>
