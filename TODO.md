# TODO

## Provider Data

- Add optional per-provider source overrides instead of one global source mode.
- Add manual custom provider list entry in settings when DMS dropdowns support editable values.
- Add a token-status hint for Copilot when neither `gh auth token` nor GitHub token environment variables are available.

## Dashboard

- Add screenshot assets for the new dashboard layout.
- Add compact/expanded density modes.
- Add a provider filter row when many providers are selected.
- Add stale-data indicators when a provider has not refreshed recently.

## Claude Analytics

- Show today's token count separately from today's estimated cost.
- Add cache status and API fallback messaging for Claude Code usage.
- Add optional EUR display when exchange-rate lookup succeeds.

## Packaging

- Add lightweight shell tests for `get-claude-usage`.
- Add a release checklist for posting to DankMaterialShell plugins.
- Add plugin marketplace metadata when the DMS plugin registry format is finalized.
- Pin action versions com SHA para hardening de supply chain (ex: `actions/checkout@<sha>`).
- Adicionar step de validação dos scripts `get-*` no workflow de CI (shellcheck).
