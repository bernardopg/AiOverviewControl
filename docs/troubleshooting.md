# Troubleshooting

Use this page to identify whether an issue originates from a binary, authentication, provider, local script or rendering.

## Quick checklist

```bash
command -v bash
command -v node
command -v jq
command -v curl
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage
```

If a local helper fails, fix it before digging into the UI. `codexbar` is recommended for Codex and generic providers but is not the only collection path.

## `codexbar not found`

DMS may start with a different `PATH` than your interactive shell.

This affects Codex and providers without a local adapter. Copilot, Gemini with local key, OpenRouter with local key and Claude details may still work via helpers.

Solutions:

1. Configure **Optional fallback** with the absolute path to `codexbar`.
2. Ensure the file exists and is executable.
3. Restart DMS.

Useful commands:

```bash
command -v codexbar
ls -l ~/.local/bin/codexbar /usr/local/bin/codexbar 2>/dev/null
```

## Provider shown as error

Test the provider outside the widget:

```bash
codexbar usage --format json --provider codex --source cli
codexbar usage --format json --provider claude --source cli
codexbar usage --format json --provider gemini --source api
```

If the terminal command fails, adjust authentication, source mode or remove the provider from the list. AiOverviewControl preserves working providers even when others fail.

Use the main helper to test full aggregation outside the UI:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage \
  "$(command -v codexbar)" \
  "codex,claude,copilot,gemini,openrouter" \
  "cli" \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

## Copilot shows no usage

The local script requires a valid GitHub token.

Test:

```bash
gh auth status
gh auth token >/dev/null && echo ok
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

Token alternatives:

```bash
export COPILOT_GITHUB_TOKEN=...
export GH_TOKEN=...
export GITHUB_TOKEN=...
```

If you see HTTP 401/403, re-authenticate with `gh auth login` and confirm your account has Copilot enabled.

## Claude missing extra details

The main Claude card may work via CodexBar while extra details remain empty. This usually indicates a missing CLI, credentials or local logs.

Check:

```bash
claude --version
test -f ~/.claude/.credentials.json
test -d ~/.claude/projects
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
```

Script dependencies:

```bash
command -v jq
command -v curl
```

The helper uses caches to reduce requests and tolerate rate limits. If stale data appears, wait a few minutes or remove caches only if you intend to force a fresh read:

```bash
rm -f ~/.claude/usage-cache.json ~/.claude/pricing-cache.json
```

## Empty panel

Possible causes:

- `get-provider-usage` is not executable.
- All configured providers failed.
- The custom list is empty or contains unsupported IDs.
- The first refresh is still running.

Minimum test:

```text
Provider Set: codex
Source Mode: cli
Show Provider Errors: true
```

Then run:

```bash
codexbar usage --format json --provider codex --source cli
```

## Slow or cluttered panel

Each provider is queried sequentially. Many providers, slow networks or APIs with timeouts can make refreshes heavy.

Practical improvements:

- Increase **Refresh Interval** to `300000` or higher
- Remove providers that always fail
- Prefer `cli` for local providers
- Use `api` only when tokens are configured and the provider responds quickly

## Validate QML

During development:

```bash
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml
```

If `qmllint` is missing, install Qt/Quickshell tooling for your distribution.

---

# Troubleshooting (PT-BR)

As notas originais em Portugues estao preservadas no historico do projeto. Use a versao em ingles acima como referencia principal.
