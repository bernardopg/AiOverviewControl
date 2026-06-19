# TODO

Roadmap and backlog for **AiOverviewControl**.

**Legend** — Effort: `S` (≤1h) · `M` (≤half-day) · `L` (multi-day).
Impact: `★` nice-to-have · `★★` solid win · `★★★` high value.
Open items are ordered quick-wins-first within each section. Completed items
stay one release cycle, then move to `CHANGELOG.md`.

---

## ⚡ Quick wins / cleanup (do next)

- [ ] **Remove dead code from the v1.4.5 hero rework** — `barText` (line ~395) and `providerEngineLabel` (line ~412) properties are now unreferenced after the ring → window-bars + Engine → Resets changes. `S · ★` — shrinks the file, removes confusion.
- [ ] **Fix orphan/missing i18n keys** — `card.engine` is now unused but still present in all 5 bundles; `card.resets_in` is used in QML but missing from every bundle (renders the English fallback). Drop `card.engine`, add `card.resets_in` + `card.used` + the `window.*` labels across `en/pt_BR/zh_CN/es_ES/de_DE` (parity is CI-gated). `S · ★★` — correct localization, no orphan keys.
- [ ] **Refresh screenshots** — `screenshot.png` and `docs/assets/*` predate the v1.4.5 UI (inline identity pills, per-window hero bars, contained active indicator). `S · ★★` — README/marketplace accuracy. (Folds in the two long-standing "add screenshot assets" items below.)
- [ ] **Round the `MetricTile` left bar** — it still uses a sharp full-height rectangle (line ~1642) with the same rectangular-clip corner bleed the provider-card stripe had before v1.4.5; apply the contained rounded-indicator treatment. `S · ★`
- [ ] **Silence dispatch-coverage CI noise** — `get-provider-usage` reports `zai` stub with no dispatch case + alias-only cases (`grok`, `moonshot`, `vertex`, …). Add the missing `zai` case (or document the alias mapping the coverage script understands). `S · ★`

## Dashboard — UX

- [ ] **Notification click action** — open the popout focused on the offending provider. `M · ★★★`
- [ ] **Make hero window bars interactive** — click a window bar to expand/scroll to that provider's card. `M · ★★`
- [ ] **Real empty/error state for the hero** — when no providers resolve, the window-bar column is hidden but the hero is bare; show a guided empty state (mirror the existing providers-empty card). `S · ★★`
- [ ] **Drag-to-reorder pinned providers** in the dashboard (beyond star pin). `L · ★`

## Providers — Data & Auth

- [ ] **NVIDIA** — surface quota-window info if NIM adds a balance endpoint (monitor changelog). `M · ★★`
- [ ] **Mistral** — surface `is_default_key` flag and rate-limit headers when a quota endpoint exists. `M · ★★`
- [ ] **BytePlus/Ark** — surface `remaining_tokens` per model when the API exposes per-model quotas. `M · ★★`
- [ ] **Codex** — record credit-balance history alongside rate-limit snapshots. `M · ★★`

## Telemetry & History

- [ ] **Aggregate cross-provider view** — a combined "total spend / total quota" rollup window in the hero (today it shows a single focused provider). `M · ★★★`
- [ ] **History export** — button to dump `usage-history.jsonl` (or CSV) from Settings. `S · ★`

## Claude Analytics

- [ ] **Cost currency option** — USD-only today; reintroduce currency conversion only with a real `costCurrency` setting wired end to end (the old Frankfurter EUR lookup was removed as dead code). `M · ★`

## Settings

- [ ] **Threshold validation/feedback** — validate the per-provider `notifyThresholds` CSV inline and show parse errors. `S · ★★`
- [ ] **Reset-to-defaults** action for plugin settings. `S · ★`

## Quality / CI

- [ ] **Make QML lint a hard gate** — install `qt6-declarative-dev` in the `qml` CI job so `qmllint` actually runs (currently skipped on ubuntu-latest). Would catch syntax regressions; pair with a documented filter for the unavoidable `qs.*` import-resolution warnings. `M · ★★★`
- [ ] **Guard the `modelData` gotcha** — a custom Repeater delegate without `required property var modelData` silently renders blank (cost us the v1.4.5 hero bars). Add a grep/lint check, or a short CONTRIBUTING note. `S · ★★`
- [ ] **QML smoke test** — headless instantiate of the three QML files with stub data to catch binding-loop / undefined-property regressions. `L · ★★`

## Packaging / Marketplace

- [ ] **Plugin marketplace metadata** — add when the DMS plugin registry format is finalized. `M · ★★`
- [ ] **Install/update docs for tagged releases** — point users at the release zip/sha256 flow. `S · ★`

---

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
