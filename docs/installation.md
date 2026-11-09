# Installation

## Install from the Dux Shell plugin store

The simplest path: install **AiOverviewControl** through the built-in plugin
store of [Dux Shell](https://github.com/duxlabs-dev/dux-shell) (formerly
Dux Shell), or with `dms plugins install aiOverviewControl`. Store installs land under the manifest id — note the lowercase leading `a`:

```text
~/.config/dms/plugins/aiOverviewControl
```

Manual installs (the two methods below) use the `AiOverviewControl`
display-name casing instead. Linux paths are case-sensitive, so when following
[troubleshooting](./troubleshooting.md), adjust its `PLUGIN=` line to whichever
directory `ls ~/.config/dms/plugins` actually shows.

## Install from a checkout

Run this from the checkout root. Copy **all** root `.qml` and `.js` files and
the `lib/` and `scripts/` directories, not a hand-picked subset: `qmldir`
resolves the root QML components by name, the widget and settings import
`lib/BarWindows.js` and `ClaudeProfiles.js`, and `providers/get-local-analytics`
reads `scripts/local-analytics.jq`. Without `lib/` the plugin does not load;
without `scripts/` it loads but local analytics fail at runtime.

```bash
PLUGIN="$HOME/.config/dms/plugins/AiOverviewControl"
mkdir -p "$PLUGIN"
cp -a ./*.qml ./*.js plugin.json qmldir lib detect providers scripts assets \
  README.md CHANGELOG.md LICENSE docs i18n translations screenshot.png \
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

Dux Shell **2.0 or newer** is required (`requires_dms: ">=2.0.0"` in
`plugin.json`; the key keeps the shell's former Dux Shell name). Each release is
tested against Dux Shell 2.1. DankMaterialShell 1.x reports the plugin as
incompatible instead of loading it: stay on
[1.22.0](https://github.com/bernardopg/AiOverviewControl/releases/tag/v1.22.0), the last
release for DMS 1.6, until your distribution ships Dux Shell 2.0.

DankMaterialShell became Dux Shell with 2.0. Its CLI is still `dms`, and it
moved its directories from `DankMaterialShell` to `dms` (`~/.config/dms`,
`~/.local/state/dms`, `~/.cache/dms`), leaving a symlink at each old path, so an
existing checkout under `~/.config/DankMaterialShell/plugins` keeps working.
Distribution packages are now named `dux-shell` (Arch's package replaces
`dms-shell`), and `dms migrate dux` (2.1+) moves an install from the legacy
AvengeMedia package repositories to the Dux Labs ones. None of this changes the
plugin directory or its settings.

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
./providers/get-provider-usage "codex,claude,copilot" | jq .
./providers/get-copilot-usage | jq .
```

Then enable the plugin in Dux Shell settings (**Settings → Plugins**) and add the
widget to a bar section (**Settings → Bars**).

## Upgrade

Replace the installed plugin files using either method above, preserve the shell's plugin settings store, restore executable bits, and restart the shell:

```bash
chmod +x ~/.config/dms/plugins/AiOverviewControl/providers/get-*
dms restart
```

Version 1.3 ignores obsolete aggregation settings from earlier releases; they can be removed from the shell's plugin data store if desired.
