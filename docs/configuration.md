# Configuracao

As opcoes ficam em **DMS Settings > Plugins > AiOverviewControl**. O dashboard tambem permite adicionar e remover providers diretamente.

## Runtime

### Refresh Interval

Define a frequencia de coleta.

Valores comuns:

```text
60000    1 minuto
120000   2 minutos
300000   5 minutos
900000   15 minutos
1800000  30 minutos
```

Use `120000` para acompanhamento ativo. Use `300000` ou mais se voce tiver muitos providers, estiver em rede lenta ou quiser reduzir chamadas aos servicos.

### Optional fallback

Caminho opcional para o executavel `codexbar`.

Se vazio, o widget tenta:

```text
PATH
~/.local/bin/codexbar
/usr/local/bin/codexbar
```

Configure um caminho absoluto quando houver mais de uma instalacao ou quando o DMS nao herdar o mesmo `PATH` do seu terminal.

O plugin ainda funciona com helpers locais quando `codexbar` nao existe, mas Codex e providers genericos normalmente precisam do fallback `codexbar`.

Exemplo:

```text
/home/user/.local/bin/codexbar
```

## Providers

### Provider Set

Atalho para listas comuns:

```text
codex
claude
copilot
codex,claude
codex,claude,copilot
codex,claude,copilot,gemini,openrouter,perplexity
```

### Custom provider list

Campo livre para lista separada por virgula. O plugin normaliza para minusculas, remove espacos e elimina duplicados.

Exemplos:

```text
codex,claude,copilot
codex,claude,copilot,gemini
openrouter,perplexity,cursor
```

Evite manter providers que sempre falham se voce quer um painel mais limpo. Falhas sao isoladas por card, mas ainda ocupam espaco.

## Fallback source

Modo passado para o backend local. Quando o provider usa fallback CodexBar, o mesmo valor segue para `codexbar usage`.

```text
cli    melhor padrao no Linux para telemetria local de assinatura
auto   deixa o CodexBar escolher
oauth  usa autenticacao OAuth quando o provider e o CodexBar suportam
api    usa tokens/API configurados no CodexBar
web    usa dashboards web quando o CodexBar suporta
```

Recomendacao atual para Linux:

```text
cli
```

O modo `web` pode depender de estrategias macOS-only em alguns providers. O modo `api` e util para providers com token de API ou adapter local, mas nem sempre representa consumo de assinatura.

## Show Provider Errors

Mantenha `true` durante configuracao. Isso faz providers quebrados aparecerem como cards de atencao, com a mensagem retornada pelo `codexbar` ou pelo script local.

Depois de estabilizar sua lista, voce pode usar `false` para esconder cards em erro e manter o dashboard mais limpo.

## Configuracao recomendada por cenario

### Uso pessoal com Codex, Claude e Copilot

```text
Provider Set: codex,claude,copilot
Source Mode: cli
Refresh Interval: 120000
Show Provider Errors: true
```

### Muitos providers API

```text
Provider Set: lista customizada
Source Mode: api
Refresh Interval: 300000
Show Provider Errors: true
```

### Barra minimalista

```text
Provider Set: codex
Source Mode: cli
Refresh Interval: 300000
Show Provider Errors: false
```

## Onde as configuracoes aparecem na UI

- DankBar pill: mostra o percentual do provider bem-sucedido mais perto do limite.
- Header do popout: mostra ultimo refresh e source mode.
- Overview: total de providers ativos, providers em atencao, engine local e fallback resolvido.
- Provider cards: mostram conta, origem, progresso, reset e controles de remover/expandir.
