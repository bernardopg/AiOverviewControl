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

The hook checks the current working tree's metadata and, when `gitleaks` is
installed, scans only the commits being pushed for secrets. It is a
fast safeguard, **not** a replacement for the integration, shellcheck,
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

## Security scans

`.github/workflows/security.yml` runs on every PR, push to `main` and weekly:

- **Secret scan**: gitleaks over the full Git history with redacted output, then
  TruffleHog reporting only credentials their issuer still accepts.
- **Workflow security audit**: zizmor over `.github/workflows`, failing on
  medium or higher findings.

Both are required checks on `main`. Reproduce them locally before pushing
workflow or fixture changes:

```bash
gitleaks git --no-banner --redact .
trufflehog git file://. --results=verified --fail --no-update
GH_TOKEN="$(gh auth token)" zizmor --min-severity=medium .github/workflows
```

Test fixtures must use obviously fake values (`fixture-work`, `offline-lint-placeholder`)
that match no real credential format. If gitleaks flags a fixture, change the
fixture rather than adding an allowlist. `scorecard.yml` publishes the OpenSSF
Scorecard weekly and on branch-protection changes, and the Release workflow
attests build provenance for the published archives (see
[SECURITY.md](../.github/SECURITY.md#verifying-a-release)).

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
The entry point is also compiled through DMS-style cache-busted `file://...?...`
URLs. It exercises the remaining-quota toggle, both pills, independent Claude
profiles through actual refresh/retry processes, per-profile analytics, a separate
Claude Code details panel per profile and window selection, settings reconstruction/persistence, removal/override cleanup and reset
with both features enabled together. Translation-load errors fail the suite.
Use `scripts/qmlls-setup` first, or supply the import-tree parent with
`AIOC_DMS_IMPORTS`. It needs a native Wayland connection because Qt offscreen
cannot construct DMS PanelWindow types; without these prerequisites it reports
**SKIP** locally. CI makes it mandatory: the `qml-runtime` job checks out
DankMaterialShell at a pinned tag (with its `dank-qml-common` submodule), builds
the import tree with `scripts/qmlls-setup`, starts headless sway
(`WLR_BACKENDS=headless`, pixman renderer) and runs the suite, including the
pointer-drag pass, with `AIOC_REQUIRE_NATIVE_UI=1` so a missing prerequisite
fails instead of skipping. Bump the pinned DMS ref when the plugin targets a
newer DMS.

See [refactoring.md](refactoring.md) for the controller/dashboard/native-adapter
boundaries and [currency.md](currency.md) for monetary units and network policy.
Lint of all root QML files and recursive syntax/ShellCheck of `providers/` remain
mandatory.

## Running DMS discovery

Use `scripts/reload-plugin` rather than guessing a config path. `dms run` can
launch Quickshell under `/run/user/<uid>/dms-shell/<hash>` (DMS 2.x;
`danklinux-shell/<hash>` on 1.x), not `~/.config/quickshell/dms`. The script discovers running instances via
`qs list --all`, queries each plugin IPC target, and reloads only shells where
the plugin is loaded. It never enables intentionally disabled plugins.
Before contacting the running shell for `aiOverviewControl`, the helper validates
manifest/translation JSON, component/qmldir/JavaScript file availability and the
absence of merge conflicts in runtime source. A rejected checkout leaves the live
widget untouched. `tests/test-dms-reload.sh` checks this fail-closed behavior,
discovery and failure handling using a fake qs.

A Quickshell process started before a new QML/JavaScript dependency was installed
may reject a cache-busted reload with **File name case mismatch**, even when the
same code compiles in a fresh process. Restart DMS once (`dms restart`) after such
an upgrade. A second normal load can reuse the old compiled component, so a
successful fallback is not proof that the new features are running. After the
restart, verify plugin status and repeat the reload; reopen any old popout.

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

## Fuzzing

`tests/fuzz/fuzz_provider_responses.py` is an [atheris](https://github.com/google/atheris)
harness: it serves arbitrary HTTP statuses and bodies through a fake `curl` to
every API-key adapter and fails when the dispatcher does not return exactly
one well-formed result or when the fake credential appears in the output.

```bash
python3 -m venv /tmp/fuzz-venv
/tmp/fuzz-venv/bin/pip install --no-deps --require-hashes -r tests/fuzz/requirements.txt
/tmp/fuzz-venv/bin/python tests/fuzz/fuzz_provider_responses.py -max_total_time=60
```

`tests/fuzz/fuzz_local_readers.py` does the same for files read from disk: a
Claude Code transcript or `.credentials.json`, a Codex or pi session log, an
OpenCode message row (SQLite), the Grok CLI `auth.json` and the Cline CLI
`providers.json`. It fails on a non-zero exit, output the widget cannot parse
(Claude's `KEY=VALUE` lines included), a leaked credential, or a credential on
curl's command line. Run it the same way, with `fuzz_local_readers.py`.

The **Fuzz provider responses** job runs both harnesses directly, and the
**ClusterFuzzLite** workflow runs the same harnesses packaged by
`.clusterfuzzlite/build.sh`. To reproduce the ClusterFuzzLite build locally:

```bash
docker build -t aioc-cflite -f .clusterfuzzlite/Dockerfile .
docker run --rm -e SANITIZER=address -e FUZZING_LANGUAGE=python -e FUZZING_ENGINE=libfuzzer \
  -e ARCHITECTURE=x86_64 -v "$PWD/out:/out" aioc-cflite compile
```
||||||| parent of 2bcc33c (test: raise shell statement coverage to 80% and enforce it in CI)

## Statement coverage

`scripts/coverage [OUTPUT_DIR]` runs every non-QML `tests/test-*.sh` suite
under [kcov](https://github.com/SimonKagstrom/kcov), merges the runs and prints
statement coverage of `providers/` and `scripts/`, with a per-file table in
`OUTPUT_DIR/files.tsv` (default `./coverage/`, ignored by git). Set
`AIOC_COVERAGE_MIN=80` to fail below 80%, as the **Statement coverage** CI job
does.

kcov's own percentage counts every physical line, including the body of a
multi-line jq or awk program, a heredoc body and a backslash-continued line.
Those lines belong to the statement that starts above them and are never
reported as executed, so `scripts/coverage-report` drops them and counts a
statement as covered when its first line ran
(`tests/test-coverage-report.sh` pins this). The jq programs themselves are
exercised by the fixture assertions, not measured line by line.

Coverage suites must not clear the environment (`env -i`) or unset
`BASH_ENV`: kcov traces child `bash` processes through it. Capture a
command's output before `grep -q` instead of piping into it; under kcov the
early pipe close turns into an `EPIPE` failure with `pipefail`.
