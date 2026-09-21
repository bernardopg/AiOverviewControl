<div align="center">

![Banner do AiOverviewControl](./assets/banner.png)

# AiOverviewControl

**Todas as suas cotas de IA. Um dashboard. Zero achismo.**

Widget autocontido do [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) para cotas,
billing, autenticação e telemetria local de uso de IA — direto na sua DankBar.

[![CI](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml/badge.svg)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/bernardopg/AiOverviewControl)](https://github.com/bernardopg/AiOverviewControl/releases/latest)
[![Licença](https://img.shields.io/github/license/bernardopg/AiOverviewControl)](../LICENSE)
[![Provedores](https://img.shields.io/badge/provedores-37-7C4DFF)](./providers.md)
[![Idiomas](https://img.shields.io/badge/idiomas%20de%20UI-5-00BFA5)](./i18n-crowdin.md)
[![Upvote no Dank Plugins](https://img.shields.io/badge/Dank%20Plugins-%F0%9F%91%8D%20upvote-FF4081)](https://github.com/AvengeMedia/dms-plugin-registry/issues/358)

[Instalação](#instalação) · [Screenshots](#screenshots) · [Provedores](./providers.md) ·
[Configuração](./configuration.md) · [Changelog](../CHANGELOG.md) ·
[Upvote](#apoie-o-plugin) · [English](../README.md)

</div>

---

## Veja em ação

![Demonstração do AiOverviewControl](./assets/demo.gif)

> 🎬 Prefere mais qualidade? Assista ao [demo em MP4](./assets/demo.mp4).

A pílula fica na DankBar e mostra o uso ao vivo. Provedores com múltiplas janelas de cota (as de 5 horas e 7 dias do Claude, por exemplo) podem exibir qualquer janela na barra — escolha por provedor, ou deixe `highest` seguir a mais apertada. Passe o mouse sobre a pílula para ver de qual janela veio o número e quando ela reseta:

![Pílula na DankBar](./assets/bar-pill.png)

## Por que AiOverviewControl?

Você paga por Claude, Codex, Copilot, OpenRouter — e cada um esconde a cota em
um dashboard, CLI ou API diferente. O AiOverviewControl coleta cada provedor
**de forma independente e local**, normaliza o resultado e renderiza uma visão
única e honesta, sem nenhum serviço externo de agregação.

**Honesto** é a palavra-chave: ele reporta dados medidos quando existe uma
fonte suportada e rotula claramente provedores apenas-autenticação ou
informativos quando não existe. Sem scraping de dashboards. Sem percentuais
inventados. Nunca.

## Destaques

| | |
| --- | --- |
| 📊 **Dashboard unificado** | 37 provedores de IA e ferramentas de desenvolvimento em um só lugar. |
| 🛰️ **Visão geral da frota** | Rollup cross-provider no hero — carga média só de cotas mensuráveis, provedor mais quente, quantos estão perto do limite e o próximo reset. |
| ⏱️ **Janelas oficiais do Codex** | Janelas de rate-limit direto do `codex app-server`. |
| 🤖 **Analytics profundo do Claude** | Cota mais analytics local de tokens, sessões, modelos, projetos e custo. |
| 🐙 **Cotas do Copilot** | Snapshots de Premium requests, Chat e Completions. |
| 🗂️ **Cartões ricos** | Janelas de uso, horários de reset, identidade, créditos, sparklines, tendências e links para o console. |
| 🛡️ **Falhas isoladas** | Um timeout ou credencial inválida nunca esconde provedores saudáveis. |
| 🎛️ **Layout flexível** | Densidade compacta/confortável, filtros por status, provedores fixados, pílula `auto`/`custom`/`top` e escolha de janela de uso por provedor na DankBar. |
| 🔔 **Notificações de cota** | Alertas do DMS com a marca do provedor, limiares globais/por provedor, um toast por janela de cota, atualizado no mesmo toast quando a cota esgota. Os alertas podem seguir a janela exibida na barra, todas as janelas ou apenas a primária. |
| 📄 **Exportação de histórico** | Salve o histórico local de uso em CSV ou JSONL pelas Configurações ou por `providers/export-usage-history`. |
| 🌍 **5 idiomas de UI** | English, Português (BR), 简体中文, Español e Deutsch. |
| 🔒 **Privacidade em primeiro lugar** | Adaptadores locais, nenhuma chamada paga só para testar chave, segredos nunca exibidos. |

## Screenshots

| Visão geral do dashboard | Cartão de provedor expandido |
| --- | --- |
| ![Dashboard](./assets/dashboard.png) | ![Cartão expandido](./assets/card-expanded.png) |

<details>
<summary><b>📈 Telemetria local detalhada (exemplo do 9Router)</b></summary>
<br>

Seções de telemetria por provedor incluem gráficos diários de custo, totais de
hoje/semana/mês, contadores de tokens in/out, top modelos e detalhamento por
provedor roteado — tudo lido de dados locais pertencentes ao provedor.

![Telemetria do 9Router](./assets/telemetry.png)

</details>

## Modelo de cobertura

Os cartões usam um de seis níveis honestos de cobertura:

| Cobertura | Significado |
| --- | --- |
| **Cota** | Retorna janelas reais de limite ou gasto e o percentual usado (Codex, Copilot, Antigravity, OpenRouter, Z.ai, GLM, Command Code, OpenCode Go, xAI SuperGrok). |
| **Saldo** | Retorna saldo pré-pago ou créditos restantes em moeda real (Kimi, DeepSeek, xAI Management API). |
| **Analytics** | Lê contadores de consumo ou dados locais pertencentes ao provedor (Cloudflare GraphQL, 9Router, Claude, pi, Hermes). |
| **Autenticação** | Verifica credenciais via endpoint somente leitura sem dados estáveis de cota (Gemini, Mistral, MiniMax, Qwen e outros). Alguns cartões de status configurado, como NVIDIA, não conseguem validar a chave porque o catálogo do provedor é público. |
| **Runtime local** | Mostra estado local em vez de cota de conta (modelos do Ollama, autenticação do Vertex AI). |
| **Informativo** | Aponta para o uso oficial quando não existe API somente leitura (Kiro, Cursor, Warp e outros). |

Integrações medidas notáveis:

| Provedor | Fonte de dados |
| --- | --- |
| Codex | Métodos oficiais de conta e rate-limit do `codex app-server`. |
| Claude Code | Cota OAuth mais analytics local de `~/.claude/projects` (ou `$CLAUDE_CONFIG_DIR/projects` quando essa variável de ambiente estiver definida). |
| GitHub Copilot | Snapshot autenticado de cota GitHub/Copilot. |
| Antigravity | Janelas de cota de 5 horas e semanais para Gemini e Claude/OpenAI via Cloud Code Assist; diagnósticos opcionais por modelo, separação automática de múltiplas contas e descoberta do arquivo de token do `agy`. |
| 9Router | Dados locais de uso em SQLite ou JSON, incluindo telemetria por modelo roteado. |
| pi | Telemetria JSONL local de sessões (`~/.pi/agent/sessions`) — custo, tokens, top modelos, top projetos; não há API de cota (o pi não tem rate limits). |
| Hermes | Entrada de natureza dupla: telemetria do harness de agente via `~/.hermes/state.db` (sessões, tokens por modelo/projeto, origens, chamadas de API) mais identidade de provider (cobrança ativa, modelo padrão) de `~/.hermes/config.yaml` / `auth.json`. O faturamento do lado provider permanece no [Nous Portal](https://portal.nousresearch.com). |
| OpenRouter | Limites de chave, gasto, saldo e atividade de modelos em 30 dias. |
| Kimi (Moonshot) | Saldo da Open Platform (`GET /v1/users/me/balance`, USD/CNY) — ou cota da assinatura **Kimi Code** (`GET /coding/v1/usages`, janelas semanal e de 5h) quando uma chave `sk-kimi-` / `KIMI_CODING_API_KEY` está definida. |
| DeepSeek | API oficial de saldo da conta. |
| Together | Validação somente leitura da chave; uso e billing permanecem no console da Together. |
| Cloudflare | Verificação de token e analytics opcional do Workers AI via GraphQL. |
| Z.ai, GLM | `GET /api/monitor/usage/quota/limit` — uso real por janela, timestamps de reset e plano da assinatura. Faz fallback para verificação apenas de autenticação via `/models`. |
| Command Code | Uso ao vivo das janelas de 5h/semanal/mensal via `/alpha/billing/credits`; usa `COMMAND_CODE_API_KEY` ou o `apiKey` protegido salvo por `cmd login` em `~/.commandcode/auth.json`. |
| OpenCode Go | Uso ao vivo das janelas de 5h/semanal/mensal em `/zen/go/v1/usage`; usa `OPENCODE_API_KEY` ou a credencial do CLI em `${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json`. Quando o fallback de saldo do plano Go está ativo, o cartão o informa sem declarar um valor de saldo. |
| xAI (Grok) | Uso SuperGrok semanal/mensal a partir de `grok login` (`~/.grok/auth.json`) via a API de billing do CLI; créditos pré-pagos da API via Management API (`XAI_MANAGEMENT_KEY` + `XAI_TEAM_ID`); `XAI_API_KEY` é apenas autenticação. |
| MiniMax, Qwen, Mistral | Validação somente leitura via `/models` (ou `/api-key`) — consumo zero de tokens. |
| NVIDIA | Apenas status da chave configurada; o catálogo público de modelos não permite validar a chave. |
| Ollama | Modelos instalados e em execução via `/api/tags` e `/api/ps`. |

A matriz completa, credenciais e referências upstream estão documentadas em
[Provedores](./providers.md) e
[Verificação de provedores](./provider-verification.md).

## Requisitos

- DankMaterialShell rodando sobre Quickshell.
- `bash`, `jq` e `curl`.
- CLIs ou credenciais específicas apenas para os provedores habilitados. O Antigravity pode ler o arquivo de token do `agy` em `~/.gemini/antigravity-cli/antigravity-oauth-token`, uma sessão no keyring via `secret-tool` ou o banco de estado da IDE (esse caminho exige `sqlite3`); Hermes e 9Router precisam de `sqlite3` para seus bancos locais de uso.
- As notificações de cota também precisam de `notify-send` e `flock`.

Linha de base recomendada para o conjunto padrão de provedores:

```bash
command -v bash jq curl codex claude gh
codex login
claude auth status
gh auth status
```

## Instalação

### Loja de plugins do DMS (recomendado)

```bash
dms plugins install aiOverviewControl
```

Ou instale o **AiOverviewControl** pela loja de plugins dentro das configurações
do DMS, ou pelo [diretório Dank Plugins](https://danklinux.com/plugins).
Instalações pela loja ficam sob o id de manifesto `aiOverviewControl` (com `a`
minúsculo no início); os dois métodos manuais abaixo usam o casing do nome de
exibição `AiOverviewControl` — veja [installation.md](./installation.md) para
entender por que isso importa em sistemas de arquivos sensíveis a maiúsculas.

### Arquivo de release

Baixe o `.tar.gz` ou `.zip` da
[release mais recente](https://github.com/bernardopg/AiOverviewControl/releases/latest),
extraia como `AiOverviewControl` e coloque no diretório de plugins do DMS:

```text
~/.config/DankMaterialShell/plugins/AiOverviewControl
```

Depois restaure as permissões de execução e reinicie o DMS:

```bash
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

### Clone via Git

```bash
git clone https://github.com/bernardopg/AiOverviewControl.git \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

Ative **AiOverviewControl** nas configurações do DMS e adicione-o a uma seção
da DankBar. Orientações detalhadas de instalação e upgrade estão em
[docs/installation.md](./installation.md).

## Configuração

As configurações são armazenadas pelo DMS e sobrevivem a upgrades do plugin.

| Configuração | Valores | Padrão |
| --- | --- | --- |
| Idioma | `auto`, `en_US`, `pt_BR`, `zh_CN`, `es_ES`, `de_DE` | `auto` |
| Provedores monitorados | IDs separados por vírgula | `codex,claude,copilot` |
| Densidade do dashboard | `comfortable`, `compact` | `comfortable` |
| Modo da pílula | `auto`, `custom`, `top` | `auto` |
| Provedores da pílula customizada | IDs de provedores monitorados separados por vírgula | provedores monitorados |
| Janela de uso no DankBar | pares `provedor:janela`, com janela `primary`, `secondary`, `tertiary` ou `highest` (ex.: `claude:secondary`) | janela primária |
| Tooltip da pílula no DankBar | ativado ou desativado | ativado |
| Provedores fixados | IDs separados por vírgula | vazio |
| Cor dos logos | qualquer string de cor aceita pelo QML | cor primária atual do DMS |
| Intervalo de atualização | 1, 2, 5, 15 ou 30 minutos | 2 minutos |
| Mostrar erros de provedor | habilitado ou desabilitado | habilitado |
| Detalhamento de projetos do Claude | habilitado ou desabilitado | habilitado |
| Modelos individuais do Antigravity | habilitado ou desabilitado | desabilitado |
| Notificações de cota | habilitado ou desabilitado | habilitado |
| Limiar global de notificação | 75%, 85% ou 95% | 85% |
| Limiares por provedor | pares `provedor:percentual` separados por vírgula (ex.: `claude:90,codex:75`), validados na hora | vazio |
| Janelas que geram alertas | `displayed` (segue a janela do DankBar), `all` ou `primary` | `displayed` |
| Intervalo de repetição | uma vez por janela, 1h, 6h ou 24h (atualiza o alerta existente) | uma vez por janela |
| Retenção de histórico | 500, 2.000 ou 10.000 snapshots | 2.000 |

As Configurações também oferecem **Exportar histórico de uso** (CSV ou JSONL) e
um **Redefinir configurações do plugin** em dois passos, que restaura todas as
opções acima sem tocar no histórico registrado.

A seleção padrão de provedores é:

```text
codex,claude,copilot
```

Provedores com API leem credenciais do ambiente do processo do DMS. Um export
disponível apenas em shell interativo pode não chegar a uma sessão gráfica do
DMS. Veja [Configuração](./configuration.md) para a matriz de variáveis de
ambiente e o comportamento do health-check.

## Comportamento do dashboard

- O hero mostra uma **visão geral da frota** quando dois ou mais provedores
  resolvem: a carga média nas janelas de cota mensuráveis, o provedor mais
  quente, quantos estão em ou acima de 80% e o reset mais próximo da frota.
  Cartões de saldo, analytics, runtime local e informativos ficam
  intencionalmente fora do denominador da média, para que seus placeholders
  honestos de `0%` não diluam a pressão real de cota. Pico, contagem em risco
  e reset ainda varrem todos os cartões vivos.
- A visão geral é **navegável**: clique no provedor de pico do rollup da frota,
  ou nas barras de uso do hero, para expandir e rolar direto até o cartão
  daquele provedor.
- Cartões são ordenados com fixados primeiro, depois por maior uso mensurável,
  com provedores em falha por último.
- Cartões suportam foco por teclado, além de Enter/Espaço (expandir), Delete
  (remover), P (fixar) e R (tentar novamente).
- Dados ficam obsoletos após o dobro do intervalo de atualização configurado.
- Cartões em falha expõem uma ação de retry específica do provedor.
- Cartões expandidos mostram janelas disponíveis, créditos, fonte, identidade e
  horário de atualização, sem inventar campos indisponíveis.
- Snapshots de uso são armazenados localmente em
  `~/.cache/AiOverviewControl/usage-history.jsonl` e podados conforme a
  retenção configurada. O escritor de histórico registra apenas pressão real
  não-zero de cota/gasto; placeholders `0%` informativos, de runtime local,
  somente-saldo e somente-analytics são ignorados para que as sparklines
  permaneçam significativas. Suítes de teste baseadas em fixtures exportam um
  `XDG_CACHE_HOME` isolado antes de invocar o dispatcher real, então nunca
  gravam snapshots de fixture no seu histórico real. Como o arquivo é podado,
  `providers/export-usage-history csv|jsonl` (também um botão nas
  Configurações) é a forma de guardar dados de longo prazo.
- O analytics do Claude roda separadamente, para que falhas de histórico local
  ou de OAuth não bloqueiem a coleta principal.

## Privacidade e resiliência

- Credenciais são lidas de CLIs dos provedores, dados locais pertencentes ao
  provedor ou variáveis de ambiente; a UI nunca exibe valores secretos.
- O plugin não faz scraping de dashboards web autenticados.
- Não chama endpoints pagos de inferência apenas para testar uma chave.
- Arquivos temporários são isolados por execução e removidos ao fim da coleta.
- Erros de provedor retornam como dados estruturados em vez de encerrar todo o
  refresh.
- Cartões informativos usam texto explícito e links oficiais em vez de
  percentuais sintéticos.

## Validação

<details>
<summary>Execute as mesmas verificações principais usadas pelo CI</summary>
<br>

O lint de QML é um **gate obrigatório** no CI (`qmllint` do Qt5, verificação
de sintaxe — sem ruído de resolução de import `qs.*` para filtrar). Um arquivo
QML malformado derruba o build.

```bash
jq -e . plugin.json >/dev/null
for file in i18n/*.json; do jq -e . "$file" >/dev/null; done
find providers -maxdepth 1 -type f -print0 | xargs -0 bash -n
for test in tests/*.sh; do bash -n "$test"; done
bash -n scripts/package-release
for test in tests/*.sh; do bash "$test"; done
shellcheck -S warning providers/* tests/*.sh scripts/package-release scripts/render-contributors
qmllint \
  AiOverviewControlWidget.qml \
  AiOverviewControlSettings.qml \
  AiOverviewControlI18n.qml \
  ProviderLogo.qml
./providers/get-provider-health "codex,claude,copilot,pi" | jq .
./providers/get-provider-usage \
  "codex,claude,copilot,pi" \
  ./providers/get-copilot-usage | jq .
./providers/get-usage-history | jq .
./providers/export-usage-history csv /tmp
```

O GitHub Actions também valida sintaxe dos workflows, paridade de chaves de
locale, permissões dos scripts de provedor, contratos de integração,
configuração do Crowdin e empacotamento de release.

</details>

## Arquitetura

```text
AiOverviewControlWidget.qml       Orquestração de runtime e dashboard
AiOverviewControlSettings.qml     Configurações, seleção de provedores e UI de saúde
AiOverviewControlI18n.qml         Carregamento de locales e interpolação
ProviderLogo.qml                  Resolução e fallback dos logos locais de provedores
providers/get-provider-usage      Dispatcher multi-provedor e escritor de histórico
providers/get-provider-health     Verificações locais de pré-requisitos
providers/export-usage-history    Exportação do histórico de uso em CSV ou JSONL
providers/get-codex-usage         Ponte do protocolo codex app-server
providers/get-claude-usage        Ponte de cota e analytics local do Claude
providers/get-copilot-usage       Ponte de cota do GitHub Copilot
providers/get-antigravity-usage   Ponte de cota do Cloud Code Assist do Antigravity
providers/get-9router-analytics   Telemetria local detalhada do 9Router
providers/get-pi-analytics        Telemetria local detalhada de sessões do pi
providers/get-hermes-analytics    Telemetria local do estado do Hermes
providers/get-*-usage             Entrypoints canônicos de provedor único
scripts/package-release           Build e validação dos arquivos de release
scripts/render-contributors       Grade de avatares de colaboradores nos READMEs
```

Veja [Arquitetura](./architecture.md) para o fluxo de runtime e o contrato
normalizado de provedores.

## Documentação

| Tópico | Link |
| --- | --- |
| Instalação e upgrades | [installation.md](./installation.md) |
| Configuração e credenciais | [configuration.md](./configuration.md) |
| Matriz de cobertura de provedores | [providers.md](./providers.md) |
| Política de verificação de provedores | [provider-verification.md](./provider-verification.md) |
| Arquitetura e contrato de adaptadores | [architecture.md](./architecture.md) |
| Solução de problemas | [troubleshooting.md](./troubleshooting.md) |
| Internacionalização e Crowdin | [i18n-crowdin.md](./i18n-crowdin.md) |
| Checklist de release | [release-checklist.md](./release-checklist.md) |
| Changelog | [CHANGELOG.md](../CHANGELOG.md) |

## Apoie o plugin

O AiOverviewControl é ranqueado no [diretório Dank Plugins](https://danklinux.com/plugins)
pelas reações 👍 na issue de acompanhamento do registry. Uma reação lá é a coisa
mais útil que você pode fazer pelo projeto — é o que decide se outras pessoas
usuárias do DankMaterialShell vão descobrir o plugin.

<div align="center">

[![Dar upvote no Dank Plugins](https://img.shields.io/badge/Dank%20Plugins-%F0%9F%91%8D%20d%C3%AA%20upvote%20neste%20plugin-7C4DFF?style=for-the-badge)](https://github.com/AvengeMedia/dms-plugin-registry/issues/358)
[![Dar estrela no repositório](https://img.shields.io/github/stars/bernardopg/AiOverviewControl?style=for-the-badge&color=FFC400&label=estrela%20no%20reposit%C3%B3rio)](https://github.com/bernardopg/AiOverviewControl/stargazers)

</div>

A mesma issue é o link **Discuss** do plugin no diretório, então feedback e
ideias de funcionalidades também são bem-vindos por lá, além das
[issues do GitHub](https://github.com/bernardopg/AiOverviewControl/issues).

## Colaboradores

<div align="center">

<!-- CONTRIBUTORS:START - generated by scripts/render-contributors -->

<a href="https://github.com/bernardopg" title="bernardopg"><img src="https://avatars.githubusercontent.com/u/69475128?v=4&s=112" width="56" height="56" alt="bernardopg" /></a>
<a href="https://github.com/gtheys" title="gtheys"><img src="https://avatars.githubusercontent.com/u/527237?v=4&s=112" width="56" height="56" alt="gtheys" /></a>
<a href="https://github.com/Luna161" title="Luna161"><img src="https://avatars.githubusercontent.com/u/268031236?v=4&s=112" width="56" height="56" alt="Luna161" /></a>
<a href="https://github.com/arqueon" title="arqueon"><img src="https://avatars.githubusercontent.com/u/66568719?v=4&s=112" width="56" height="56" alt="arqueon" /></a>
<a href="https://github.com/goulartdev" title="goulartdev"><img src="https://avatars.githubusercontent.com/u/16469407?v=4&s=112" width="56" height="56" alt="goulartdev" /></a>
<a href="https://github.com/emmsixx" title="emmsixx"><img src="https://avatars.githubusercontent.com/u/56744133?v=4&s=112" width="56" height="56" alt="emmsixx" /></a>
<a href="https://github.com/gouwazi" title="gouwazi"><img src="https://avatars.githubusercontent.com/u/23072555?v=4&s=112" width="56" height="56" alt="gouwazi" /></a>
<a href="https://github.com/UN-9BOT" title="UN-9BOT"><img src="https://avatars.githubusercontent.com/u/111110804?v=4&s=112" width="56" height="56" alt="UN-9BOT" /></a>

<!-- CONTRIBUTORS:END -->

</div>

Contribuições são bem-vindas — veja [CONTRIBUTING.md](../CONTRIBUTING.md).

---

<div align="center">

Distribuído sob a [Licença MIT](../LICENSE).

Feito com ❤️ para a comunidade [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

</div>
