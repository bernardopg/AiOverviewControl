# Contributing to AiOverviewControl

Thanks for helping improve the plugin. This guide covers the local dev loop, the
CI gates you must satisfy, and the QML/shell gotchas that have bitten us before.

## Project layout

| Path | Purpose |
| --- | --- |
| `AiOverviewControlWidget.qml` | Main UI — dankbar pill + popout dashboard. |
| `AiOverviewControlSettings.qml` | Plugin settings page. |
| `AiOverviewControlI18n.qml` | Locale loading + string interpolation (singleton). |
| `i18n/*.json` | Translation bundles (`en` is the source of truth). |
| `providers/get-*` | One adapter per provider; `get-provider-usage` dispatches. |

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
  qmllint *.qml 2>&1 | grep -vE "qs\.|was not found|Unqualified|import"
  ```

## Providers

- Each `providers/get-<id>-usage` stub `exec`s `get-provider-wrapper <id>`,
  which calls into `get-provider-usage`'s `fetch_provider()` dispatch. A case is
  `canonical|alias1|alias2)`; the **first** token is the canonical provider that
  owns a stub, the rest are documented aliases.
- Scripts must be executable (`chmod +x`) and pass `shellcheck`.

## CI gates (run these locally before pushing)

| Gate | Local command |
| --- | --- |
| `plugin.json` valid + semver | `jq -e . plugin.json` |
| i18n JSON valid | `for f in i18n/*.json; do jq -e . "$f"; done` |
| **i18n key parity** (all locales == `en`) | `diff <(jq -r 'keys[]' i18n/en.json | sort) <(jq -r 'keys[]' i18n/pt_BR.json | sort)` |
| CHANGELOG has the `plugin.json` version | `grep "## $(jq -r .version plugin.json)" CHANGELOG.md` |
| **QML lint (hard gate)** | `qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml ProviderLogo.qml` |
| Shell lint | `shellcheck providers/get-*` |

Parity is strict: every key in `en.json` must exist in `pt_BR`, `zh_CN`,
`es_ES`, and `de_DE`, and vice versa. Prefer `t("key", "English fallback")`
calls so a missing translation degrades gracefully, but the key must still be
present in all five bundles.

## Release

See [`docs/release-checklist.md`](docs/release-checklist.md). In short: bump
`plugin.json` (patch for fixes/UI, minor for features), add a `CHANGELOG.md`
entry, commit, push `main`, wait for **green CI**, then tag `vX.Y.Z` (the tag
must equal the `plugin.json` version — `release.yml` validates it) and push the
tag to trigger the release build.
