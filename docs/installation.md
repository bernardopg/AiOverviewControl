# Instalacao

Este guia assume que o Dank Material Shell ja esta instalado e funcionando. O AiOverviewControl deve ficar inteiro em:

```text
~/.config/DankMaterialShell/plugins/AiOverviewControl
```

## 1. Copiar arquivos

Se voce esta no diretorio onde baixou ou editou o plugin:

```bash
cd /caminho/onde/baixou/AiOverviewControl
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml plugin.json get-* README.md CHANGELOG.md LICENSE docs screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
```

Arquivos esperados:

```text
AiOverviewControlWidget.qml
AiOverviewControlSettings.qml
plugin.json
get-claude-usage
get-copilot-usage
get-provider-usage
README.md
CHANGELOG.md
LICENSE
docs/
```

O plugin nao precisa de arquivos de outro plugin DMS. `codexbar` e uma integracao externa recomendada para Codex e providers sem adapter local.

## 2. Permissoes dos scripts

```bash
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-*
```

## 3. Dependencias

Instale ou confira:

```bash
command -v bash
command -v node
command -v jq
command -v curl
```

Para Copilot:

```bash
command -v gh
gh auth status
```

Para detalhes extras de Claude Code:

```bash
command -v claude
test -f ~/.claude/.credentials.json
test -d ~/.claude/projects
```

Para Codex e providers sem adapter local, confira tambem:

```bash
command -v codexbar
```

## 4. Reiniciar o DMS

```bash
dms restart
```

Depois:

1. Abra as configuracoes do Dank Material Shell.
2. Entre em Plugins.
3. Habilite **AiOverviewControl**.
4. Adicione o widget a uma secao da DankBar.

## 5. Teste inicial recomendado

Antes de abrir muitos providers, valide Codex, Claude e Copilot:

```bash
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage "$(command -v codexbar)" "codex,claude,copilot" "cli" ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
```

Se esses comandos retornarem JSON ou pares `CHAVE=valor`, a camada de coleta esta operacional. Se a UI continuar vazia, veja [troubleshooting.md](./troubleshooting.md).

## Atualizacao

Para atualizar sem perder configuracoes salvas no DMS:

```bash
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml plugin.json get-* README.md CHANGELOG.md LICENSE docs \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-*
dms restart
```

As preferencias do widget ficam no armazenamento de settings do DMS, nao nos arquivos do plugin.
