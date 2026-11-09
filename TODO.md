# TODO

Roadmap and backlog for **AiOverviewControl**. The direction and the
non-goals are in [docs/roadmap.md](docs/roadmap.md).

**Legend** — Effort: `S` (≤1h) · `M` (≤half-day) · `L` (multi-day).
Impact: `★` nice-to-have · `★★` solid win · `★★★` high value.
**Status:** `[ ]` not started · `[~]` partial / in progress · `[x]` done.
Open items are ordered quick-wins-first within each section. Completed items
stay one release cycle, then move to `CHANGELOG.md`.

---

## 🚀 Next release

- [ ] **2.3.1** — `## Unreleased` holds the DeepSeek multi-currency balance
  fix (#117). Ship it as a patch release with `docs/release-checklist.md`, or
  let it ride with the first feature below if one lands within a week.
  `S · ★★★`

## 🔧 Partial — needs a follow-up

- [~] **Live check of the new spend providers** — Anthropic API, OpenAI API,
  Ollama Cloud and Vercel AI Gateway are tested against the documented example
  responses only; no account was available. Run each card once with a real key
  and pin a sanitized live fixture, as done for Kimi Code. `S · ★★`
- [~] **Gemini CLI quota on a licensed account** — the ineligible path is
  live-verified (Google returns `UNSUPPORTED_CLIENT` to individual Gemini CLI
  accounts since 2026), but the per-model buckets of a Code Assist Standard or
  Enterprise project are only fixture-tested from the CLI's
  `RetrieveUserQuotaResponse` type. Verify with a licensed account. `S · ★★`
- [~] **Measure the whole dispatcher** — `providers/get-provider-usage`
  counts only 46 statements: kcov's parser loses its quote state at a
  multi-line jq program that opens on a backslash-continued line (the first is
  `json_note_usage`), so it treats later code as a string and stops listing
  it. Coverage is 100% of what kcov lists. Reformat those jq calls (program on
  the command's first line) or move them into functions, then cover what
  becomes visible. `M · ★★`

## ✨ Features — bar, dashboard and alerts

Ideas checked against similar projects (CodexBar, ai-usagebar, quotabar,
ccusage, Claude-Code-Usage-Monitor, tokscale) and against the non-goals in
`docs/roadmap.md`: everything below stays local-first and read-only.

- [ ] **IPC `refresh` and `status`** — today IPC only has `toggle`,
  `settings`, `about` and `focus`. Add `refresh` (one provider or all) for a
  compositor key or a post-login hook, and `status` returning one compact JSON
  line (provider, headline window, percent, reset), so scripts, tmux and other
  bars reuse the widget's snapshot instead of polling providers again.
  `S · ★★`
- [ ] **Scroll and middle-click on the bar pill** — wheel over the pill cycles
  the provider shown in `top` mode (or the window of a single-provider pill);
  middle-click refreshes. Idea from ai-usagebar's scroll-to-cycle. Keep the
  choice in memory only, so it never rewrites `pillMode`. `S · ★★`
- [ ] **Detect providers** — a settings button that enables every provider
  whose readiness is already **Ready** (credential or CLI found), with a
  confirmation listing them. Readiness exists; this is the one-click onboarding
  ai-usagebar ships as `detect`. Never raises a keyring prompt. `S · ★★`
- [ ] **Pace for every window** — `windowBurnForecast()` only runs in the
  Claude details panel. Move it next to `BarWindows.js` (in `lib/`, see
  #92), and show it for every rolling window that reports `resetsAt` and a
  window length: "on pace", "ahead by 12%" or "runs out in 2h 10m, resets in
  3h". Add an even-use tick on each quota bar at the elapsed fraction of the
  window (CodexBar's even-use guide). Label it as a projection; skip balance,
  informational and analytics-only windows. `M · ★★★`
- [ ] **Forecast alert** — opt-in `notifyForecast`: alert once per window
  when the pace above projects exhaustion before the reset, before the
  threshold is crossed. Reuses the dedupe key and cooldown of quota alerts;
  require a minimum elapsed share (for example 15%) so one early burst does not
  fire it. `M · ★★`
- [ ] **Unused-quota reminder** — opt-in alert when a weekly window resets
  within N hours with most of it unused ("Codex weekly resets in 6h, 70%
  left"), as CodexBar does for Codex. Off by default; weekly windows only.
  `S · ★`
- [ ] **Quota burndown chart** — the expanded card's sparkline shows recent
  snapshots only. Add a per-window chart over the current window from
  `usage-history.jsonl`, with reset markers and the even-use line, so a user
  sees whether this week runs hotter than the last. `M · ★★`
- [ ] **Activity heatmap and streaks** — a 12-week, GitHub-style grid of daily
  tokens or estimated cost for the local-telemetry providers (Claude, Codex,
  OpenCode, 9Router, pi, Hermes), with active days and current streak. Read
  from the analytics already collected; no new source. Idea from tokscale.
  `M · ★★`
- [ ] **Bar meter style** — optional thin progress bar under each pill entry
  (two stacked bars for `primary+secondary`), for users who read a fill level
  faster than a number. CodexBar's two-meter icon. Respect vertical bars and
  `pillCompact`. `M · ★★`
- [ ] **Adaptive refresh** — refresh faster (down to 60 s) while a displayed
  window is above 80% or local telemetry changed, slower while the session is
  locked or idle, never below each adapter's own cache TTL or backoff.
  `M · ★★`
- [ ] **Spend budgets in settings** — `ANTHROPIC_MONTHLY_BUDGET_USD` and its
  OpenAI twin are environment-only. Add per-provider monthly budgets to the
  settings page for every spend provider (Anthropic API, OpenAI API,
  OpenRouter, Vercel AI Gateway, Ollama Cloud), turning spend into a quota
  window that alerts like any other. An exported variable still wins. `M · ★★`
- [ ] **Weekly digest** — opt-in notification once a week: tokens and
  estimated cost per local-telemetry provider versus the previous week, and
  the busiest model and project. Local data only. `M · ★`
- [ ] **Settings backup** — export and import every plugin setting (including
  Claude profiles, pins and per-provider overrides) as one JSON file, validated
  on import like the CSV fields are today. `S · ★`

## Providers — Data & Auth

### Improvements to existing providers

- [ ] **Claude Code status line bridge** — Claude Code (2.1.80+) passes
  `rate_limits.five_hour` / `seven_day` (`used_percentage`, `resets_at`) to a
  `statusLine` command. Ship an optional `providers/claude-statusline-bridge`
  that the user chains into their status line: it writes the reading,
  owner-only, under `~/.cache/AiOverviewControl/`, and the Claude adapter
  prefers a fresh reading (per `CLAUDE_CONFIG_DIR`, so profiles keep their own)
  over the OAuth usage endpoint. Fewer requests while Claude Code is in use,
  so less 429 pressure (#96). The field is absent before the first response
  and was missing in some releases (anthropics/claude-code#45133), so the
  endpoint stays the fallback. `M · ★★★`
- [ ] **Codex profiles** — several Codex accounts side by side, each from its
  own `CODEX_HOME`, mirroring Claude profiles (`codex-<id>` provider IDs,
  same settings editor and 16-profile cap). `M · ★★★`
- [ ] **Provider status incidents** — opt-in: read the public Statuspage
  summary (`/api/v2/status.json`) of each enabled provider that has one
  (Anthropic, OpenAI, GitHub, Cursor, OpenRouter, …), cached for 10 minutes,
  and show an incident badge on the card and a dot on the pill. No
  credential is sent. Adds hosts, so `docs/usage.md#network-endpoints`, the
  README privacy note and `AIOC_NO_STATUS=1` ship with it. CodexBar does the
  same. `M · ★★`
- [ ] **Token mix for local telemetry** — split tokens into input, output,
  cache read, cache write and reasoning where the logs carry them, and show the
  cache-hit share, which explains most of the gap between token count and
  estimated cost. `M · ★`

### Blocked upstream (checked monthly)

No work starts until a read-only source exists. Last check: 2026-10-26.

- [ ] **Cline ClinePass usage** — the Cline dashboard reads the 5-hour, weekly
  and monthly windows from the undocumented
  `GET https://api.cline.bot/api/v1/users/me/plan/usage-limits`
  (`data.limits[]` with `type`, `percentUsed`, `resetsAt`). Blocked on a
  ClinePass account to verify the shape and pin a fixture; today the card
  shows only the plan and renewal date. `M · ★★`
- [ ] **NVIDIA** — build.nvidia.com replaced trial credits with per-model rate
  limits it does not publish; there is no balance or rate-limit API. Surface
  rate-limit headers if NIM responses start carrying them, otherwise close as
  WONTFIX. `M · ★★`
- [ ] **Mistral** — `is_default_key` and rate-limit data. No quota or usage
  endpoint; limits are only in Admin Console → Limits. `M · ★★`
- [ ] **BytePlus/Ark** — per-model `remaining_tokens`. Free quota and rate
  limits per model are only in the console (Activation Management). `M · ★★`
- [ ] **Hermes / Nous Portal** — real spend for the provider half. Requested
  upstream in
  [NousResearch/hermes-agent#24814](https://github.com/NousResearch/hermes-agent/issues/24814);
  only the local agent half (`~/.hermes/state.db`) is measurable. `M · ★★`

### Candidates — not started

- [ ] **JetBrains AI** — quota lives in the IDE's local options and logs, with
  no documented format. Needs an installed IDE with an AI Assistant license to
  read real files before writing a parser. `M · ★★`
- [ ] **Windsurf** — plan usage lives in the editor's local state database,
  with no documented format. Same requirement as JetBrains AI. `M · ★★`
- [ ] **Anthropic and OpenAI budgets from the API** — both cards use an
  optional `*_MONTHLY_BUDGET_USD` because Console and Platform organizations
  expose no spend limit. Switch to the API if one is published (Anthropic's
  Spend Limits API is Claude Enterprise only today). `S · ★`

## 🎨 Polish and finish

- [ ] **First-run state** — with nothing measurable yet (fresh install, every
  provider signed out), the popout shows an empty hero. Show a short card
  instead: which default providers need a sign-in, a **Detect providers**
  button and a link to settings. `S · ★★`
- [ ] **Loading placeholders** — on the first refresh after a shell start,
  draw placeholder cards and pill entries with a subtle pulse instead of empty
  space or `0%`, so slow adapters (Codex app-server, Antigravity) do not read
  as idle. `S · ★★`
- [ ] **Screen reader names** — the widget has no `Accessible` properties and
  the dashboard has three. Give the pill, header actions, provider cards,
  capsule buttons and quota bars an `Accessible.name`/`role` that reads the
  provider, window, percentage and reset, and translate them. `M · ★★`
- [ ] **Refresh screenshots and demo** — `docs/assets/settings.png`, the demo
  GIF and the README feature table predate the 2.3 settings groups and live
  preview. Re-record them with sample data (no real accounts). `S · ★★`
- [ ] **New locales** — announce French, Japanese and Russian on Crowdin and
  merge any locale that reaches full coverage; the parity gate already
  enforces completeness. `S · ★`
- [ ] **Split `DashboardContent.qml`** — 4,235 lines with 13 inline
  components. Move the larger ones (provider card, Claude/pi/Hermes details,
  hero) into files under a new subdirectory loaded by URL, as
  `docs/refactoring.md` describes, so a running shell's cached directory
  listing cannot break the import (#92). `L · ★★`

## Quality / CI

- [ ] **Duplicate IPC handler warning** — with more than one bar, every widget
  instance registers the `aiOverviewControl` IPC target and Quickshell logs
  "Handler was registered but will not be used" for the extra ones. IPC works;
  register the handler from one instance only to silence it. `S · ★`

- [ ] **Packaged kcov** — CI builds kcov from a pinned commit after 43,
  which fixed lost bash line tracking after a multi-line quoted argument with
  a single quote. Switch back to the Arch package once kcov 44 ships, and
  update the local build note in `docs/development-gates.md`. `S · ★`

## Integrations

- [ ] **Waybar and terminal output** — `providers/get-provider-usage` already
  prints the merged JSON. Add a documented `--format waybar` (text, tooltip,
  class by severity) and `--format line` mode, and declare the JSON shape a
  stable contract in `docs/architecture.md`, so the same adapters serve users
  on other bars and in tmux without the plugin installed. `M · ★★`
- [ ] **Read-only MCP server** — `providers/aioc-mcp`, a local stdio server
  exposing `get_usage` and `list_providers` over the cached snapshot, so a
  coding agent can check its own quota before a long task. No network of its
  own, no write tools. ai-usagebar ships the same idea. `M · ★`

## Project health

- [ ] **Registry metadata** — publish the `requires_dms` constraint in the
  Dux Shell plugin registry entry once the registry accepts it, so DMS 1.6
  users stay on 1.22.0 (`docs/roadmap.md`, `docs/release-checklist.md`).
  `S · ★★`
- [ ] **Account successor** — designate a GitHub account successor for the
  maintainer account (see `GOVERNANCE.md`). `S · ★★`
- [ ] **Second maintainer** — grant the maintain role to a second trusted
  contributor, then require one approving review on `main`. `L · ★★`

## ✅ Shipped in 2.3.0 (removed after the next release)

- [x] **Grok Bot provider** — weekly Grok Bot Plan pool with the app's saved
  reading offline; keyring-backed sessions reported, not guessed (#109).
- [x] **Keyring keys** — `AIOC_VAULT_*` for OpenRouter, Z.ai, GLM and OpenCode
  Go, never prompting from a background refresh (#105).
- [x] **Honest bar pill** — a used-up window takes over the bar, prepaid
  balances read as amounts (#106, #107).
- [x] **Settings page** — foldable groups, live bar preview, provider search
  (#113).
- [x] **Provider fixes** — OpenCode Go nested envelope (#104), Antigravity local
  language server per account (#108).
- [x] **Translations and Crowdin** — readiness details translated, Crowdin
  resynced with a sync workflow (#112, #114).
- [x] **Coverage to 100%** — the remaining statements covered (Codex
  app-server that ignores SIGTERM, exchange-rate lock timeout, LiteLLM
  pricing cache, Antigravity CLI token errors, xAI renewal rejections, a stray
  release-archive entry), dead code removed, and multi-line commands kcov
  could not attribute restructured; the gate rises to 97%.
- [x] **Release 2.3.0** — [docs/releases/2.3.0.md](docs/releases/2.3.0.md).

## Decided against

- **Incremental transcript parse** (Claude) — measured 2026-09-30: 805
  transcripts / 288 MB; warm refresh 0.26 s, refresh after the 20 MB active
  transcript changed 0.43 s. Revisit only if a changed-file refresh passes
  ~2 s (`ponytail:` note in `get-claude-usage`).
- **Translating `formatTier()` names** — `Max 20x`/`Pro`/`Free` are brand plan
  names, not UI chrome.
- **Separate marketplace metadata** — the Dux Shell plugin registry entry is the
  marketplace metadata; it is tracked under the registry item above.
- **Rewriting SQL to work around kcov** — single-line SQL pieces did not
  restore kcov's line tracking and cost readability; the limitation is
  documented instead.

---

Shipped work before 2.3.0 is in `CHANGELOG.md`.
