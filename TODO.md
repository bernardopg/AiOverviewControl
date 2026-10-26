# TODO

Roadmap and backlog for **AiOverviewControl**. The direction and the
non-goals are in [docs/roadmap.md](docs/roadmap.md).

**Legend** — Effort: `S` (≤1h) · `M` (≤half-day) · `L` (multi-day).
Impact: `★` nice-to-have · `★★` solid win · `★★★` high value.
**Status:** `[ ]` not started · `[~]` partial / in progress · `[x]` done.
Open items are ordered quick-wins-first within each section. Completed items
stay one release cycle, then move to `CHANGELOG.md`.

---

## 🚀 Next release (2.2.0)

`## Unreleased` in `CHANGELOG.md` holds four new providers, Gemini CLI quota,
the coverage-measurement fix and the 2.1 documentation.

- [ ] **Release 2.2.0** — follow `docs/release-checklist.md`: release branch,
  version bump in `plugin.json`, `## 2.2.0` heading, `docs/releases/2.2.0.md`,
  PR with green checks, signed tag. `S · ★★★`

## 🔧 Partial — needs a follow-up

- [~] **Registry entry** — `requires_dms: ">=2.0.0"`, the `dash-card`
  capability and the provider count in
  `plugins/bernardopg-aioverviewcontrol.json`, so DMS 1.6 users keep 1.22.0.
  Open as
  [duxlabs-dev/dux-plugin-registry#1095](https://github.com/duxlabs-dev/dux-plugin-registry/pull/1095),
  waiting for the registry maintainers. It states 39 providers: update the
  description to 43 after 2.2.0 ships. `S · ★★★`
- [~] **Live check of the new spend providers** — Anthropic API, OpenAI API,
  Ollama Cloud and Vercel AI Gateway are tested against the documented example
  responses only; no account was available. Run each card once with a real key
  and pin a sanitized live fixture, as done for Kimi Code. `S · ★★`
- [~] **Gemini CLI quota on a licensed account** — the ineligible path is
  live-verified (Google returns `UNSUPPORTED_CLIENT` to individual Gemini CLI
  accounts since 2026), but the per-model buckets of a Code Assist Standard or
  Enterprise project are only fixture-tested from the CLI's
  `RetrieveUserQuotaResponse` type. Verify with a licensed account. `S · ★★`
- [~] **Weakest coverage files** — total shell statement coverage is 90.13%
  (gate 80%). Below 80%, measured 2026-10-26:
  `providers/get-hermes-analytics` 66.67%, `providers/native/hermes.bash`
  71.88%, `providers/reset-provider-limits` 71.88% (Claude sign-in and HTTP
  error branches), `providers/native/opencode.bash` 72.22%,
  `providers/get-local-analytics` 75.00%. The Hermes and OpenCode figures are
  understated by the kcov limitation below. `M · ★★`
- [ ] **Report the kcov line-tracking bug upstream** — kcov loses line
  tracking after a command whose multi-line quoted argument contains a single
  quote; reproducers are in `docs/development-gates.md`. File it at
  SimonKagstrom/kcov, then drop the caveat when a fixed kcov reaches Arch.
  `S · ★`

## Providers — Data & Auth

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

## Quality / CI

- [ ] **DMS pin** — the `qml-runtime` job checks out DankMaterialShell
  `v2.0.0`, still the latest release on 2026-10-26; bump it when a newer 2.x
  ships. `S · ★★`
- [ ] **Duplicate IPC handler warning** — with more than one bar, every widget
  instance registers the `aiOverviewControl` IPC target and Quickshell logs
  "Handler was registered but will not be used" for the extra ones. IPC works;
  register the handler from one instance only to silence it. `S · ★`

## Project health

- [ ] **Account successor** — designate a GitHub account successor for the
  maintainer account (see `GOVERNANCE.md`). `S · ★★`
- [ ] **Second maintainer** — grant the maintain role to a second trusted
  contributor, then require one approving review on `main`. `L · ★★`

## ✅ Done since 2.1.1 (moves to the 2.2.0 notes)

- [x] **Backlog refresh** — only open work, dated upstream checks (#79).
- [x] **2.1 documentation** — DankDash card and limit resets in architecture
  and troubleshooting; NVIDIA credits note (#80).
- [x] **Coverage** — 85.61% → 90.13%: multi-line statements measured on the
  line kcov records, new health-check, Copilot helper, Antigravity token
  refresh and Hermes cache tests (#81).
- [x] **New providers** — Anthropic API, OpenAI API, Ollama Cloud and Vercel
  AI Gateway, plus Gemini CLI quota and the ineligible-account reason (#82).
- [x] **Dash plugin surface** — `AiOverviewDashCard.qml`, shipped in 2.1.0.

## Decided against

- **Incremental transcript parse** (Claude) — measured 2026-09-30: 805
  transcripts / 288 MB; warm refresh 0.26 s, refresh after the 20 MB active
  transcript changed 0.43 s. Revisit only if a changed-file refresh passes
  ~2 s (`ponytail:` note in `get-claude-usage`).
- **Translating `formatTier()` names** — `Max 20x`/`Pro`/`Free` are brand plan
  names, not UI chrome.
- **Separate marketplace metadata** — the DMS plugin registry entry is the
  marketplace metadata; it is tracked under the registry item above.
- **Rewriting SQL to work around kcov** — single-line SQL pieces did not
  restore kcov's line tracking and cost readability; the limitation is
  documented instead.

---

Shipped work before 2.1.1 is in `CHANGELOG.md`.
