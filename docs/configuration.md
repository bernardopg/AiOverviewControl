# Configuration

Settings live in **DMS Settings > Plugins > AiOverviewControl**. The dashboard also allows adding/removing providers directly.

## Runtime

### Refresh Interval

Defines the collection frequency.

Common values:

```text
60000    1 minute
120000   2 minutes
300000   5 minutes
900000   15 minutes
1800000  30 minutes
```

Use `120000` for active monitoring. Increase to `300000` or higher when you have many providers, a slow network or want to reduce API calls.

### Optional fallback

Optional path to the `codexbar` executable.

If empty, the widget tries:

```text
PATH
~/.local/bin/codexbar
/usr/local/bin/codexbar
```

Set an absolute path when multiple installations exist or when DMS does not inherit your interactive shell `PATH`.

The plugin still works with local helpers when `codexbar` is missing, but Codex and generic providers usually require the `codexbar` fallback.

Example:

```text
/home/user/.local/bin/codexbar
```

## Providers

### Provider Set

Shortcuts for common lists:

```text
codex
claude
copilot
codex,claude
codex,claude,copilot
codex,claude,copilot,gemini,openrouter,perplexity
```

### Custom provider list

Comma-separated free text. The plugin normalizes to lower-case, trims spaces and removes duplicates.

Examples:

```text
codex,claude,copilot
codex,claude,copilot,gemini
openrouter,perplexity,cursor
```

Avoid keeping providers that always fail if you prefer a cleaner dashboard. Failures are isolated per card but still occupy space.

## Fallback source

Mode passed to the local backend. When a provider uses the CodexBar fallback, the same value is forwarded to `codexbar usage`.

```text
cli    best default on Linux for local telemetry
auto   let CodexBar choose
oauth  use OAuth where supported
api    use API tokens configured in CodexBar
web    use web dashboards when CodexBar supports them
```

Current recommendation for Linux:

```text
cli
```

The `web` mode may rely on macOS-only strategies for some providers. `api` is useful for providers with API tokens or local adapters but does not always represent subscription consumption.

## Show Provider Errors

Keep `true` while configuring. This shows broken providers as attention cards with the message returned by `codexbar` or the local script.

After stabilizing your list, set `false` to hide error cards and keep the dashboard minimal.

## Recommended configurations

### Personal use (Codex, Claude, Copilot)

```text
Provider Set: codex,claude,copilot
Source Mode: cli
Refresh Interval: 120000
Show Provider Errors: true
```

### Many API-based providers

```text
Provider Set: custom list
Source Mode: api
Refresh Interval: 300000
Show Provider Errors: true
```

### Minimal bar

```text
Provider Set: codex
Source Mode: cli
Refresh Interval: 300000
Show Provider Errors: false
```

## Where settings appear in the UI

- DankBar pill: shows the percent of the successful provider closest to quota
- Popout header: shows last refresh and source mode
- Overview: total active providers, providers in attention, local engine and resolved fallback
- Provider cards: show account, origin, progress, reset and controls to remove/expand

---

# Configuracao (PT-BR)

As opcoes e exemplos originais em Portugues aparecem acima como referencia. Ajuste conforme sua instalacao local.
