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

- [ ] **Next release** — nothing is queued in `## Unreleased` after 2.3.0;
  follow `docs/release-checklist.md` once it is. `S · ★★★`

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

- [ ] **Duplicate IPC handler warning** — with more than one bar, every widget
  instance registers the `aiOverviewControl` IPC target and Quickshell logs
  "Handler was registered but will not be used" for the extra ones. IPC works;
  register the handler from one instance only to silence it. `S · ★`

- [ ] **Packaged kcov** — CI builds kcov from a pinned commit after 43,
  which fixed lost bash line tracking after a multi-line quoted argument with
  a single quote. Switch back to the Arch package once kcov 44 ships, and
  update the local build note in `docs/development-gates.md`. `S · ★`

## Project health

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
