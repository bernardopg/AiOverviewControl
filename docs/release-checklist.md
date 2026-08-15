# Release checklist

CI and the release workflow enforce the checks explicitly noted below; the
functional smoke test and publishing sequence remain manual. Work top to bottom —
the tag push is the last action.

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
jq --exit-status . plugin.json >/dev/null
VERSION="$(jq -r .version plugin.json)"
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
grep -qF "## ${VERSION}" CHANGELOG.md || grep -qF "## [${VERSION}]" CHANGELOG.mdfind providers -maxdepth 1 -type f -print0 | xargs -0 bash -n
for test in tests/*.sh; do bash -n "$test"; done
bash -n scripts/package-release
shellcheck -S warning providers/* tests/*.sh scripts/package-release
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml ProviderLogo.qml
for f in i18n/*.json; do jq -e . "$f" >/dev/null; done
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
./providers/get-usage-history | jq .
bash tests/test-hermes-analytics.sh
scripts/package-release
```

The generated `dist/` directory is ignored by Git.

- [ ] i18n parity: every locale has exactly the keys of `i18n/en.json` (CI enforces exact parity; the release workflow rejects missing keys; locales: pt_BR, zh_CN, es_ES, de_DE).
- [ ] All provider, test, and packaging scripts are executable (CI and the release workflow enforce).
- [ ] Run `actionlint -color` if installed. CI always runs the pinned actionlint binary.

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

## 5. Commit, tag, push

Rules: no AI co-author trailers; tag must be `v` + `plugin.json` version.

```bash
git add -A && git commit
git push origin main
git tag v1.x.y
git push origin v1.x.y
```

The tag workflow re-runs the complete reusable CI gate at the tagged commit and only publishes after it passes. It also rejects tags that are not reachable from `main`.

## 6. Post-release

- [ ] Release workflow green; GitHub release has `.zip`, `.tar.gz`, `.sha256` assets.
- [ ] `gh release view v1.x.y` sanity check.
- [ ] Update DMS plugin registry listing when the registry format is finalized (see TODO).
