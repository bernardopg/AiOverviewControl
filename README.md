# AiOverviewControl

![AiOverviewControl screenshot](./screenshot.png)

[![CI](https://img.shields.io/github/actions/workflow/status/bernardopg/AiOverviewControl/ci.yml?branch=main&label=CI&style=flat-square)](https://github.com/bernardopg/AiOverviewControl/actions)
[![Release](https://img.shields.io/github/v/tag/bernardopg/AiOverviewControl?label=Release&style=flat-square)](https://github.com/bernardopg/AiOverviewControl/releases)
[![License](https://img.shields.io/github/license/bernardopg/AiOverviewControl)](LICENSE)
[![Stars](https://img.shields.io/github/stars/bernardopg/AiOverviewControl?style=social)](https://github.com/bernardopg/AiOverviewControl/stargazers)
[![Issues](https://img.shields.io/github/issues/bernardopg/AiOverviewControl)](https://github.com/bernardopg/AiOverviewControl/issues)
[![Crowdin](https://badges.crowdin.net/aioverviewcontrol/localized.svg)](https://crowdin.com/project/aioverviewcontrol)

Telemetry panel for tracking usage, limits and reset windows of AI assistants inside Dank Material Shell (DMS).

AiOverviewControl is a self-contained DMS plugin that collects usage data from multiple AI providers (Copilot, Claude, Codex and others), displays the most-limited provider in the DankBar, and exposes a floating dashboard with per-provider cards.

Table of Contents

- [AiOverviewControl](#aioverviewcontrol)
  - [Features](#features)
  - [Quick Start](#quick-start)
  - [Installation](#installation)
  - [Configuration](#configuration)
  - [Providers](#providers)
    - [Provider Summary Table](#provider-summary-table)
  - [Validation \& Debugging](#validation--debugging)
  - [Architecture](#architecture)
  - [Troubleshooting](#troubleshooting)
  - [Contributing](#contributing)
  - [License](#license)
  - [Português (PT-BR)](#português-pt-br)
  - [O que ele mostra](#o-que-ele-mostra)
  - [Requisitos](#requisitos)
  - [Instalacao rapida](#instalacao-rapida)
  - [Configuracao recomendada](#configuracao-recomendada)
  - [Providers](#providers-1)
  - [Validacao local](#validacao-local)
  - [Arquitetura](#arquitetura)
  - [Troubleshooting curto](#troubleshooting-curto)
  - [Licenca](#licenca)

## Features

- Compact DankBar indicator showing the provider closest to quota limits
- Floating dashboard with per-provider cards, progress bars and isolated error states
- Visual controls to add/remove providers without manual JSON edits
- Per-provider collection to avoid a single provider failure hiding others
- Local helper scripts for Copilot, Claude and Codex fallbacks

## Quick Start

Copy the plugin directory into your DMS plugins directory and enable the plugin in the DMS settings, then add the widget to a DankBar section.

```bash
cd /path/to/downloaded/AiOverviewControl
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml plugin.json get-* README.md CHANGELOG.md LICENSE docs screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-*
dms restart
```

Full installation guide: [docs/installation.md](./docs/installation.md)

## Installation

See [docs/installation.md](./docs/installation.md) for step-by-step instructions and platform-specific notes.

## Configuration

Recommended defaults for Linux:

- Provider Set: `codex,claude,copilot`
- Source Mode: `cli`
- Show Provider Errors: `true` (useful while adding providers)
- Refresh Interval: `120000` or `300000` (ms)

The `cli` source mode relies on a `codexbar` fallback for providers that expose CLI usage. Local helpers included in this plugin provide extra coverage for Copilot, Claude Code, Gemini and OpenRouter.

Configuration reference: [docs/configuration.md](./docs/configuration.md)

## Providers

Supported provider IDs (recognized by the plugin): `codex`, `claude`, `copilot`, `gemini`, `openrouter`, `perplexity`, `cursor`, `kilo`, `kiro`, `ollama`, `warp`, `amp`.

Support depends on two factors:

- Local bridges included in this directory
- Providers available via fallback `codexbar` CLI

Practical provider matrix: [docs/providers.md](./docs/providers.md)

### Provider Summary Table

| Provider ID                  | Notes                                                    |
| ---------------------------- | -------------------------------------------------------- |
| codex                        | Fallback via `codexbar` CLI.                             |
| claude                       | Local analytics via `get-claude-usage`.                  |
| copilot                      | Local bridge `get-copilot-usage` (requires GitHub auth). |
| gemini / openrouter / others | Covered by helpers or `codexbar` when configured.        |

## Validation & Debugging

Use these commands to isolate environment, auth and UI issues:

```bash
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage "$(command -v codexbar)" "codex,claude,copilot" "cli" ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml || true
```

If a provider prints data in the terminal but not in the panel, see [docs/troubleshooting.md](./docs/troubleshooting.md).

## Architecture

Key files and responsibilities:

- `plugin.json` — plugin metadata and capabilities
- `AiOverviewControlWidget.qml` — the DankBar pill, popout and collection normalization
- `AiOverviewControlSettings.qml` — DMS-exposed settings UI
- `get-provider-usage` — unified local backend for providers and fallbacks
- `get-copilot-usage` — local bridge to GitHub Copilot usage
- `get-claude-usage` — Claude Code analytics and optional OAuth usage

Technical overview: [docs/architecture.md](./docs/architecture.md)

## Troubleshooting

- Codex shows no data: install `codexbar` or set a fallback absolute path
- Copilot shows no data: run `gh auth login` and ensure `gh auth token` exists
- Claude missing extra details: ensure `claude --version`, `jq`, `curl` and `~/.claude/.credentials.json` are present
- Gemini/OpenRouter errors: run `get-provider-usage`, configure local keys and keep Show Provider Errors enabled
- Too many providers visible: remove failing providers or use a smaller custom list

## Contributing

Contributions are welcome. Please open issues or PRs and follow repository guidelines. For development notes and how to run local checks, see the repository docs.

## License

See [LICENSE](./LICENSE)

---

## Português (PT-BR)

Painel de telemetria para acompanhar uso, limites e janelas de reset de assistentes de IA dentro do Dank Material Shell.

O plugin foi feito para ser autocontido: todos os arquivos de interface, configuracao e scripts auxiliares ficam neste diretorio. Ele nao depende de outro plugin como `codexbar`. O executavel `codexbar` e usado como fallback para Codex e providers compativeis, mas os helpers locais cobrem Copilot, Claude, Gemini e OpenRouter quando ha credenciais disponiveis.

![AiOverviewControl](./screenshot.png)

## O que ele mostra

- Indicador compacto na DankBar com o provider mais perto do limite.
- Dashboard flutuante com cartoes por provider, barras de progresso e estados de erro isolados.
- Controle visual para adicionar ou remover providers sem editar JSON manualmente.
- Busca separada por provider, para que uma falha em Gemini, OpenRouter ou outro servico nao esconda Codex, Claude ou Copilot funcionando.
- Copilot via script local `get-copilot-usage`, usando a autenticacao atual do GitHub.
- Claude com dados do CodexBar e painel extra de Claude Code:
  - uso de janela de 5 horas e 7 dias;
  - tokens da semana e do mes;
  - custo estimado a partir dos JSONL locais;
  - atividade diaria, mix de modelos, sessoes e mensagens.

## Requisitos

- Dank Material Shell rodando sobre Quickshell.
- `bash`, `node`, `jq` e `curl`.
- Recomendado: `codexbar` instalado como executavel de sistema, em `PATH`, `~/.local/bin`, `/usr/local/bin` ou no caminho configurado no plugin.
- `gh` para Copilot, ou token em `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` ou `GITHUB_TOKEN`.
- Opcional para detalhes de Claude Code: CLI `claude`, `~/.claude/.credentials.json` e logs locais em `~/.claude/projects`.

## Instalacao rapida

Copie o diretorio inteiro para a pasta de plugins do Dank Material Shell:

```bash
cd /caminho/onde/baixou/AiOverviewControl
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml plugin.json get-* README.md CHANGELOG.md LICENSE docs screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-*
dms restart
```

Depois abra as configuracoes do DMS, habilite **AiOverviewControl** e adicione o widget a uma secao da DankBar.

Guia completo: [docs/installation.md](./docs/installation.md).

## Configuracao recomendada

Para Linux, use:

- **Provider Set:** `codex,claude,copilot`
- **Source Mode:** `cli`
- **Show Provider Errors:** `true` enquanto estiver adicionando providers
- **Refresh Interval:** `120000` ou `300000`

Detalhes de cada opcao: [docs/configuration.md](./docs/configuration.md).

## Providers

O plugin conhece os IDs `codex`, `claude`, `copilot`, `gemini`, `openrouter`, `perplexity`, `cursor`, `kilo`, `kiro`, `ollama`, `warp` e `amp`.

O suporte real depende das pontes locais e do fallback `codexbar`.

Matriz pratica: [docs/providers.md](./docs/providers.md).

## Validacao local

Use estes comandos para separar problema de ambiente, autenticacao e UI:

```bash
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage "$(command -v codexbar)" "codex,claude,copilot" "cli" ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml
```

Se algo aparecer no terminal, mas nao no painel, veja [docs/troubleshooting.md](./docs/troubleshooting.md).

## Arquitetura

O widget e composto por:

- `plugin.json`: metadata, capacidades e requisitos.
- `AiOverviewControlWidget.qml`: DankBar pill, popout, processos de coleta e normalizacao visual.
- `AiOverviewControlSettings.qml`: configuracoes expostas pelo DMS.
- `get-provider-usage`: backend local unificado para providers e fallbacks.
- `get-copilot-usage`: ponte local para uso do GitHub Copilot.
- `get-claude-usage`: analytics local de Claude Code e consulta OAuth de uso Anthropic.

Visao tecnica: [docs/architecture.md](./docs/architecture.md).

## Troubleshooting curto

- **Codex sem dados**: instale `codexbar` ou configure **Optional fallback** com o caminho absoluto.
- **Copilot sem dados**: rode `gh auth login` e confirme `gh auth token`.
- **Claude sem detalhes extras**: confirme `claude --version`, `jq`, `curl` e `~/.claude/.credentials.json`.
- **Gemini/OpenRouter/etc. em erro**: teste `get-provider-usage`, configure as chaves locais quando existirem e mantenha **Show Provider Errors** ativo.

## Licenca

Veja [LICENSE](./LICENSE).
