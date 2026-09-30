# Offline metadata and QML runtime gates

## Metadata and optional pre-push hook

Run `scripts/check-metadata` from any directory. It checks the release version
heading, numeric `major.minor.patch` version, locale JSON validity and exact
key parity, executable test/adapter files, and explicit CI registration of all
`tests/test-*.sh` suites. CI invokes the same script.

Install the repository hook explicitly (it is not installed automatically):

```bash
git config --local core.hooksPath .githooks
```

The hook checks the current working tree, not every commit being pushed. It is a
fast metadata safeguard, **not** a replacement for the integration, shellcheck,
QML lint, package, and remote CI gates. If you already have `core.hooksPath`
configured, integrate the call into that hook instead of overwriting it.

`tests/test-metadata.sh` exercises rejection cases in a temporary fixture;
it never changes repository metadata or permissions.

## Workflow dependencies

See [update-audit.md](update-audit.md) for verified upstream versions and the
scope of repository-managed tooling.
`tests/test-workflow-dependencies.sh` guards immutable external action references,
downloaded-tool checksums and the Crowdin 5 native launcher. This offline test
does not discover future releases; Dependabot covers actions, while pinned binary
versions still need explicit upstream review.

## Pinned order and retention feedback

Drag the ↕ handle on a pinned card onto another pinned card to insert before
it; no long press is required. The handle captures the gesture rather than
letting the page's Flickable scroll. Other card areas retain normal scrolling.
Unknown/self drops cannot add or remove pins; the runtime suite exercises forward
and backward moves and nonmutation.

`AIOC_TEST_POINTER=1 tests/test-widget-runtime.sh` opens a temporary fixture window
and sends a fast synthetic mouse drag (without a hold). It checks that pin order
changes while page scroll position does not. The default invocation keeps windows
hidden and checks common header-center alignment for handle, logo, percentage,
actions and collapsed accent stripe. QtTest is required for the optional pointer
exercise. Other monitor/scale and touch configurations still need manual checks.

Settings displays the number of valid history snapshots and the number removed
by the latest trim. `providers/get-history-stats` reads only local files; the
settings view refreshes it every five seconds. `history-trim.json` is written
atomically inside the existing history lock.

## QML runtime smoke

`tests/test-qml-smoke.sh` requires Quickshell (`qs`) and runs with the Qt offscreen
platform. CI provides it in an Arch Linux container. A temporary shell loads the
actual `LocalAnalyticsReader.qml`, with a deterministic bash adapter replacing
network/local account access. The suite checks pinned-order invariants, valid JSON, malformed JSON,
adapter errors, nonzero exit status, deadline cancellation, retry after timeout,
failure-retention policy, empty-argument scripts, and suppression of duplicate refreshes. All subprocesses are bounded and the
shell instance is stopped during cleanup. This test does not reload your DMS.

The extracted component receives its provider, script path, and timeout from the
widget. It does not depend on DMS services or dashboard state. The widget exposes
`codexStats`/`opencodeStats` snapshots from the reader's `result`.
Neither overrides QtQuick Item's default `data` property. The component is loaded
by URL so an existing DMS engine's cached qmldir cannot break hot reload.

`tests/test-currency-qml.sh` also runs offscreen and verifies conversion, locale,
precision, unavailable-rate fallback and currency changes during an active request.

`tests/test-widget-runtime.sh` instantiates the actual widget, both bar pills,
extracted dashboard, settings body and settings window with real DMS imports and
fixture-only provider scripts. Its isolated HOME/no-credential environment never
opens visible windows. It checks empty-provider bindings and live BRL→USD changes.
Use `scripts/qmlls-setup` first, or supply the import-tree parent with
`AIOC_DMS_IMPORTS`. It needs a native Wayland connection because Qt offscreen
cannot construct DMS PanelWindow types; without these prerequisites it reports
**SKIP**. The full suite passed locally; generic CI still needs an isolated
layer-shell backend before this can become a mandatory native gate.

See [refactoring.md](refactoring.md) for the controller/dashboard/native-adapter
boundaries and [currency.md](currency.md) for monetary units and network policy.
Lint of all root QML files and recursive syntax/ShellCheck of `providers/` remain
mandatory.

## Running DMS discovery

Use `scripts/reload-plugin` rather than guessing a config path. `dms run` can
launch Quickshell under `/run/user/<uid>/danklinux-shell/<hash>`, not
`~/.config/quickshell/dms`. The script discovers running instances via
`qs list --all`, queries each plugin IPC target, and reloads only shells where
the plugin is loaded. It never enables intentionally disabled plugins.
`tests/test-dms-reload.sh` checks discovery and failure handling using a fake qs.

## Translation coverage

`tests/test-i18n.sh` verifies every static QML translation lookup, all 38 provider
notes, exact key parity, nonempty strings, and interpolation parameters across
English, Portuguese (Brazil), Chinese (Simplified), Spanish, and German. The
provider notes previously bypassed the translation layer; they now use locale
keys (localized concise descriptions). Product names, CLI commands, environment
variable names, CSV/JSONL identifiers, and user/API-returned diagnostics remain
literal by design. This structural gate does not certify native-speaker wording
or translate arbitrary server messages.

## Codex credit snapshots

The dispatcher delegates persistence to `providers/record-usage-history`.
Quota snapshots retain their existing `{ts, provider, pct}` fields. For Codex,
a numeric nonnegative `credits.balance` also adds `creditBalance`, including
zero. The adapter populates this only from `rateLimitResetCredits.availableCount`;
its legacy `credits.remaining` individual-limit fallback is never recorded as a
balance. This is a count of reset credits, **not a USD balance**.
Unavailable/string-only balances are not persisted. A credit-only reading has
no `pct` field, so it cannot produce a fake zero-percent sparkline.

The writer uses a stable `flock` lock around append and retention, private cache
permissions, and atomic trimming through a unique temporary file. Recording is
best-effort: a cache write failure must not fail the provider refresh. The cache
remains `${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl/usage-history.jsonl`.

JSONL exports preserve the optional field. CSV exports append `credit_balance`
after `percent`; unavailable values are empty, not zero. Consumers that assume
exactly four CSV columns need to accept the additional column. The history
reader tolerates malformed lines and returns only numeric percentage readings.
`tests/test-credit-history.sh` covers balance zero, unavailable balance,
concurrent appends, retention, and exports without accessing real accounts.

Codex now emits `windowMinutes` without an English `resetDescription`, letting
the existing widget window-label translations choose the label in every locale.
