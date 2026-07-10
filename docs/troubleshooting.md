# Troubleshooting

## No cards appear

```bash
PLUGIN=~/.config/DankMaterialShell/plugins/AiOverviewControl
$PLUGIN/providers/get-provider-health "codex,claude,copilot" | jq .
$PLUGIN/providers/get-provider-usage "codex,claude,copilot" $PLUGIN/providers/get-copilot-usage | jq .
```

If terminal output is valid, run `qmllint` and restart DMS.

## Codex

```bash
codex --version
codex login
./providers/get-codex-usage | jq .
```

The adapter requires a Codex CLI version with `app-server` and `account/rateLimits/read`. Update Codex if the helper reports that rate limits are unavailable.

## Claude

If the local analytics are present but the 5-hour window shows an authentication error, renew the Claude subscription session:

```bash
claude auth login --claudeai
```

The plugin only reuses a successful quota response for two minutes. Expired credentials and older cache files are reported as errors instead of being displayed as `0%` usage.

```bash
claude auth status
./providers/get-claude-usage
```

Claude analytics require readable JSONL files under `~/.claude/projects`. Quota windows are best-effort and may be absent when Claude Code changes its private OAuth behavior.

## Copilot

```bash
gh auth status
gh api user --jq .login
./providers/get-copilot-usage | jq .
```

The adapter uses the GitHub-authenticated Copilot quota snapshot. If the regional `api.github.com` route fails before returning HTTP, it retries through another GitHub edge with normal TLS hostname verification. The last valid response may be reused for up to one hour and is labeled `github-copilot-cache`.

## Environment variable is present in a terminal but missing in settings

DMS may have been started before the variable was exported. Put the variable in the graphical-session environment, restart DMS, and run the health helper again. The helper reports names only, never secret values.

## Provider shows zero percent

Zero can mean one of three things:

- the provider reports a real unused quota;
- the provider exposes balance/status but no total from which a percentage can be calculated;
- the card is informational because no public quota API exists.

Read the card's source and display value rather than assuming every provider has a percentage quota.

## Antigravity quota or account layout

The normal Antigravity view deliberately shows only **Gemini Models** and **Claude & OpenAI Models**. These are family quotas, not placeholders: each reflects the model in that family with the least quota remaining. With multiple locally signed-in accounts, expand the card to see the same two family rows under each account email and install.

If the result looks inconsistent with the Antigravity Models screen, refresh the plugin and check the raw response without exposing credentials:

```bash
PLUGIN=~/.config/DankMaterialShell/plugins/AiOverviewControl
$PLUGIN/providers/get-provider-usage antigravity | jq .
```

For a temporary model-by-model diagnosis, enable **Show individual Antigravity models** in the plugin settings, then expand the Antigravity card. Turn it off again to return to the concise view. If the helper reports no session, open the affected Antigravity installation, sign in, and ensure `sqlite3` is installed.

## Slow refresh or timeout

The widget has a 45-second total timeout. Each network adapter also has a shorter curl timeout. Reduce the selected provider count, increase the refresh interval, and test providers individually.

## QML validation

```bash
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml
for file in i18n/*.json; do jq . "$file"; done
```
