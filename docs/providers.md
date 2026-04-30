# Providers

O AiOverviewControl consulta cada provider separadamente e combina os resultados no dashboard. Isso evita que uma falha em um provider derrube o painel inteiro.

O caminho atual do widget usa `get-provider-usage` como backend local. Esse helper tenta adapters nativos primeiro quando existem e usa `codexbar` como fallback para Codex e providers compativeis.

## IDs conhecidos

O seletor do dashboard conhece:

```text
codex
claude
copilot
gemini
openrouter
perplexity
cursor
kilo
kiro
ollama
warp
amp
```

Voce tambem pode digitar manualmente outros IDs aceitos pelo seu `codexbar`, desde que ele retorne JSON no formato esperado.

## Matriz pratica

| Provider | Caminho usado | Melhor source | Observacoes |
| --- | --- | --- | --- |
| `codex` | `get-provider-usage` -> `codexbar usage` | `cli` | Recomendado para janela local de Codex/ChatGPT quando suportada pelo CodexBar. |
| `claude` | `get-provider-usage` -> `codexbar usage` ou `get-claude-usage` | `cli` | Detalhes extras vem dos arquivos locais do Claude Code. |
| `copilot` | `get-copilot-usage` | independente do source global | Usa GitHub autenticado via `gh` ou token de ambiente. |
| `gemini` | `get-provider-usage` -> `codexbar` ou chave/OAuth local | `api`, `oauth` ou `auto` | Aceita `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY` ou credenciais `~/.gemini`. |
| `openrouter` | `get-provider-usage` -> `OPENROUTER_API_KEY` ou `codexbar` | `api` | Normalmente exige token/API configurado no CodexBar ou `OPENROUTER_API_KEY`. |
| `perplexity` | `codexbar usage` | `api` ou `oauth` | Depende de suporte no CodexBar. |
| `cursor`, `kilo`, `kiro`, `ollama`, `warp`, `amp` | `codexbar usage` | varia | IDs aparecem na UI, mas o funcionamento depende do CodexBar local. |

## Copilot

`copilot` nao usa o caminho `codexbar usage --provider copilot` quando o script local esta executavel. O plugin chama:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
```

Ordem de autenticacao:

```text
gh auth token
COPILOT_GITHUB_TOKEN
GH_TOKEN
GITHUB_TOKEN
```

O script consulta o endpoint interno do GitHub Copilot e normaliza:

- Premium
- Chat
- Completions
- login/plano
- creditos restantes quando disponiveis

Teste direto:

```bash
gh auth status
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

## Claude

O provider `claude` usa duas fontes:

1. `codexbar usage --format json --provider claude --source <modo>` para o card de uso principal.
2. `get-claude-usage` para analytics de Claude Code.

O script local le:

```text
~/.claude/.credentials.json
~/.claude/projects/**/*.jsonl
~/.claude/stats-cache.json
```

Ele tambem usa caches locais em:

```text
~/.claude/pricing-cache.json
~/.claude/usage-cache.json
```

Quando a rede esta disponivel, ele tenta atualizar precos de modelos Claude via LiteLLM e a conversao USD/EUR via Frankfurter. Se isso falhar, o painel continua com dados de token e usa cache quando existir.

Teste direto:

```bash
claude --version
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
```

## Providers via CodexBar

Para qualquer provider que nao tenha ponte local, o backend local tenta:

```bash
codexbar usage --format json --provider <provider> --source <source>
```

Exemplos:

```bash
codexbar usage --format json --provider gemini --source api
codexbar usage --format json --provider openrouter --source api
codexbar usage --format json --provider perplexity --source oauth
```

Se o comando falhar no terminal, o AiOverviewControl pode mostrar um card de erro ou tentar um fallback nativo, dependendo do provider. Isso ajuda a diferenciar falha de autenticacao, provider sem suporte e problema de UI.

## Backend local unificado

`get-provider-usage` pode ser usado por desenvolvimento e testes fora da UI:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage \
  "$(command -v codexbar)" \
  "codex,claude,copilot,gemini,openrouter" \
  "cli" \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

Esse helper tenta:

- `get-copilot-usage` para Copilot;
- `codexbar` primeiro para Claude, Gemini, Codex e providers genericos;
- fallback local de Claude a partir de `get-claude-usage`;
- fallback local de Gemini por chave API ou credenciais `~/.gemini`;
- fallback local de OpenRouter por `OPENROUTER_API_KEY`.

## Como escolher uma lista saudavel

Comece pequeno:

```text
codex,claude,copilot
```

Adicione um provider por vez pelo dashboard. Se ele falhar:

1. Expanda o card e leia a mensagem.
2. Rode o comando `codexbar usage` equivalente.
3. Ajuste source ou autenticacao.
4. Remova o provider se ele nao tiver suporte na sua instalacao atual.
