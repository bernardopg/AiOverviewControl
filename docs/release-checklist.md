# Release checklist

Every step is enforced or exercised by CI/release workflows where noted; the
rest is manual. Work top to bottom — the tag push is the last action.

## 1. Version bump

- [ ] `plugin.json` → `version` (release workflow rejects a tag that differs).
- [ ] `AiOverviewControlSettings.qml` → hero version pill (`v1.x.y`).
- [ ] `providers/get-codex-usage` → `clientInfo.version` in the initialize payload.
- [ ] Confirm all three match: `grep -rn "1\.x\.y" plugin.json AiOverviewControlSettings.qml providers/get-codex-usage`

## 2. Changelog

- [ ] Move `[Unreleased]` content into a new `## 1.x.y - YYYY-MM-DD` section (release workflow requires the entry).
- [ ] Leave an empty `## [Unreleased]` heading on top.

## 3. Local validation (mirrors CI)

```bash
jq . plugin.json
find providers -name 'get-*' -type f -print0 | xargs -0 bash -n
shellcheck -S warning providers/get-* providers/send-quota-alert
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml
for f in i18n/*.json; do jq -e . "$f" >/dev/null; done
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
./providers/get-usage-history | jq .
```

- [ ] i18n parity: every locale has exactly the keys of `i18n/en.json` (CI + release workflows enforce; locales: pt_BR, zh_CN, es_ES, de_DE).
- [ ] All `providers/get-*` files are executable (release workflow enforces).

## 4. Functional smoke

- [ ] Reload the plugin and open the popout:
      `qs -p ~/.config/quickshell/dms ipc call plugins reload aiOverviewControl`
- [ ] Hero ring renders; provider cards expand; Claude card shows analytics.
- [ ] Settings opens without QML errors and health chips populate.

## 5. Commit, tag, push

Rules: no AI co-author trailers; tag must be `v` + `plugin.json` version.

```bash
git add -A && git commit
git push origin main
git tag v1.x.y
git push origin v1.x.y
```

## 6. Post-release

- [ ] Release workflow green; GitHub release has `.zip`, `.tar.gz`, `.sha256` assets.
- [ ] `gh release view v1.x.y` sanity check.
- [ ] Update DMS plugin registry listing when the registry format is finalized (see TODO).
