# Contributing to AiOverviewControl

Thanks for helping improve the plugin. This guide covers the local dev loop, the
CI gates you must satisfy, and the QML/shell gotchas that have bitten us before.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md). How
decisions are made and who holds which role is described in
[GOVERNANCE.md](GOVERNANCE.md); where the project is heading is in the
[roadmap](docs/roadmap.md). Report vulnerabilities privately as described in
[SECURITY.md](.github/SECURITY.md), never in a public issue.

## Project layout

| Path | Purpose |
| --- | --- |
| `AiOverviewControlWidget.qml` | Main UI — dankbar pill + popout dashboard. |
| `AiOverviewControlSettings.qml` | Plugin settings page. |
| `AiOverviewControlI18n.qml` | Locale loading + string interpolation (singleton). |
| `ProviderLogo.qml` | Local provider-logo resolution, tinting, and fallback icons. |
| `i18n/*.json` | Translation bundles (`en` is the source of truth). |
| `providers/get-*` | Provider adapters and helpers; `get-provider-usage` dispatches. |
| `scripts/package-release` | Builds and validates the installable release archives. |

## Dev loop

Hot-reload the running plugin without restarting the shell:

```bash
qs -p ~/.config/quickshell/dms ipc call plugins reload aiOverviewControl
# → PLUGIN_RELOAD_SUCCESS: aiOverviewControl
```

Two caveats that cost real debugging time:

- **Reopen the popout after every reload.** A reload does *not* re-render a
  popout that is already open — the old instance stays in memory. Close and
  reopen it to see UI changes.
- **`AiOverviewControlI18n` is a `pragma Singleton` and is frozen at the
  quickshell process level.** A plugin reload re-instantiates the widget but
  **not** the singleton: both its cached translation bundles *and its code* stay
  as they were when the shell process started. New i18n keys (or singleton code
  changes) only appear after a full `qs` restart. The widget calls
  `AiOverviewControlI18n.refresh()` on completion (typeof-guarded) so future
  sessions re-read the JSON on reload, but the session that introduced the
  change still needs a restart.

## QML gotchas

- **`modelData` in custom `Repeater` delegates.** A `Repeater` injects
  `modelData` into a *plain inline* delegate, but a delegate that is a **custom
  component** (e.g. `UsageBar { ... }`) does **not** receive it implicitly — you
  must declare `required property var modelData` inside the delegate, or every
  binding that reads `modelData` silently renders blank. This is exactly what
  broke the v1.4.5 hero window bars. When a delegate is a custom component and
  reads `modelData`, add the required property.
- **Contained rounded indicators, not full-height stripes.** A left accent bar
  anchored top-to-bottom inside a `radius`/`clip: true` parent bleeds square
  corners past the rounded edge. Use the contained treatment instead:
  `anchors.verticalCenter`, a height inset from the parent, and
  `radius: width / 2` (see the provider card and `MetricTile` indicators).
- **Local `qmllint` import noise.** With the Qt5 `qmllint` (default, no `-U`)
  the files lint clean. If you pass `-U` or use the Qt6 `qmllint`, you will see
  unavoidable `qs.*` import-resolution warnings for DankMaterialShell modules
  that are not on the lint path — filter them:

  ```bash
  QT_FORCE_STDERR_LOGGING=1 qmllint *.qml 2>&1 | grep -vE "qs\.|was not found|Unqualified|import"
  ```

  Keep `QT_FORCE_STDERR_LOGGING=1`: without a terminal, Qt6 `qmllint` sends its
  messages to journald instead of stderr, so a piped run looks clean while
  parse errors land in `journalctl --user`. Trust the exit code (non-zero means
  a parse error). Qt6's parser also rejects a `: void` return annotation, so
  `IpcHandler` functions return `string`.

## Providers

- Most API-backed and informational `providers/get-<id>-usage` stubs `exec`
  `get-provider-wrapper <id>`, which calls into `get-provider-usage`'s
  `fetch_provider()` dispatch. A case is `canonical|alias1|alias2)`; the
  **first** token is the canonical provider that owns a stub, and the rest are
  documented aliases. Codex, Claude, and Copilot use specialized helpers; `pi`
  uses an inline dispatcher envelope plus `get-pi-analytics` rather than a
  generic usage stub.
- Scripts must be executable (`chmod +x`) and pass `shellcheck`.

## CI

Run `scripts/check-metadata` for the shared CI/pre-push metadata checks.
See [development gates](docs/development-gates.md) for opt-in hook installation,
Quickshell runtime smoke coverage, and the extracted history-writer contract.
 gates (run these locally before pushing)

| Gate | Local command |
| --- | --- |
| `plugin.json` valid + semver | `jq -e . plugin.json` |
| i18n JSON valid | `for f in i18n/*.json; do jq -e . "$f"; done` |
| **i18n key parity** (all locales == `en`) | `for locale in pt_BR zh_CN es_ES de_DE; do diff <(jq -r 'keys[]' i18n/en.json) <(jq -r 'keys[]' "i18n/$locale.json") || exit 1; done` |
| CHANGELOG has the `plugin.json` version | `VERSION="$(jq -r .version plugin.json)"; grep -qF "## $VERSION" CHANGELOG.md \|\| grep -qF "## [$VERSION]" CHANGELOG.md` |
| **QML lint (hard gate)** | `QT_FORCE_STDERR_LOGGING=1 qmllint *.qml` |
| Shell syntax | `find providers -type f -print0 \| xargs -0 -n 1 bash -n; for test in tests/*.sh; do bash -n "$test"; done; bash -n scripts/package-release` |
| Shell lint | `find providers -type f -print0 \| xargs -0 shellcheck -S warning; shellcheck -S warning tests/*.sh scripts/package-release` |
| Release package | `scripts/package-release` |

Parity is strict: every key in `en.json` must exist in `pt_BR`, `zh_CN`,
`es_ES`, and `de_DE`, and vice versa. Prefer `t("key", "English fallback")`
calls so a missing translation degrades gracefully, but the key must still be
present in all five bundles.

## Commits and PRs

Use Conventional Commits with a scope (`feat(pill): …`). Commit messages, PR
descriptions and release notes describe the change itself; do not add AI
co-author trailers or "generated with" footers.
Sign off every commit (`git commit -s`, see
[Developer Certificate of Origin](#developer-certificate-of-origin)). What a
reviewer checks before merging is listed in
[GOVERNANCE.md](GOVERNANCE.md#code-review).

## Coding standards

- **Shell**: `bash` with `set -euo pipefail` in entrypoints, quoted expansions,
  `mktemp` for temporary files, and no provider data in a command string. Every
  script passes `shellcheck -S warning`.
- **JSON**: parse and build provider data with `jq` (`--arg`/`--argjson`), never
  with string concatenation. Unknown cost is `null`, never `0`.
- **QML**: passes `qmllint`; run helpers with argument arrays; user-visible
  strings use `t("key", "English fallback")`.
- **Credentials and network**: follow the requirements in
  [docs/security.md](docs/security.md). Tests stay offline and use fake
  credentials.

CI enforces these through the gates above; a pull request that fails one is not
merged.

## Developer Certificate of Origin

Every commit in a pull request must be signed off under the
[Developer Certificate of Origin 1.1](https://developercertificate.org/). By
signing off you certify that you wrote the change, or otherwise have the right
to submit it under the project's MIT license:

```text
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

Sign off with `git commit -s`, which adds a trailer with your name and the
commit author email:

```text
Signed-off-by: Your Name <you@example.com>
```

The **DCO sign-off** check (`scripts/check-dco`) fails a pull request when a
non-merge commit lacks a `Signed-off-by` trailer for its author's email. To fix
existing commits, run `git rebase --signoff origin/main` and force-push your
branch. Commits from GitHub App bots such as Dependabot are exempt.

## Contributor credits

The avatar grid in `README.md` and `docs/README.pt-BR.md` is generated by
`scripts/render-contributors` and is **append-only**: once someone is credited,
they stay credited. GitHub's contributors API silently drops people whose commit
email no longer resolves to their account, so a fresh listing must never be used
to remove anyone.

- **[@SkippySteve](https://github.com/SkippySteve) must never be removed.** The
  API already reports his commits as anonymous; his login is pinned in
  `scripts/render-contributors` (`PINNED`) and `tests/test-render-contributors.sh`
  fails if either README stops crediting him. Do not edit him out by hand, and
  reject any PR, bot proposal or the Contributors workflow summary that would.
- New contributors are appended in the order the API reports them; existing
  entries keep their position.
- Only automation accounts listed in `EXCLUDED` (coding assistants that commit
  under a vendor address) are ever left out.
- To credit someone the API misses, add their login to `PINNED`.

Badge counts are not edited by hand either: `scripts/render-badges` derives the
provider and language counts from the code into `docs/badges.json`, which the
README badges read live, and `scripts/check-metadata` fails when a copy is stale.

## Release

See [`docs/release-checklist.md`](docs/release-checklist.md). In short: bump
`plugin.json` (patch for fixes/UI, minor for features), add a `CHANGELOG.md`
entry, commit, push `main`, wait for **green CI**, then tag `vX.Y.Z` (the tag
must equal the `plugin.json` version — `release.yml` validates it) and push the
tag to trigger the release build.
