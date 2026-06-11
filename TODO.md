# TODO

Roadmap and backlog for AiOverviewControl. Completed items stay listed for one
release cycle, then move to `CHANGELOG.md` history.

## Providers — Data & Auth

- [ ] NVIDIA: surface specific quota window info if NVIDIA adds a balance endpoint (monitor NIM changelog).
- [ ] Mistral: surface `is_default_key` flag and rate-limit headers when Mistral adds a quota endpoint.
- [ ] BytePlus/Ark: surface `remaining_tokens` per model when the API exposes per-model quotas.
- [ ] Codex: record credit balance history alongside rate-limit snapshots.
- [x] Cloudflare: Workers AI analytics via the documented GraphQL `aiInferenceAdaptiveGroups` dataset (7-day requests/neurons + latest day) when `CLOUDFLARE_ACCOUNT_ID` is set; graceful fallback to the token-verified note.
- [x] OpenRouter: top-models breakdown (30d, via `/api/v1/activity`) in the tertiary window, falling back to monthly spend.
- [x] Remove the global source mode; every provider now owns one explicit adapter path.
- [x] MiniMax/GLM: replace undocumented quota calls with configured-status reporting.
- [x] Ollama: poll `/api/ps` for running-model status and supplement `/api/tags`.
- [x] Qwen/DashScope: optional `DASHSCOPE_WORKSPACE_ID` request scoping.
- [x] Vertex AI: `GOOGLE_CLOUD_PROJECT` labeling alongside the `gcloud` auth check.
- [x] Copilot: prerequisite health plus the authenticated GitHub-session quota adapter.
- [x] Gemini: API key sent via `x-goog-api-key` header instead of the query string.
- [x] Kimi: `MOONSHOT_API_BASE` override is exclusive (no silent `.cn` fallback).
- [x] Health checks recognize dispatcher aliases (`moonshot`, `zhipu`, `nim`, `vertex`, `ark`, `modelark`, `dashscope`, `alibaba`).

## Telemetry & History

- [x] Configurable history retention (`historyRetention` setting → `AIOC_HISTORY_MAX` env on the dispatcher).
- [x] Per-provider notification thresholds (`notifyThresholds` CSV overrides, e.g. `claude:90,codex:75`).
- [x] Snapshot timestamps in the sparkline payload with hover values (percent · time).
- [x] Burn-rate forecast for the Claude 7-day window (shown only when on track to exhaust).
- [x] Usage history: dispatcher records snapshots to `~/.cache/AiOverviewControl/usage-history.jsonl`; `get-usage-history` aggregates per provider.
- [x] Sparklines and trend arrows on provider cards.
- [x] Desktop notifications when a provider crosses a configurable threshold (75/85/95%), de-duplicated per reset window.

## Dashboard — UX

- [ ] Notification click action: open the popout on the offending provider.
- [x] Keyboard navigation for provider cards: Tab focus, Enter/Space expand, Delete remove, P pin, R retry; focus ring and accessible name/description.
- [ ] Add screenshot assets for documentation and marketplace listing.
- [x] Compact/comfortable density modes.
- [x] Stale-data indicator per card (2× refresh interval) and `updatedAt` footer.
- [x] Status filter chips (All/Live/Issues) and name filter from six providers.
- [x] Usage-sorted card list with pinned providers first and failures last.
- [x] Pin providers (star), persisted in `pinnedProviders`.
- [x] Per-provider retry badge on failed cards.
- [x] "Open console" deep links on expanded cards.
- [x] Expand-all/collapse-all toggle; animated expand/collapse with rotating chevron.
- [x] Hero with animated progress ring, status eyebrow, and stat band.
- [x] Indeterminate loading bar while fetching.
- [x] "top" pill mode (most critical provider only) plus usage-colored pill dots.

## Claude Analytics

- [ ] Cost currency display option (USD-only today; the old Frankfurter EUR lookup was removed as dead code — reintroduce only with a real `costCurrency` setting end to end).
- [x] Per-model cost split (`WEEK_MODEL_COSTS`): model bars show tokens · cost.
- [x] Today's tokens and today's cost as separate tiles.
- [x] Local-day bucketing for daily bars and costs (UTC mismatch fixed).
- [x] Pricing matches single-number model versions (e.g. `claude-fable-5`); cache invalidated via schema marker.
- [x] Stale-cache fallback on transient OAuth API failures (429/5xx/network).
- [x] 5h burn-rate forecast and projected month cost tile.
- [x] 5h/7d reset countdowns and "Extra usage on" badge.
- [x] Top 5 projects of the week by real session `cwd`, toggleable via `showClaudeProjects`.
- [x] Per-day tokens/cost on daily-bar hover.

## Settings

- [x] Visual editor for pinned providers: star action on each selected-provider row.
- [x] Per-provider notification threshold overrides field.
- [x] Manual custom provider list text field.
- [x] Per-provider prerequisite health rows with status pills.
- [x] Quota notification toggle and threshold dropdown.
- [x] `showClaudeProjects` toggle.
- [x] Health summary chips (active/ready/missing) and re-check action in the hero.
- [x] Copy button on diagnostics commands (wl-copy).

## Quality

- [x] Integration test for `get-usage-history` (empty case, sort/group aggregation, dispatcher snapshot append).
- [x] i18n: Spanish (es_ES) and German (de_DE) bundles with full key parity, wired into locale detection, settings, and CI/release parity checks.
- [x] `shellcheck` in CI for all `get-*` scripts.
- [x] Smoke tests for `get-claude-usage` (KEY=VALUE) and `get-provider-usage` (JSON array, stub delegation).
- [x] GitHub Actions pinned to SHAs.
- [x] i18n key-parity check in the release workflow.

## Packaging

- [x] Release checklist in `docs/release-checklist.md` (version bump points, validation, tag flow, post-release).
- [ ] Add plugin marketplace metadata when DMS plugin registry format is finalized.
- [ ] Add `assets/` directory with widget screenshots for README and marketplace.
- [x] Release workflow validates tag/version/changelog/i18n and publishes zip/tar.gz/sha256 artifacts (v1.3.0 shipped).
