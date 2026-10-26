# TODO

Roadmap and backlog for **AiOverviewControl**.

**Legend** — Effort: `S` (≤1h) · `M` (≤half-day) · `L` (multi-day).
Impact: `★` nice-to-have · `★★` solid win · `★★★` high value.
Open items are ordered quick-wins-first within each section. Completed items
stay one release cycle, then move to `CHANGELOG.md`.

---

## 🔧 DMS 2.0 follow-ups

- [ ] **Registry entry** — `requires_dms: ">=2.0.0"`, the `dash-card`
  capability and the 39-provider description in
  `plugins/bernardopg-aioverviewcontrol.json`, so DMS 1.6 users keep 1.22.0
  instead of being offered an incompatible update. Open as
  [duxlabs-dev/dux-plugin-registry#1095](https://github.com/duxlabs-dev/dux-plugin-registry/pull/1095);
  close this item when it merges. `S · ★★★`
- [x] **Dash plugin surface** — `AiOverviewDashCard.qml`, a DankDash overview
  card fed by the widget's `dash-snapshot.json`; shipped in 2.1.0. `M · ★★`

## Providers — Data & Auth

Upstream-blocked items are checked monthly; each one records the date of its
last check. No work starts until a read-only source exists.

- [ ] **Cline ClinePass usage** — show the 5-hour, weekly and monthly ClinePass
  windows. The Cline dashboard reads them from
  `GET https://api.cline.bot/api/v1/users/me/plan/usage-limits` (bearer token,
  `data.limits[]` with `type`, `percentUsed`, `resetsAt`), which community
  tools already use. It is read-only but undocumented: verify the shape against
  a live ClinePass account and pin a sanitized fixture before shipping. Today
  only the plan and renewal date are read. Checked 2026-10-26. `M · ★★`
- [ ] **NVIDIA** — build.nvidia.com no longer uses credits: trial usage is
  limited by per-model rate limits that NVIDIA does not publish, and there is
  still no balance or rate-limit API. Surface rate-limit headers if NIM
  responses start carrying them; otherwise close as WONTFIX. Checked
  2026-10-26. `M · ★★`
- [ ] **Mistral** — surface `is_default_key` and rate-limit data. No quota or
  usage endpoint; limits live in Admin Console → Limits. Docs mention an
  `X-RateLimit-Remaining` header on responses, which would need a request per
  refresh. Checked 2026-10-26. `M · ★★`
- [ ] **BytePlus/Ark** — surface `remaining_tokens` per model. Free quota and
  rate limits per model are shown only in the console (Activation Management);
  no API returns them. Checked 2026-10-26. `M · ★★`
- [ ] **Hermes** — real quota/spend for the provider half. Nous Portal still has
  no read-only usage endpoint (requested upstream in
  [NousResearch/hermes-agent#24814](https://github.com/NousResearch/hermes-agent/issues/24814));
  only the local agent half (`~/.hermes/state.db`) is measurable. Checked
  2026-10-26. `M · ★★`

## Quality / CI

- [ ] **Raise the weakest coverage files toward 90%** — total shell statement
  coverage is 85.61% (2026-10-26, `scripts/coverage`; CI gate 80%). Lowest:
  `providers/get-hermes-analytics` 47.83%, `providers/native/hermes.bash`
  52.27%, `providers/get-provider-health` 60.00%,
  `providers/reset-provider-limits` 71.88%, `providers/native/opencode.bash`
  72.22%, `providers/get-local-analytics` 73.21%, `providers/get-provider-usage`
  74.83%. `scripts/qmlls-setup` (10%) is a developer tool exercised by the
  `qml-runtime` CI job, not by the shell suites. `M · ★★`
- [ ] **DMS pin** — the `qml-runtime` job checks out DankMaterialShell
  `v2.0.0`; bump the pinned revision when a newer DMS 2.x is released.
  `S · ★★`

## Project health

- [ ] **Account successor** — designate a GitHub account successor for the
  maintainer account (see `GOVERNANCE.md`). `S · ★★`
- [ ] **Second maintainer** — grant the maintain role to a second trusted
  contributor, then require one approving review on `main`. `L · ★★`

## Decided against

- **Incremental transcript parse** (Claude) — measured 2026-09-30: 805
  transcripts / 288 MB; warm refresh 0.26 s, refresh after the 20 MB active
  transcript changed 0.43 s. Revisit only if a changed-file refresh passes
  ~2 s (`ponytail:` note in `get-claude-usage`).
- **Translating `formatTier()` names** — `Max 20x`/`Pro`/`Free` are brand plan
  names, not UI chrome.
- **Separate marketplace metadata** — the DMS plugin registry entry is the
  marketplace metadata; it is tracked under the registry item above.

---

Shipped work, including everything this file tracked up to 2.1.1, is in
`CHANGELOG.md`.
