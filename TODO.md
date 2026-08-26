# TODO

Roadmap and backlog for **AiOverviewControl**.

**Legend** — Effort: `S` (≤1h) · `M` (≤half-day) · `L` (multi-day).
Impact: `★` nice-to-have · `★★` solid win · `★★★` high value.
Open items are ordered quick-wins-first within each section. Completed items
stay one release cycle, then move to `CHANGELOG.md`.

---

## ⚡ Next up (prioritized)

The v1.6.0 audit is **closed**: every P0/P1 finding was verified fixed in the
current tree (Codex `rateLimitResetCredits`, dynamic versions from
`plugin.json`, Cloudflare `String!`, Together credits, dead `SectionFrame`,
Fireworks `/quotas`, AI21 auth probe, `pipefail` in `get-claude-usage`,
9Router cached tokens, `PillProgressRing` clamp, dispatch coverage as a CI
hard gate, and the docs rewrites). The report itself was never tracked by git
— it is `.gitignore`d — so nothing shipped with it and no carry-over remains.

- [ ] **Kimi Code `/usages` live schema verification** — the parser added in 1.8.0 handles two payload shapes from community sources (`Golden0Voyager/kimi-code-usage`), not an official spec. Validate against a real `sk-kimi-` key, pin the actual field names, and trim the defensive dual-shape jq once the live shape is confirmed. **Blocked:** needs a paid Kimi Code subscription key. `M · ★★★`
- [ ] **Simultaneous Kimi cards** — key-routing means a user with BOTH an Open Platform `sk-xxx` balance key and a Kimi Code `sk-kimi-` subscription key sees only one. Emit two cards (balance + coding) when both creds exist. **Blocked** on the same missing credentials. `M · ★★`
- [ ] **Notification click action** — open the popout focused on the offending provider (`focusedProviderId` already exists). **Blocked on a design decision:** `notify-send` only reports an invoked action from a process that stays alive for the notification's lifetime, so the fire-and-forget `send-quota-alert` would have to keep one background process per armed alert, or be rewritten onto `gdbus` `Notify` + an `ActionInvoked` monitor. Routing the click back into the right widget instance also needs an IPC target that multi-monitor bars can share without duplicate `IpcHandler` registrations. `L · ★★★`
- [x] ~~**Multi-window quota notifications**~~ — done: `notifyWindowScope` (`displayed` / `all` / `primary`), `checkNotifications()` iterates `notifyWindowsFor()`.
- [x] ~~**DankBar pill tooltip**~~ — done: hovering the pill reads "Claude · 7 day · 31% · resets in 2d", gated by the `pillTooltip` setting.
- [x] ~~**Icon reconciliation** (audit 2.16)~~ — done in 1.8.1: `ProviderLogo.defaultIcon` is the single source; widget `iconForProvider()` and settings `fallbackIcon` overrides removed.
- [x] ~~**Finish UI i18n**~~ — done in 1.8.1: `"5h"` (2.9), pill `ERR`/`N/A` (2.11) localized; 3 dead keys removed (2.20). Non-issues: `notify.body` is live (not dead); the `String.replace` `$`-bug (2.19) is already avoided via function-replacement `() => value`. **Skipped (WONTFIX):** `formatTier()` names (2.10) — `Max 20x`/`Pro`/`Free` are brand plan names, not UI chrome.
- [ ] **QML smoke test** — headless instantiate the three QML files with stub data to catch binding-loop / undefined-property regressions before a tag ships. Highest-leverage safety net for third-party distribution. Needs a Quickshell runtime with the `qs.*` modules in CI, which is why Qt5 `qmllint` is still the hard gate. `L · ★★`

## Dashboard — UX

- [ ] **Drag-to-reorder pinned providers** in the dashboard (beyond star pin). `L · ★`

## Providers — Data & Auth

- [ ] **NVIDIA** — surface quota-window info if NIM adds a balance endpoint (monitor changelog). `M · ★★`
- [ ] **Mistral** — surface `is_default_key` flag and rate-limit headers when a quota endpoint exists. `M · ★★`
- [ ] **BytePlus/Ark** — surface `remaining_tokens` per model when the API exposes per-model quotas. `M · ★★`
- [ ] **Codex** — record credit-balance history alongside rate-limit snapshots. `M · ★★`
- [ ] **Hermes** — surface real quota/spend for the provider half if [Nous Portal](https://portal.nousresearch.com) publishes a read-only usage endpoint; today only the local agent half (`~/.hermes/state.db`) is measurable. `M · ★★`
- [ ] **Hermes** — resolve per-model pricing so the telemetry card can chart cost instead of tokens (`estimated_cost_usd` is frequently `0` because Hermes prices upstream). `M · ★`

## Telemetry & History

- [x] ~~**History export**~~ — done: `providers/export-usage-history csv|jsonl` plus CSV/JSONL buttons in Settings.
- [ ] **History retention trim feedback** — the trim is silent; Settings could report how many snapshots the store currently holds next to the retention dropdown. `S · ★`

## Claude Analytics

- [ ] **Cost currency option** — USD-only today; reintroduce currency conversion only with a real `costCurrency` setting wired end to end (the old Frankfurter EUR lookup was removed as dead code). `M · ★`

## Settings

- [x] ~~**Threshold validation/feedback**~~ — done: `notifyThresholdIssues()` flags malformed pairs, unknown/duplicate/untracked providers, and out-of-range percentages while typing.
- [x] ~~**Reset-to-defaults**~~ — done: two-step confirm restores every key in `settingDefaults`; `settingsEpoch` forces the controls to re-read.

## Quality / CI

- [x] ~~**Flow/anchor lint**~~ — done in 1.12.0: CI gate fails any direct child of `Flow` that sets `anchors.*` (verified to catch the Hermes regression).

## Packaging / Marketplace

- [ ] **Plugin marketplace metadata** — add when the DMS plugin registry format is finalized. `M · ★★`
- [x] ~~**Install/update docs for tagged releases**~~ — done: `docs/installation.md` documents the full release zip/sha256 download, checksum verification, and upgrade flow.

---

Historical shipped notes for v1.4.x and v1.5.0 were folded into
`CHANGELOG.md` (see its entries; note v1.5.0 was never released as such — its
content shipped in 1.6.0).

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
