# Roadmap

This roadmap covers the next twelve months (through October 2027). It states
what the project intends to do and, just as important, what it will not do.
The detailed backlog, with effort and impact estimates, lives in
[TODO.md](../TODO.md); shipped work moves to [CHANGELOG.md](../CHANGELOG.md).

## Direction

AiOverviewControl stays a **local-first** DankMaterialShell plugin: it reads
quota, billing, authentication and usage data that each AI tool or provider
already exposes, and shows it in the DankBar and a dashboard, with no service
of its own in between.

## Planned

### DankMaterialShell 2.x

- Keep the plugin working on each DMS 2.x release, with the native UI test in
  CI pinned to a tested DMS revision.
- Publish the `requires_dms` constraint in the DMS plugin registry entry, so
  DMS 1.6 users stay on 1.22.0 instead of receiving an incompatible update.
- Explore the DMS 2.0 Dash surface for a compact fleet card.

### Providers

- Keep every supported provider working when its API or CLI changes, with a
  fixture test for each fix.
- Surface richer data when upstream exposes it read-only: NVIDIA NIM balance,
  ClinePass usage windows, Mistral rate-limit data, BytePlus per-model quotas
  and the Nous Portal half of Hermes. These are checked monthly; no work starts
  until the upstream endpoint exists.
- Add new providers on request through the provider request form, when the
  provider offers a documented or stable read-only usage source.

### Quality and security

- Keep shell statement coverage at 80% or more, and raise the weakest files
  (provider health checks, Hermes analytics, the dispatcher) toward 90%.
- Extend fuzzing beyond the API-key adapters to the local readers (transcripts,
  SQLite databases, OAuth files).
- Pass every `Authorization` header to `curl` through `--config` on a pipe
  instead of the command line, and create every cache directory owner-only.
- Keep the supply-chain controls current: SHA-pinned actions, checksum-verified
  CI tools, signed release provenance, secret scanning and the OpenSSF
  Scorecard.

### Project health

- Designate a GitHub account successor and add a second maintainer, then
  require one approving review on `main` (see [GOVERNANCE.md](../GOVERNANCE.md)).
- Keep all five locales (en, pt_BR, zh_CN, es_ES, de_DE) in exact parity and
  welcome new locales through Crowdin.

## Not planned

The project will **not**:

- run a hosted service, account system or remote telemetry; usage data never
  leaves the user's machine except in the requests each provider already needs;
- store, sync or proxy provider credentials; adapters read them from each
  tool's own configuration and send them only to that provider;
- bypass a provider's authentication, terms of service or rate limits, or
  scrape web dashboards with a stolen or replayed browser session;
- change provider settings, buy credits or perform any write action on a
  provider account, except redeeming a limit reset the account already holds,
  one per explicit user confirmation;
- support desktop shells other than DankMaterialShell, or DMS 1.x beyond the
  1.22.0 release;
- estimate costs that a provider does not report: unknown cost stays unknown.

## How to influence the roadmap

Open a feature or provider request issue, or comment on an existing one. The
decision process is described in [GOVERNANCE.md](../GOVERNANCE.md).
