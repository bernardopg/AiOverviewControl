# Installation

## Install from the DMS plugin store

The simplest path: install **AiOverviewControl** through DMS's built-in plugin store. Store installs land under the manifest id — note the lowercase leading `a`:

```text
~/.config/dms/plugins/aiOverviewControl
```

Manual installs (the two methods below) use the `AiOverviewControl`
display-name casing instead. Linux paths are case-sensitive, so when following
[troubleshooting](./troubleshooting.md), adjust its `PLUGIN=` line to whichever
directory `ls ~/.config/dms/plugins` actually shows.

## Install from a checkout

Run this from the checkout root. Copy **all** root `.qml` files and the
`scripts/` directory, not a hand-picked subset: `qmldir` resolves the root QML
components by name, and `providers/get-local-analytics` reads
`scripts/local-analytics.jq`. A partial copy loads but fails at runtime.

```bash
PLUGIN="$HOME/.config/dms/plugins/AiOverviewControl"
mkdir -p "$PLUGIN"
cp -a ./*.qml ./*.js plugin.json qmldir providers scripts assets \
  README.md CHANGELOG.md LICENSE docs i18n screenshot.png \
  "$PLUGIN"/
chmod +x "$PLUGIN"/providers/get-*
dms restart
```

## Install from a release archive

Download one release archive and the release's `.sha256` file from the project's GitHub Releases page. The checksum file contains entries for both archive formats, so filter it to the file you actually downloaded:

```bash
ARCHIVE=AiOverviewControl-vX.Y.Z.tar.gz
CHECKSUM=AiOverviewControl-vX.Y.Z.sha256
grep "  ${ARCHIVE}$" "$CHECKSUM" | sha256sum --check --strict

PLUGIN="$HOME/.config/dms/plugins/AiOverviewControl"
mkdir -p "$PLUGIN"
tar -xzf "$ARCHIVE" -C "$PLUGIN" --strip-components=1
chmod +x "$PLUGIN"/providers/get-*
dms restart
```

Replace `vX.Y.Z` with the version you downloaded. For a `.zip` release, verify and unpack through a temporary directory so the archive's top-level `AiOverviewControl-vX.Y.Z` directory is not nested inside the plugin directory:

```bash
ARCHIVE=AiOverviewControl-vX.Y.Z.zip
CHECKSUM=AiOverviewControl-vX.Y.Z.sha256
grep "  ${ARCHIVE}$" "$CHECKSUM" | sha256sum --check --strict

PLUGIN="$HOME/.config/dms/plugins/AiOverviewControl"
tmpdir="$(mktemp -d)"
unzip -q "$ARCHIVE" -d "$tmpdir"
mkdir -p "$PLUGIN"
cp -a "$tmpdir"/AiOverviewControl-v*/. "$PLUGIN"/
rm -rf "$tmpdir"
chmod +x "$PLUGIN"/providers/get-*
dms restart
```

## Core dependencies

DMS **2.0 or newer** is required (`requires_dms: ">=2.0.0"` in `plugin.json`); DMS 1.x
reports the plugin as incompatible instead of loading it. Stay on
[1.22.0](https://github.com/bernardopg/AiOverviewControl/releases/tag/v1.22.0), the last
release for DMS 1.6, until your distribution ships DMS 2.0.

DMS 2.0 moved its directories from `DankMaterialShell` to `dms`
(`~/.config/dms`, `~/.local/state/dms`, `~/.cache/dms`) and leaves a symlink at each old
path, so an existing checkout under `~/.config/DankMaterialShell/plugins` keeps working.

```bash
command -v bash
command -v jq
command -v curl
```

Only enabled providers need their provider-specific CLI or credentials. Antigravity can use the `agy` CLI token file at `~/.gemini/antigravity-cli/antigravity-oauth-token`, `secret-tool` for keyring sessions, or `sqlite3` for IDE state databases. Hermes and 9Router read local SQLite databases, so they also need `sqlite3` (`~/.hermes/state.db` is opened read-only while the Hermes gateway keeps using it). Desktop quota notifications need `flock`; `notify-send` (libnotify) is optional and adds in-place updates, urgency and click-to-focus, otherwise alerts go through `dms notify`.

## Initial authentication

```bash
codex login
claude auth status
gh auth login
```

These commands are optional unless the matching provider is selected.

## First validation

```bash
cd ~/.config/dms/plugins/AiOverviewControl
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-codex-usage | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
```

Then enable the plugin in DMS settings and add the widget to the desired DankBar section.

## Upgrade

Replace the installed plugin files using either method above, preserve the DMS settings store, restore executable bits, and restart DMS:

```bash
chmod +x ~/.config/dms/plugins/AiOverviewControl/providers/get-*
dms restart
```

Version 1.3 ignores obsolete aggregation settings from earlier releases; they can be removed from the DMS plugin data store if desired.
