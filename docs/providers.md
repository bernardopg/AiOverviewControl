# Providers

AiOverviewControl queries each provider separately and merges results in the dashboard. This prevents a single provider failure from taking down the whole panel.

The widget uses `get-provider-usage` as the local backend. The helper prefers native adapters when available and falls back to `codexbar` for Codex and compatible providers.

## Known IDs

The provider selector recognizes:

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

You can also type provider IDs supported by your `codexbar`, as long as it returns JSON in the expected format.

## Practical matrix

| Provider                                          | Path used                                                      | Best source                  | Notes                                                                                                  |
| ------------------------------------------------- | -------------------------------------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------ |
| `codex`                                           | `get-provider-usage` -> `codexbar usage`                       | `cli`                        | Recommended for local Codex/ChatGPT windows when supported by CodexBar.                                |
| `claude`                                          | `get-provider-usage` -> `codexbar usage` or `get-claude-usage` | `cli`                        | Extra details come from local Claude Code files.                                                       |
| `copilot`                                         | `get-copilot-usage`                                            | independent of global source | Uses authenticated GitHub via `gh` or environment token.                                               |
| `gemini`                                          | `get-provider-usage` -> `codexbar` or local key/OAuth          | `api`, `oauth` or `auto`     | Accepts `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY` or `~/.gemini` credentials. |
| `openrouter`                                      | `get-provider-usage` -> `OPENROUTER_API_KEY` or `codexbar`     | `api`                        | Typically requires token/API configured in CodexBar or `OPENROUTER_API_KEY`.                           |
| `perplexity`                                      | `codexbar usage`                                               | `api` or `oauth`             | Depends on CodexBar support.                                                                           |
| `cursor`, `kilo`, `kiro`, `ollama`, `warp`, `amp` | `codexbar usage`                                               | varies                       | IDs appear in the UI but functionality depends on a local CodexBar.                                    |

## Copilot

When the local Copilot helper is executable, the plugin bypasses `codexbar usage --provider copilot` and calls:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
```

Authentication order:

```text
gh auth token
COPILOT_GITHUB_TOKEN
GH_TOKEN
GITHUB_TOKEN
```

The script normalizes:

- Premium
- Chat
- Completions
- login/plan
- remaining credits when available

Direct test:

```bash
gh auth status
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

## Claude

`claude` uses two sources:

1. `codexbar usage --format json --provider claude --source <mode>` for the main usage card
2. `get-claude-usage` for Claude Code analytics

The local script reads:

```text
~/.claude/.credentials.json
~/.claude/projects/**/*.jsonl
~/.claude/stats-cache.json
```

It also maintains local caches:

```text
~/.claude/pricing-cache.json
~/.claude/usage-cache.json
```

When network is available the helper attempts to refresh Claude model prices via LiteLLM and USD/EUR rates via Frankfurter. If that fails, the panel continues showing token data and uses cache when present.

Direct test:

```bash
claude --version
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
```

## Providers via CodexBar

For providers without a local bridge the local backend runs:

```bash
codexbar usage --format json --provider <provider> --source <source>
```

Examples:

```bash
codexbar usage --format json --provider gemini --source api
codexbar usage --format json --provider openrouter --source api
codexbar usage --format json --provider perplexity --source oauth
```

If the command fails in the terminal, AiOverviewControl may show an error card or try a native fallback depending on the provider. This helps differentiate authentication failures, unsupported providers and UI issues.

## Unified local backend

`get-provider-usage` can be used for development and testing outside the UI:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage \
  "$(command -v codexbar)" \
  "codex,claude,copilot,gemini,openrouter" \
  "cli" \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

This helper attempts:

- `get-copilot-usage` for Copilot
- `codexbar` first for Claude, Gemini, Codex and generic providers
- Claude fallback via `get-claude-usage`
- Gemini fallback via API key or `~/.gemini` credentials
- OpenRouter fallback via `OPENROUTER_API_KEY`

## Choosing a healthy provider list

Start small:

```text
codex,claude,copilot
```

Add one provider at a time from the dashboard. If it fails:

1. Expand the card and read the message.
2. Run the equivalent `codexbar usage` command.
3. Adjust source or authentication.
4. Remove the provider if it is unsupported on your installation.

---

# Providers (PT-BR)

A versao em Portugues original esta preservada no historico do projeto. Use a versao em ingles acima como referencia principal.
