# Arquitetura

O AiOverviewControl e um plugin de widget para Dank Material Shell. Ele mantem a UI e os scripts auxiliares dentro do proprio diretorio para evitar acoplamento com outros plugins.

## Arquivos principais

```text
plugin.json
AiOverviewControlWidget.qml
AiOverviewControlSettings.qml
get-copilot-usage
get-claude-usage
get-provider-usage
README.md
docs/
CHANGELOG.md
LICENSE
```

## Metadata

`plugin.json` declara:

- `id`: `aiOverviewControl`
- `type`: `widget`
- `component`: `./AiOverviewControlWidget.qml`
- `settings`: `./AiOverviewControlSettings.qml`
- capacidades: `dankbar-widget` e `process`
- permissoes: leitura/escrita de settings e execucao de processos

## Fluxo de dados

1. Ao carregar, o widget confere se `get-provider-usage` esta executavel.
2. Se o helper existe, dispara `refresh()`.
3. O refresh chama `get-provider-usage` com a lista `providerSelection`, `sourceMode`, caminho opcional do `codexbar` e scripts auxiliares.
4. O helper chama adapters locais ou `codexbar`, conforme o provider.
5. Para `claude`, o widget tambem pode chamar `get-claude-usage` em processo separado para popular analytics extras.
6. Cada resposta e normalizada para uma lista de providers.
7. Erros viram cards independentes, sem apagar providers saudaveis.
8. O popout mostra providers filtrados conforme `showErrorProviders`.

## Modelo visual esperado

Cada provider pode expor:

```text
provider
source
usage.identity.accountEmail
usage.identity.loginMethod
usage.primary
usage.secondary
usage.tertiary
credits.remaining
error
```

Janelas de uso seguem o formato:

```text
usedPercent
windowMinutes
resetsAt
resetDescription
remaining
unlimited
hasQuota
```

O dashboard escolhe o provider com maior `usedPercent` bem-sucedido para o indicador compacto e para o resumo superior.

## Processos QML

`AiOverviewControlWidget.qml` usa `Quickshell.Io Process` para:

- detectar o helper local e o caminho opcional do `codexbar`;
- buscar uso dos providers;
- buscar analytics extras de Claude.

O timeout de coleta e de 45 segundos. Se o processo exceder esse tempo, o widget mostra erro de timeout e evita reaproveitar saida atrasada.

## Settings persistidas

Chaves usadas pelo plugin:

```text
refreshInterval
codexbarPath
providerSelection
sourceMode
showErrorProviders
```

Essas chaves ficam no armazenamento de settings do DMS. Atualizar os arquivos do plugin nao deve apagar preferencias do usuario.

## Independencia do plugin

O AiOverviewControl nao importa componentes de outro plugin local. Os acoplamentos externos sao:

- API e componentes comuns do Dank Material Shell;
- Quickshell para processos e UI;
- executavel opcional `codexbar` para Codex e providers sem ponte local;
- CLIs e arquivos locais dos providers.

Isso significa que remover ou desabilitar outro plugin DMS chamado CodexBar nao deve quebrar este widget. Para providers que dependem especificamente do fallback CodexBar, mantenha o executavel `codexbar` instalado.

## Scripts locais

### `get-copilot-usage`

Responsavel por transformar dados do GitHub Copilot em JSON compativel com os cards do widget.

Entrada:

- token via `gh auth token`;
- ou `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`.

Saida:

- provider `copilot`;
- source `github-copilot-api`;
- janelas Premium, Chat e Completions;
- creditos restantes quando disponiveis;
- objeto `error` em JSON quando nao ha token ou a API falha.

### `get-provider-usage`

Backend agregador local para providers.

Entrada:

- caminho opcional do `codexbar`;
- CSV de providers;
- source mode;
- caminho opcional do helper de Copilot.

Saida:

- array JSON com um item por provider;
- mesma estrutura `provider/source/usage/credits/error` esperada pelos cards.

Fallbacks conhecidos:

- Copilot por `get-copilot-usage`;
- Claude por `codexbar`, com fallback para `get-claude-usage`;
- Gemini por `codexbar`, com fallback por API key ou credenciais locais;
- OpenRouter por `OPENROUTER_API_KEY` ou `codexbar`;
- demais providers por `codexbar`.

### `get-claude-usage`

Responsavel pelos detalhes extras de Claude Code.

Entrada:

- `~/.claude/.credentials.json`;
- `~/.claude/projects/**/*.jsonl`;
- `~/.claude/stats-cache.json`;
- rede opcional para precos/modelos e cambio.

Saida:

- pares `CHAVE=valor`, lidos pelo QML;
- utilizacao de 5 horas e 7 dias;
- tokens, sessoes, mensagens e custos estimados;
- caches em `~/.claude`.

## Principios de manutencao

- Preserve a coleta por provider isolado.
- Nao dependa de arquivos de outros plugins.
- Prefira erros estruturados em JSON nos scripts.
- Ao adicionar provider com script proprio, mantenha a saida no mesmo modelo `provider/source/usage/credits/error`.
- Documente source recomendado e comando de validacao em [providers.md](./providers.md).
