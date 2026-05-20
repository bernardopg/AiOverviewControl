<div align="center">

<img width="100%" alt="AiOverviewControl" src="https://capsule-render.vercel.app/api?type=wave&color=0:0F172A,45:2563EB,100:22C55E&height=220&section=header&text=AiOverviewControl&fontSize=52&fontColor=FFFFFF&animation=fadeIn&fontAlignY=36&desc=Telemetria%20de%20uso%20de%20IA%20para%20Dank%20Material%20Shell&descSize=18&descAlignY=58" />

[![CI](https://img.shields.io/github/actions/workflow/status/bernardopg/AiOverviewControl/ci.yml?branch=main&label=CI&style=flat-square)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/tag/bernardopg/AiOverviewControl?label=Release&style=flat-square)](https://github.com/bernardopg/AiOverviewControl/releases)
[![License](https://img.shields.io/github/license/bernardopg/AiOverviewControl?style=flat-square)](../LICENSE)
[![Crowdin](https://badges.crowdin.net/aioverviewcontrol/localized.svg)](https://crowdin.com/project/aioverviewcontrol)

**Widget autocontido para Dank Material Shell que monitora uso, limites, janelas de reset e saúde de providers de IA.**

[English](../README.md) · [Português do Brasil](README.pt-BR.md) · [Documentação](#-documentação) · [Abrir issue](https://github.com/bernardopg/AiOverviewControl/issues/new/choose)

</div>

---

## ✨ O Que Ele Faz

O AiOverviewControl adiciona um painel de telemetria ao Dank Material Shell (DMS). Ele acompanha múltiplos providers de IA, destaca na DankBar o provider mais perto do limite e abre um dashboard detalhado com cartões individuais de uso.

O plugin foi desenhado para continuar útil mesmo quando um provider falha: cada provider é coletado separadamente, então uma falha em Gemini, OpenRouter, Copilot ou Claude não esconde os providers que estão funcionando.

![AiOverviewControl](../screenshot.png)

## 🚀 Destaques

- 📊 **Indicador compacto na DankBar** mostrando o provider mais perto do limite.
- 🧩 **Dashboard flutuante** com cartões, barras de progresso, janelas de reset e erros isolados.
- 🛠️ **Helpers locais autocontidos** para Copilot, Claude Code, fallbacks de Codex e providers compatíveis.
- ⚙️ **Controles visuais de provider** para adicionar ou remover providers sem editar JSON manualmente.
- 🌍 **Traduções via Crowdin** usando arquivos JSON em `i18n/`.
- 🔒 **Repositório organizado** com CI, code scanning, Dependabot, templates, discussions e política de segurança.

## 📦 Requisitos

- Dank Material Shell rodando sobre Quickshell.
- Ferramentas Linux: `bash`, `node`, `jq` e `curl`.
- Recomendado: `codexbar` em `PATH`, `~/.local/bin`, `/usr/local/bin` ou configurado nas opções do plugin.
- Opcional para Copilot: `gh auth login`, `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` ou `GITHUB_TOKEN`.
- Opcional para detalhes de Claude: `claude`, `~/.claude/.credentials.json` e logs locais em `~/.claude/projects`.

## ⚡ Instalação Rápida

Copie o plugin para a pasta de plugins do DMS, torne os helpers executáveis e reinicie o DMS:

```bash
cd /caminho/onde/baixou/AiOverviewControl
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml \
  plugin.json qmldir get-* README.md CHANGELOG.md LICENSE docs i18n screenshot.png \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-*
dms restart
```

Depois abra as configurações do DMS, habilite **AiOverviewControl** e adicione o widget a uma seção da DankBar.

Guia completo: [installation.md](./installation.md)

## ⚙️ Configuração Recomendada

| Opção | Valor recomendado | Motivo |
| ----- | ----------------- | ------ |
| Provider Set | `codex,claude,copilot` | Boa cobertura padrão para uso local de assistentes de IA. |
| Source Mode | `cli` | Usa CLIs locais e helpers nativos primeiro. |
| Show Provider Errors | `true` | Facilita setup e diagnóstico de providers. |
| Refresh Interval | `120000` ou `300000` | Mantém a telemetria atualizada sem polling excessivo. |

Referência de configuração: [configuration.md](./configuration.md)

## 🤖 Providers

O AiOverviewControl reconhece estes IDs de provider:

```text
codex, claude, copilot, gemini, openrouter, perplexity, cursor, kilo, kiro, ollama, warp, amp
```

O suporte real depende das credenciais locais, APIs disponíveis, scripts auxiliares incluídos no plugin e suporte opcional via `codexbar`.

| Provider | Caminho de coleta | Observações |
| -------- | ----------------- | ----------- |
| `codex` | fallback via `codexbar` | Lê uso de providers compatíveis com CodexBar local. |
| `claude` | `get-claude-usage` | Inclui analytics de Claude Code, janelas, tokens, sessões e custo estimado. |
| `copilot` | `get-copilot-usage` | Usa autenticação do GitHub via `gh` ou variáveis de ambiente. |
| `gemini`, `openrouter`, outros | helpers nativos ou fallback | Cobertura varia por API do provider e credenciais locais. |

Matriz completa: [providers.md](./providers.md)

## 🧪 Validação Local

Na raiz do repositório, use estes comandos para separar problema de ambiente, autenticação e UI:

```bash
jq . plugin.json
bash -n get-provider-usage get-copilot-usage get-claude-usage
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
./get-provider-usage "$(command -v codexbar)" "codex,claude,copilot" "cli" ./get-copilot-usage
./get-copilot-usage
./get-claude-usage
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml
```

Se um provider funciona no terminal, mas não aparece no painel, comece por [troubleshooting.md](./troubleshooting.md).

## 🗂️ Estrutura Do Projeto

| Caminho | Função |
| ------- | ------ |
| `AiOverviewControlWidget.qml` | Indicador da DankBar, dashboard, coleta e renderização. |
| `AiOverviewControlSettings.qml` | Interface de configurações no DMS. |
| `AiOverviewControlI18n.qml` | Loader e lookup de traduções. |
| `get-provider-usage` | Backend unificado e dispatcher de fallbacks. |
| `get-copilot-usage` | Ponte para uso do GitHub Copilot. |
| `get-claude-usage` | Analytics local de Claude Code e ponte de uso. |
| `i18n/` | Arquivos JSON de idioma gerenciados com Crowdin. |
| `.github/` | CI, code scanning padrão, Dependabot, funding, templates e arquivos comunitários. |

Visão técnica: [architecture.md](./architecture.md)

## 📚 Documentação

- 🇺🇸 README principal: [../README.md](../README.md)
- 🇧🇷 README em português: [README.pt-BR.md](./README.pt-BR.md)
- 🧭 Instalação: [installation.md](./installation.md)
- ⚙️ Configuração: [configuration.md](./configuration.md)
- 🤖 Providers: [providers.md](./providers.md)
- 🌍 Crowdin e i18n: [i18n-crowdin.md](./i18n-crowdin.md)
- 🧱 Arquitetura: [architecture.md](./architecture.md)
- 🩺 Troubleshooting: [troubleshooting.md](./troubleshooting.md)

## 🤝 Contribuindo

Issues, pedidos de provider, traduções e pull requests são bem-vindos.

- Use os [templates de issue](https://github.com/bernardopg/AiOverviewControl/issues/new/choose) para bugs, features e providers.
- Use [discussions](https://github.com/bernardopg/AiOverviewControl/discussions) para suporte e perguntas gerais.
- Reporte vulnerabilidades pelo fluxo de segurança do repositório e siga [../.github/SECURITY.md](../.github/SECURITY.md).
- Para traduções, veja [i18n-crowdin.md](./i18n-crowdin.md).

## 💜 Apoio

Se o AiOverviewControl ajuda no seu setup do DMS, você pode apoiar a manutenção pelo GitHub Sponsors:

[![Sponsor](https://img.shields.io/badge/Sponsor-bernardopg-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/bernardopg)

## 📄 Licença

Distribuído nos termos de [LICENSE](../LICENSE).

<img width="100%" alt="" src="https://capsule-render.vercel.app/api?type=wave&color=0:22C55E,45:2563EB,100:0F172A&height=110&section=footer" />
