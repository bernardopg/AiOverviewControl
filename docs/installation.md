# Installation

This guide assumes Dank Material Shell is already installed and working. The plugin should reside in:

```text
~/.config/DankMaterialShell/plugins/AiOverviewControl
```

## 1. Copy files

If you are in the directory where you downloaded or edited the plugin:

```bash
cd /path/to/downloaded/AiOverviewControl
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml \
  plugin.json qmldir providers README.md CHANGELOG.md LICENSE docs i18n screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
```

Expected files:

```text
AiOverviewControlWidget.qml
AiOverviewControlSettings.qml
AiOverviewControlI18n.qml
plugin.json
qmldir
providers/
README.md
CHANGELOG.md
LICENSE
docs/
i18n/
```

The plugin does not require files from other DMS plugins. `codexbar` is an optional external integration recommended for Codex and providers without a local adapter.

## 2. Make scripts executable

```bash
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-*
```

## 3. Dependencies

Install or verify the following binaries are available:

```bash
command -v bash
command -v node
command -v jq
command -v curl
```

For Copilot:

```bash
command -v gh
gh auth status
```

For extra Claude details:

```bash
command -v claude
test -f ~/.claude/.credentials.json
test -d ~/.claude/projects
```

For Codex and providers without local adapters:

```bash
command -v codexbar
```

## 4. Restart DMS

```bash
dms restart
```

Then:

1. Open Dank Material Shell settings.
2. Go to Plugins.
3. Enable **AiOverviewControl**.
4. Add the widget to a DankBar section.

## 5. Initial smoke tests

Before enabling many providers, validate Codex, Claude and Copilot:

```bash
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-provider-usage "$(command -v codexbar)" "codex,claude,copilot" "cli" ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-claude-usage
```

If those commands return JSON or KEY=VALUE pairs the collection layer is operational. If the UI remains empty, see [troubleshooting.md](./troubleshooting.md).

## Upgrading

To upgrade without losing DMS-saved settings:

```bash
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml \
  plugin.json qmldir providers README.md CHANGELOG.md LICENSE docs i18n \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

Widget preferences are stored in the DMS settings store, not in plugin files.

---

# Instalacao (PT-BR)

As instrucoes em Portugues estao preservadas acima como referencia. Siga os passos em ingles caso prefira.
