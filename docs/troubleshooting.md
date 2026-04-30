# Troubleshooting

Use esta pagina para identificar se o problema esta em binario, autenticacao, provider, script local ou renderizacao.

## Checklist rapido

```bash
command -v bash
command -v node
command -v jq
command -v curl
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage
```

Se algum helper local falhar, corrija antes de investigar a UI. `codexbar` e recomendado para Codex e providers genericos, mas nao e mais o unico caminho de coleta.

## `codexbar not found`

O DMS pode iniciar com um `PATH` diferente do seu terminal.

Isso afeta Codex e providers sem adapter local. Copilot, Gemini com chave local, OpenRouter com chave local e detalhes de Claude podem continuar funcionando via helpers.

Solucoes:

1. Configure **Optional fallback** com o caminho absoluto do `codexbar`.
2. Confirme que o arquivo existe e e executavel.
3. Reinicie o DMS.

Comandos uteis:

```bash
command -v codexbar
ls -l ~/.local/bin/codexbar /usr/local/bin/codexbar 2>/dev/null
```

## Provider aparece como erro

Teste o provider fora do widget:

```bash
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
codexbar usage --format json --provider gemini --source api
```

Se o terminal falhar, ajuste autenticacao, source mode ou remova o provider da lista. O AiOverviewControl preserva providers que funcionam mesmo quando outros falham.

Use o helper principal para testar a agregacao completa fora da UI:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage \
  "$(command -v codexbar)" \
  "codex,claude,copilot,gemini,openrouter" \
  "cli" \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

## Copilot nao mostra uso

O script local precisa de token GitHub valido.

Teste:

```bash
gh auth status
gh auth token >/dev/null && echo ok
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

Alternativas de token:

```bash
export COPILOT_GITHUB_TOKEN=...
export GH_TOKEN=...
export GITHUB_TOKEN=...
```

Se a resposta for HTTP 401/403, renove a autenticacao com `gh auth login` e confirme que sua conta tem Copilot ativo.

## Claude nao mostra detalhes extras

O card principal de Claude pode funcionar via CodexBar enquanto os detalhes extras ficam vazios. Isso normalmente indica falta de CLI, credenciais ou logs locais.

Confira:

```bash
claude --version
test -f ~/.claude/.credentials.json
test -d ~/.claude/projects
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
```

Dependencias do script:

```bash
command -v jq
command -v curl
```

O script usa cache para reduzir chamadas e tolerar rate limit. Se dados antigos aparecerem, aguarde alguns minutos ou remova caches somente se souber que quer forcar nova leitura:

```bash
rm -f ~/.claude/usage-cache.json ~/.claude/pricing-cache.json
```

## Painel vazio

Possiveis causas:

- `get-provider-usage` nao esta executavel.
- Todos os providers configurados falharam.
- A lista customizada ficou vazia ou contem IDs sem suporte.
- O primeiro refresh ainda esta rodando.

Teste minimo:

```text
Provider Set: codex
Source Mode: cli
Show Provider Errors: true
```

Depois rode:

```bash
codexbar usage --format json --provider codex --source cli
```

## Painel lento ou cheio demais

Cada provider e consultado em sequencia. Muitos providers, rede lenta ou APIs com timeout podem deixar o refresh pesado.

Melhorias praticas:

- Aumente **Refresh Interval** para `300000` ou mais.
- Remova providers que sempre falham.
- Prefira `cli` para providers locais.
- Use `api` apenas quando o token esta configurado e o provider responde rapido.

## Validar QML

Quando estiver desenvolvendo o plugin:

```bash
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml
```

Se `qmllint` nao existir, instale as ferramentas Qt/Quickshell da sua distribuicao.
