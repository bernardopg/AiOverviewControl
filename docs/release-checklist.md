# Release checklist

Deliver through a PR, verify main CI, then push an immutable release tag. The
published notes must describe the release, not merely contain its heading. See
[repository rules](repository-rules.md) for the protected-branch/check contract.

## 1. Scope and version

- Inspect `git status`, fetch origin/tags and preserve unrelated changes.
- Branch from the intended source head; do not push feature work directly to main.
- Choose semver: patch for fixes, minor for features, major for breaking contracts.
- Change the version in **plugin.json only**; QML reads it dynamically.
- Confirm the tag and release do not already exist. Do not overwrite published tags.
- Move substantive Unreleased notes into `## X.Y.Z - YYYY-MM-DD`, leaving an empty
  `## Unreleased` heading. Organize user changes, maintenance, privacy/migration and
  validation limitations; link relevant guides. Document behavior changes together
  with their code, including updated translations.
- Validate the exact section and PR delta:

```bash
scripts/check-changelog
scripts/check-changelog --base origin/main
VERSION="$(jq -r .version plugin.json)"
scripts/check-changelog --notes --repository OWNER/REPO --tag "v$VERSION"
```

## 2. Local gates

```bash
scripts/check-metadata
find providers -type f -print0 | xargs -0 -n 1 bash -n
find providers -type f -print0 | xargs -0 shellcheck -S warning
find tests -name '*.sh' -print0 | xargs -0 -n 1 bash -n
shellcheck -S warning tests/*.sh scripts/package-release scripts/render-contributors \
  scripts/check-metadata scripts/reload-plugin .githooks/pre-push
for test in tests/*.sh; do bash "$test"; done
QT_FORCE_STDERR_LOGGING=1 qmllint *.qml
actionlint
for f in i18n/*.json; do jq -e . "$f" >/dev/null; done
git diff --check
```

The metadata gate checks locale key/placeholder parity, executable entrypoints,
registered integration suites and release notes. Sourced native `.bash` modules
need syntax/lint/packaging checks, not executable permissions.

- If QML interactions changed, materialize DMS imports with `scripts/qmlls-setup`
  and run `AIOC_TEST_POINTER=1 tests/test-widget-runtime.sh`. It briefly opens a
  fixture window. CI runs the same suite under headless sway against a pinned
  DankMaterialShell checkout and fails rather than skipping.
- Reload with `scripts/reload-plugin` (discovers the live instance). Check the
  popout, both version pills, settings, empty/error cards, expanded analytics,
  currency fallback and pin ordering as applicable. Keep credentials out of logs.
- Commit before `scripts/package-release`: archives come from HEAD. When testing
  uncommitted candidates, use an isolated Git snapshot so those files are included.
  Verify zip/tar.gz/checksums, including dashboard, formatter, native modules and
  the archived nonempty changelog. `dist/` is ignored; do not publish local files
  as a substitute for the tag workflow's artifacts.

## 3. PR and protected merge

- Commit task changes using Conventional Commits, without AI co-author trailers.
- Push the feature/release branch and open a PR against main with scope, migration,
  testing and explicit limitations. Reference the release guide and changelog.
- Confirm the live rulesets match `.github/repository-rules/*.json`, with no bypass.
- Wait for **all required checks on the exact PR head**, including Changelog
  integrity. Resolve review conversations and any real findings before merging.
- If base/main advanced, update the branch and revalidate. Never disable a check
  or use an admin merge to work around missing notes.
- Merge the verified head via the PR. Record its merge SHA and fetch main; wait for
  its new main push CI as well. The release workflow will repeat full CI on the tag.

```bash
gh pr checks PR_NUMBER --watch
# Merge only the reviewed SHA, after the required checks have passed.
gh pr merge PR_NUMBER --merge --match-head-commit PR_HEAD_SHA
git fetch origin main
MAIN_SHA="$(git rev-parse origin/main)"
# Identify the CI push run for MAIN_SHA and await its successful conclusion.
gh run list --workflow CI --commit "$MAIN_SHA" --json databaseId,headSha,status,conclusion
```

## 4. Tag and publish

- The manifest version, release notes and tag must agree exactly.
- Create the annotated `vX.Y.Z` tag on the verified main merge SHA, never on an
  unmerged feature commit. Push only that new tag.
- Await the Release workflow. It rejects a tag outside main ancestry, mismatched
  manifest or empty notes, runs reusable CI and publishes validated notes plus
  `.zip`, `.tar.gz` and `.sha256` assets. Generated notes are disabled: the
  changelog section is the authoritative body.

```bash
git tag -a "v$VERSION" "$MAIN_SHA" -m "v$VERSION"
git push origin "v$VERSION"
gh run list --workflow Release --commit "$MAIN_SHA" --json databaseId,status,conclusion
# gh run watch RELEASE_RUN_ID --exit-status
```

## 5. Independent published-artifact verification

- Check the release is published, the tag resolves to the verified merge SHA and
  the body matches `scripts/check-changelog --notes --repository OWNER/REPO --tag`.
- Download all three assets to a fresh directory, verify SHA-256 and inspect their
  archived manifest/version and nonempty changelog. Check that new modules and
  assets are actually present, not just listed in source documentation.

```bash
DOWNLOAD="$(mktemp -d)"
gh release download "v$VERSION" --dir "$DOWNLOAD"
(cd "$DOWNLOAD" && sha256sum -c "AiOverviewControl-v$VERSION.sha256")
gh release view "v$VERSION" --json tagName,isDraft,isPrerelease,body,assets,url
```

- Finish with PR/release links, commit/tag, CI evidence, checksum result and any
  SKIP/manual-coverage limitations. Do not label a release perfect because a
  workflow merely queued; publication and downloaded assets must be verified.
- Update the plugin registry when its accepted metadata format is available.
