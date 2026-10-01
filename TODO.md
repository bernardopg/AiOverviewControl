# TODO

Roadmap and backlog for **AiOverviewControl**.

**Legend** — Effort: `S` (≤1h) · `M` (≤half-day) · `L` (multi-day).
Impact: `★` nice-to-have · `★★` solid win · `★★★` high value.
Open items are ordered quick-wins-first within each section. Completed items
stay one release cycle, then move to `CHANGELOG.md`.

---

## 🔧 Registry review remediation (AvengeMedia/dms-plugin-registry#358)

Automated Claude review on `6d37548` flagged 6 issues, all verified legitimate.
Code shipped in 1.17.2/1.17.3; the registry PR (AvengeMedia/dms-plugin-registry#961) awaits merge.

- [x] **Move Claude caches out of `~/.claude`** — `pricing-cache.json` and
  `usage-cache.json` relocate to `${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl/`
  with one-time migration of stale files. `stats-cache.json` stays read-only
  from `~/.claude` (Claude Code's own file). `S · ★★★`
- [x] **Incremental transcript analytics** — per-transcript extraction cache
  (`claude-transcripts.tsv`, keyed by size + mtime) re-parses only changed
  files, so an active Claude Code session no longer forces a full rescan;
  `claude --version` gets a daily TTL cache. Shipped in 1.17.2 as a
  whole-tree fingerprint, made per-file in 1.17.3. `M · ★★★`
- [x] **Document + opt-out third-party calls** — LiteLLM pricing fetch
  (`AIOC_NO_LITELLM=1`) and Copilot dns.google DoH fallback
  (`AIOC_NO_DOH_FALLBACK=1`) documented in README/docs with env opt-outs.
  `S · ★★`
- [x] **Antigravity transparency** — docs state plainly: reads Google refresh
  tokens from IDE `state.vscdb`, exchanges via public embedded OAuth client
  credentials, calls internal Cloud Code endpoints with the IDE User-Agent;
  provider is opt-in. `S · ★★`
- [x] **Registry entry PR** — update `plugins/bernardopg-aioverviewcontrol.json`
  description (~40 providers) and dependencies (sqlite3, notify-send, flock,
  secret-tool as optional). `S · ★★`
- [x] **heroGlow infinite animation** — bind `running` to popout visibility
  via injected `parentPopout.shouldBeVisible`. `S · ★★`

- [ ] **Registry PR follow-up** — track AvengeMedia/dms-plugin-registry#961
  until the maintainers merge it, then close this section. `S · ★★`

## 🧭 Roadmap after 1.18.0 (recommended order)

The 1.18.0 plan (Codex labels i18n, QML smoke test, god-file split) shipped,
as did the compact pill (#34), the transcript-parse measurement, the native
DMS UI CI gate, the notification click action and Hermes per-model pricing.

1. Upstream-blocked items (NVIDIA, Mistral, BytePlus, Hermes portal,
   marketplace metadata): check monthly, no active work.

## ⚡ Next up (prioritized)

The v1.6.0 audit is **closed**: every P0/P1 finding was verified fixed in the
current tree (Codex `rateLimitResetCredits`, dynamic versions from
`plugin.json`, Cloudflare `String!`, Together credits, dead `SectionFrame`,
Fireworks `/quotas`, AI21 auth probe, `pipefail` in `get-claude-usage`,
9Router cached tokens, `PillProgressRing` clamp, dispatch coverage as a CI
hard gate, and the docs rewrites). The report itself was never tracked by git
— it is `.gitignore`d — so nothing shipped with it and no carry-over remains.

- [x] **Kimi Code `/usages` live schema verification** — the parser added in 1.8.0 handles two payload shapes from community sources (`Golden0Voyager/kimi-code-usage`), not an official spec. Validate against a real `sk-kimi-` key, pin the actual field names, and trim the defensive dual-shape jq once the live shape is confirmed. **Verified 2026-09-29:** system `KIMI_CODING_API_KEY` returned HTTP 200 on the first-party `.com` endpoint. Sanitized live fixture pins detailed-limit precedence; legacy shapes remain supported. See `docs/kimi-domains-research.md`. `M · ★★★`
- [x] **Simultaneous Kimi cards** — key-routing means a user with BOTH an Open Platform `sk-xxx` balance key and a Kimi Code `sk-kimi-` subscription key sees only one. Emit two cards (balance + coding) when both creds exist. Implemented independent `kimi` and `kimi-code` cards when both credentials exist, explicit Code selection and deduplication tests. Code was live-verified; dual-key behavior is fixture-tested. `M · ★★`
- [x] **Notification click action** — clicking an alert (or its **Open dashboard** action) opens the popout on the offending provider. Chose the `notify-send -A` waiter over a `gdbus` `ActionInvoked` monitor: the DMS daemon delivers the action to the waiter that owns the notification, there is no shared monitor to elect across bars, and each waiter is killed when its alert is replaced and exits when the notification closes. The click reuses the existing `aiOverviewControl` IPC target via the new `focus <provider>` function, so multi-monitor routing matches `toggle`. Covered by `tests/test-quota-alert.sh` and the native UI suite. `L · ★★★`
- [x] ~~**Multi-window quota notifications**~~ — done: `notifyWindowScope` (`displayed` / `all` / `primary`), `checkNotifications()` iterates `notifyWindowsFor()`.
- [x] ~~**DankBar pill tooltip**~~ — done: hovering the pill reads "Claude · 7 day · 31% · resets in 2d", gated by the `pillTooltip` setting.
- [x] ~~**Icon reconciliation** (audit 2.16)~~ — done in 1.8.1: `ProviderLogo.defaultIcon` is the single source; widget `iconForProvider()` and settings `fallbackIcon` overrides removed.
- [x] ~~**Finish UI i18n**~~ — done in 1.8.1: `"5h"` (2.9), pill `ERR`/`N/A` (2.11) localized; 3 dead keys removed (2.20). Non-issues: `notify.body` is live (not dead); the `String.replace` `$`-bug (2.19) is already avoided via function-replacement `() => value`. **Skipped (WONTFIX):** `formatTier()` names (2.10) — `Max 20x`/`Pro`/`Free` are brand plan names, not UI chrome.
- [x] **Codex window labels i18n** — `get-codex-usage` still emits raw "Session"/"Weekly" through `resetDescription`, which the widget shows untranslated. Emit only `windowMinutes` (like the kimi-code adapter) so `getWindowLabel()` localizes it; add a fixture assertion. `S · ★★★`
- [x] **QML smoke test** — Mandatory offscreen CI suites cover reader and currency lifecycles. Full real-DMS widget/pills/dashboard/settings/window construction and reactive BRL→USD bindings run in `tests/test-widget-runtime.sh`, with isolated fixture data and no visible windows. Passed locally; explicitly SKIPs when Wayland/DMS imports are absent. See `docs/development-gates.md` and `docs/refactoring.md`. `L · ★★`
- [x] **Native DMS UI smoke in generic CI** — the `qml-runtime` job checks out DankMaterialShell at a pinned tag, builds imports with `scripts/qmlls-setup`, starts headless sway and runs `tests/test-widget-runtime.sh` (pointer pass included) with `AIOC_REQUIRE_NATIVE_UI=1`, so a missing prerequisite fails instead of skipping. `M · ★★`

## Dashboard — UX

- [x] **Drag-to-reorder pinned providers** — Immediate ↕ handle drag inserts before another pinned card, persists ordering and cannot be stolen by page scrolling. Native QtTest pointer regression verifies fast drag and unchanged scroll position; header/logo/action alignment is covered. Other touch/monitor configurations remain manual. `L · ★`

## Providers — Data & Auth

- [ ] **NVIDIA** — surface quota-window info if NIM adds a balance endpoint (monitor changelog). `M · ★★`
- [ ] **Mistral** — surface `is_default_key` flag and rate-limit headers when a quota endpoint exists. `M · ★★`
- [ ] **BytePlus/Ark** — surface `remaining_tokens` per model when the API exposes per-model quotas. `M · ★★`
- [x] **Codex** — record credit-balance history alongside rate-limit snapshots. Reset-credit balances (zero included), serialized writer, CSV/JSONL exports and fixture tests are implemented; individual quota limits are not mistaken for balances. `M · ★★`
- [ ] **Hermes** — surface real quota/spend for the provider half if [Nous Portal](https://portal.nousresearch.com) publishes a read-only usage endpoint; today only the local agent half (`~/.hermes/state.db`) is measurable. `M · ★★`
- [x] **Hermes** — per-model pricing: rows with an unresolved cost are priced from a daily trimmed LiteLLM table (`litellm-prices.json`); included rows stay free, ledger costs are kept, and an unpriced model leaves totals unknown. The 7-day chart plots cost when every day is priced and some of it is paid. `M · ★`

## Telemetry & History

- [x] ~~**History export**~~ — done: `providers/export-usage-history csv|jsonl` plus CSV/JSONL buttons in Settings.
- [x] **History retention trim feedback** — Settings now displays snapshot count and last-trim removal count; writer/status tests cover the contract. — the trim is silent; Settings could report how many snapshots the store currently holds next to the retention dropdown. `S · ★`

## Claude Analytics

- [x] **Incremental transcript parse** — the per-file cache (1.17.3) re-parses a changed transcript in full (`ponytail:` note in `get-claude-usage`). Parse only from the previous byte size if long active sessions ever make refreshes slow; measure first. **WONTFIX (measured 2026-09-30):** 805 transcripts / 288 MB; warm refresh 0.26 s, refresh after the 20 MB active transcript changed 0.43 s. Revisit only if a changed-file refresh passes ~2 s. `M · ★`
- [x] **Cost currency option** — `costCurrency` is wired through Settings/reset, all common USD analytics cost displays, daily reference-rate cache, locale precision and explicit USD fallback. Nine currencies; stored amounts and provider balances are unchanged. Cache/concurrency and offscreen/native DMS binding tests pass. See `docs/currency.md`. `M · ★`

## Settings

- [x] ~~**Threshold validation/feedback**~~ — done: `notifyThresholdIssues()` flags malformed pairs, unknown/duplicate/untracked providers, and out-of-range percentages while typing.
- [x] ~~**Reset-to-defaults**~~ — done: two-step confirm restores every key in `settingDefaults`; `settingsEpoch` forces the controls to re-read.

## Quality / CI

- [x] **Split the god files** — Native provider implementations moved into 31 source modules (33 fetchers); dispatcher reduced to about 1,200 lines. Hero/cards/manager and 13 visual components moved into `DashboardContent.qml`; widget controller reduced to about 2,450 lines. Five analytics readers share bounded process lifecycle; currency display is an independent module. Existing contracts, complete local DMS UI construction, offscreen suites and provider fixtures pass. See `docs/refactoring.md`. `L · ★★★`
- [x] **Pre-push hook mirroring CI metadata gates** — the first 1.17.2 push failed CI (missing CHANGELOG entry, non-executable tests). Reuse the `ci.yml` checks locally: plugin.json semver, `## <version>` in CHANGELOG, i18n key parity, executable `tests/*.sh` and `providers/get-*`, every `tests/test-*.sh` listed in `ci.yml`. `S · ★★`
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
- [x] Release checklist (`docs/release-checklist.md`); release workflow publishes zip/tar.gz/sha256 with validated exact-version notes. Dedicated PR changelog integrity and main/tag rulesets prevent empty-note delivery and mutable release tags.

</details>
