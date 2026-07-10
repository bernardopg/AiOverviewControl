# Installation

## Install from a checkout

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml \
  plugin.json qmldir providers README.md CHANGELOG.md LICENSE docs i18n screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

## Install from a release archive

Download the release archive and its matching SHA-256 checksum from the project's GitHub Releases page. Verify it before replacing an existing installation:

```bash
sha256sum --check AiOverviewControl-*.sha256
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
tar -xzf AiOverviewControl-*.tar.gz -C ~/.config/DankMaterialShell/plugins/AiOverviewControl --strip-components=1
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

For a `.zip` release, verify the same checksum and replace the extraction command with `unzip AiOverviewControl-*.zip -d ~/.config/DankMaterialShell/plugins/AiOverviewControl`.

## Core dependencies

```bash
command -v bash
command -v jq
command -v curl
```

Only enabled providers need their provider-specific CLI or credentials.

## Initial authentication

```bash
codex login
claude auth status
gh auth login
```

These commands are optional unless the matching provider is selected.

## First validation

```bash
cd ~/.config/DankMaterialShell/plugins/AiOverviewControl
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-codex-usage | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
```

Then enable the plugin in DMS settings and add the widget to the desired DankBar section.

## Upgrade

Replace tracked plugin files, preserve the DMS settings store, restore executable bits, and restart DMS:

```bash
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

Version 1.3 ignores obsolete aggregation settings from earlier releases; they can be removed from the DMS plugin data store if desired.
