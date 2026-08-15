# Installation

## Install from a checkout

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml \
  ProviderLogo.qml plugin.json qmldir providers assets README.md CHANGELOG.md LICENSE \
  docs i18n screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

## Install from a release archive

Download one release archive and the release's `.sha256` file from the project's GitHub Releases page. The checksum file contains entries for both archive formats, so filter it to the file you actually downloaded:

```bash
ARCHIVE=AiOverviewControl-v1.9.1.tar.gz
CHECKSUM=AiOverviewControl-v1.9.1.sha256
grep "  ${ARCHIVE}$" "$CHECKSUM" | sha256sum --check --strict

PLUGIN="$HOME/.config/DankMaterialShell/plugins/AiOverviewControl"
mkdir -p "$PLUGIN"
tar -xzf "$ARCHIVE" -C "$PLUGIN" --strip-components=1
chmod +x "$PLUGIN"/providers/get-*
dms restart
```

Replace `v1.9.1` with the version you downloaded. For a `.zip` release, verify and unpack through a temporary directory so the archive's top-level `AiOverviewControl-vX.Y.Z` directory is not nested inside the plugin directory:

```bash
ARCHIVE=AiOverviewControl-v1.9.1.zip
CHECKSUM=AiOverviewControl-v1.9.1.sha256
grep "  ${ARCHIVE}$" "$CHECKSUM" | sha256sum --check --strict

PLUGIN="$HOME/.config/DankMaterialShell/plugins/AiOverviewControl"
tmpdir="$(mktemp -d)"
unzip -q "$ARCHIVE" -d "$tmpdir"
mkdir -p "$PLUGIN"
cp -a "$tmpdir"/AiOverviewControl-v*/. "$PLUGIN"/
rm -rf "$tmpdir"
chmod +x "$PLUGIN"/providers/get-*
dms restart
```

## Core dependencies

```bash
command -v bash
command -v jq
command -v curl
```

Only enabled providers need their provider-specific CLI or credentials. Antigravity needs `secret-tool` for keyring sessions or `sqlite3` for IDE state databases. Hermes and 9Router read local SQLite databases, so they also need `sqlite3` (`~/.hermes/state.db` is opened read-only while the Hermes gateway keeps using it). Desktop quota notifications need `notify-send` and `flock`.

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

Replace the installed plugin files using either method above, preserve the DMS settings store, restore executable bits, and restart DMS:

```bash
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

Version 1.3 ignores obsolete aggregation settings from earlier releases; they can be removed from the DMS plugin data store if desired.
