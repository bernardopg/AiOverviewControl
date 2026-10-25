# Governance

AiOverviewControl is a community plugin for DankMaterialShell with a single
maintainer. This document describes how decisions are made, who holds which
role, what each role must do, and how the project continues if the maintainer
becomes unavailable.

## Governance model

The project follows a **maintainer-led** model, sometimes called "benevolent
dictator": the maintainer makes the final call on scope, design, merges and
releases, after public discussion when a change is not trivial.

- Proposals start as a GitHub issue (bug report, feature request or provider
  request form) or as a pull request. Larger ideas can start in Discussions.
- Anyone may comment. The maintainer weighs the discussion against the
  [roadmap](docs/roadmap.md), the [security requirements](docs/security.md) and
  the runtime contracts in [AGENTS.md](AGENTS.md).
- The decision and its reason are recorded on the issue or pull request, so the
  history stays public and searchable.
- Rules that protect `main` and release tags are versioned in
  [`.github/repository-rules/`](.github/repository-rules/) and explained in
  [docs/repository-rules.md](docs/repository-rules.md). Changing them is itself
  a reviewed pull request.

Everyone in the project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Roles and responsibilities

| Role | Who | Responsibilities |
| --- | --- | --- |
| Maintainer | [@bernardopg](https://github.com/bernardopg) | Triage issues and discussions; review and merge pull requests; keep CI, rulesets and dependencies healthy; cut releases following [docs/release-checklist.md](docs/release-checklist.md); handle vulnerability reports as described in [SECURITY.md](.github/SECURITY.md); enforce the Code of Conduct. |
| Security contact | The maintainer | Acknowledge private vulnerability reports within 7 days, coordinate the fix and the advisory, and credit the reporter. |
| Contributor | Anyone who opens a pull request | Follow [CONTRIBUTING.md](CONTRIBUTING.md): pass the local gates, add a test and a `CHANGELOG.md` bullet with each behavior change, keep all five locales in parity, and sign off every commit under the [DCO](CONTRIBUTING.md#developer-certificate-of-origin). |
| Translator | Contributors on Crowdin | Translate UI strings through the Crowdin project described in [docs/i18n-crowdin.md](docs/i18n-crowdin.md). The maintainer reviews the synced bundles. |
| Reporter | Anyone | Report bugs and request features through the issue forms; report vulnerabilities privately as described in [SECURITY.md](.github/SECURITY.md). |

Contributors are credited in the README contributor grid, which is append-only
(see [CONTRIBUTING.md](CONTRIBUTING.md#contributor-credits)).

## Code review

Every change reaches `main` through a pull request. Before merge, a pull
request must:

- pass every required check in [docs/repository-rules.md](docs/repository-rules.md):
  changelog integrity, metadata and i18n parity, shellcheck, QML lint,
  integration and runtime tests, release packaging, secret scanning, workflow
  security audit and DCO sign-off;
- have all review conversations resolved;
- keep the runtime contracts in [AGENTS.md](AGENTS.md): credentials stay with
  their own provider, unknown cost is `null`, caches live under the XDG cache
  directory, and tests stay offline;
- ship docs, translations, a `CHANGELOG.md` bullet and a test with any
  user-visible behavior change.

The reviewer checks correctness, the security requirements in
[docs/security.md](docs/security.md) (input handling, credential handling,
network destinations, temporary files), test coverage of the change, and that
the change fits the roadmap. Pull requests from contributors are reviewed by
the maintainer. The maintainer's own pull requests rely on the required checks;
see [Continuity](#continuity-and-bus-factor) for the current limits.

## Continuity and bus factor

The project currently has a **bus factor of one**: only the maintainer can
merge pull requests, publish releases and administer the repository settings.

What already survives without the maintainer:

- The source, history, issues, releases and documentation are public on GitHub
  under the MIT license, so anyone can fork and continue the project.
- Build, test and release steps are automated and documented in
  [docs/release-checklist.md](docs/release-checklist.md) and
  [docs/development-gates.md](docs/development-gates.md); no step depends on a
  private machine or secret held only by the maintainer, except the optional
  Crowdin token.
- Release archives carry signed build provenance, so a successor can keep the
  verification chain described in [SECURITY.md](.github/SECURITY.md).

Planned improvements, tracked in the [roadmap](docs/roadmap.md):

1. Designate a GitHub account successor for the maintainer account, so access
   to the repository can be transferred if the maintainer cannot continue.
2. Grant the maintain role to a second trusted contributor, then raise the
   required approving-review count on `main` from zero to one.

Until then, if the maintainer is unresponsive for more than 30 days on a
security report or a release-blocking bug, contributors are encouraged to fork
the project and announce the fork in the
[DankMaterialShell plugin registry](https://github.com/duxlabs-dev/dux-plugin-registry).

## Changes to this document

Changes to this governance document follow the normal pull request process and
are announced in `CHANGELOG.md`.
