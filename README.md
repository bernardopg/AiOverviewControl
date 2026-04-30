# AiOverviewControl

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

O modo `cli` e usado apenas por providers que caem no fallback `codexbar`. Os helpers locais deste plugin cobrem lacunas comuns no Linux, especialmente Copilot, Claude Code, Gemini e OpenRouter.

Detalhes de cada opcao: [docs/configuration.md](./docs/configuration.md).

## Providers

O plugin conhece os IDs `codex`, `claude`, `copilot`, `gemini`, `openrouter`, `perplexity`, `cursor`, `kilo`, `kiro`, `ollama`, `warp` e `amp`.

O suporte real depende de duas coisas:

- Providers com ponte local propria dentro deste diretorio.
- Providers consultados pelo fallback `codexbar usage --format json --provider <id> --source <modo>`.

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
- **Painel cheio demais**: remova providers que falham ou use uma lista customizada menor.

## Licenca

Veja [LICENSE](./LICENSE).
