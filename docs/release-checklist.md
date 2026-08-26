# Release checklist

CI and the release workflow enforce the checks explicitly noted below; the
functional smoke test and publishing sequence remain manual. Work top to bottom —
the tag push is the last action.

## 0. Preflight

- [ ] Start from a clean, current `main`; do not release a local-only commit or
  an already-published tag:

  ```bash
  git status --short --branch
  git fetch origin
  git pull --ff-only origin main
  git describe --tags --abbrev=0
  git log --oneline "$(git describe --tags --abbrev=0)..HEAD"
  ```

- [ ] Choose the semantic version deliberately: patch for fixes/UI-only changes,
  minor for features, major only for breaking behavior. Confirm the target tag
  does not already exist with `git rev-parse -q --verify "refs/tags/vX.Y.Z"`
  and `gh release view vX.Y.Z` (both must report absent).

## 1. Version bump

- [ ] `plugin.json` → `version` (release workflow rejects a tag that differs). This is the **only** place a release version is written: the Settings hero pill and the popout header pill both read `plugin.json` at runtime, and `providers/get-codex-usage` reads it for `clientInfo.version`.
- [ ] Confirm the QML still sources the version dynamically (CI enforces both greps):

  ```bash
  VERSION="$(jq -r .version plugin.json)"
  printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
  grep -qF 'text: "v" + root.pluginVersion' AiOverviewControlSettings.qml
  grep -qF '"/plugin.json"' AiOverviewControlWidget.qml
  ```

## 2. Changelog

- [ ] Move `Unreleased` content into a new `## 1.x.y - YYYY-MM-DD` section (release workflow requires the entry).
- [ ] Leave an empty `## Unreleased` heading on top.

## 3. Local validation (core CI-equivalent checks)

```bash
git diff --check
jq --exit-status . plugin.json >/dev/null
VERSION="$(jq -r .version plugin.json)"
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
grep -qF "## ${VERSION}" CHANGELOG.md || grep -qF "## [${VERSION}]" CHANGELOG.md
find providers -maxdepth 1 -type f -print0 | xargs -0 bash -n
for test in tests/*.sh; do bash -n "$test"; done
bash -n scripts/package-release
shellcheck -S warning providers/* tests/*.sh scripts/package-release
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml ProviderLogo.qml
for f in i18n/*.json; do jq -e . "$f" >/dev/null; done
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
./providers/get-usage-history | jq .
for test in tests/*.sh; do bash "$test"; done
scripts/package-release
```

The generated `dist/` directory is ignored by Git.

- [ ] i18n parity: every locale has exactly the keys of `i18n/en.json` (CI enforces exact parity; the release workflow rejects missing keys; locales: pt_BR, zh_CN, es_ES, de_DE).
- [ ] All provider, test, and packaging scripts are executable (CI and the release workflow enforce).
- [ ] Run `actionlint -color` if installed. CI always runs the pinned actionlint binary.
- [ ] Inspect the generated `dist/` filenames and checksum manifest; the tag
  workflow rebuilds these artifacts from the immutable tag, so do not upload a
  locally built archive manually.

CI also runs fixture-backed integration contracts, provider dispatch coverage,
QML script-reference checks, Crowdin configuration checks, and packaging. Do
not describe the local smoke commands above as a substitute for a green CI run.

## 4. Functional smoke

- [ ] Reload the plugin and open the popout:
      `qs -p ~/.config/quickshell/dms ipc call plugins reload aiOverviewControl`
- [ ] Hero ring renders; provider cards expand; Claude card shows analytics.
- [ ] Local-telemetry cards render their expanded sections (pi, 9Router, Hermes) or hide them cleanly when the tool is not installed.
- [ ] Version pill shows the freshly bumped version in both the popout header and Settings (both read `plugin.json`).
- [ ] Settings opens without QML errors and health chips populate.
- [ ] If the release changes a provider, verify its card/icon and its documented
  credential/fallback state; do not use a real credential in logs or screenshots.

## 5. Commit, tag, push

Rules: no AI co-author trailers; tag must be `v` + `plugin.json` version.

```bash
git add -A && git commit
git push origin main
# Wait for the push CI on this exact commit before creating the tag.
HEAD_SHA="$(git rev-parse HEAD)"
RUN_ID="$(gh run list --workflow CI --commit "$HEAD_SHA" --limit 1 --json databaseId --jq '.[0].databaseId')"
test -n "$RUN_ID" && gh run watch "$RUN_ID" --exit-status
git tag -a v1.x.y -m "v1.x.y"
git push origin v1.x.y
```

The tag workflow re-runs the complete reusable CI gate at the tagged commit and only publishes after it passes. It also rejects tags that are not reachable from `main`.

## 6. Post-release

- [ ] Wait for the **Release** workflow to finish green; it reruns the complete
  reusable CI gate at the tag and then publishes `.zip`, `.tar.gz`, and
  `.sha256`:

  ```bash
  gh run list --workflow Release --limit 1
  gh run watch RUN_ID --exit-status
  ```

- [ ] Verify the published release targets the tag and independently validate
  the downloaded artifacts against the published checksum manifest:

  ```bash
  gh release view v1.x.y
  mkdir -p /tmp/AiOverviewControl-v1.x.y
  gh release download v1.x.y --dir /tmp/AiOverviewControl-v1.x.y
  (cd /tmp/AiOverviewControl-v1.x.y && sha256sum -c AiOverviewControl-v1.x.y.sha256)
  ```

- [ ] Update DMS plugin registry listing when the registry format is finalized (see TODO).
