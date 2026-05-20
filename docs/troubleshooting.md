# Troubleshooting

Use this page to identify whether an issue originates from a binary, authentication, provider, local script or rendering.

---

## Quick checklist

```bash
command -v bash
command -v jq
command -v curl
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
test -x ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage
```

Fix any failing check before investigating the UI.

---

## `codexbar not found`

DMS may start with a different `PATH` than your interactive shell.

This only affects providers without a native adapter: `codex`, `perplexity`, `cursor`, `kilo`, `kiro`, `warp`, `amp`, `cline`, `opencode`. All other providers use local adapters and are unaffected.

Solutions:

1. Set **Optional fallback** in settings to the absolute path of `codexbar`.
2. Verify the binary is executable: `ls -l $(command -v codexbar)`.
3. Restart DMS.

---

## Provider shows as error card

Test the provider outside the widget using the direct backend:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage \
  "$(command -v codexbar)" \
  "<provider-id>" \
  "cli" \
  ~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

Replace `<provider-id>` with the failing provider. Read the `error` field in the output.

---

## Claude

### Main card missing

```bash
codexbar usage --format json --provider claude --source cli
```

### Extra analytics empty

```bash
claude --version
test -f ~/.claude/.credentials.json && echo "credentials ok"
test -d ~/.claude/projects && echo "projects dir ok"
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-claude-usage
```

Remove stale caches if data looks frozen:

```bash
rm -f ~/.claude/usage-cache.json ~/.claude/pricing-cache.json
```

---

## Copilot

```bash
gh auth status
gh auth token >/dev/null && echo "gh token ok"
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-copilot-usage | jq .
```

If output shows HTTP 401 or 403: re-authenticate with `gh auth login` and confirm Copilot is enabled on your GitHub account.

Token fallbacks if `gh` is not installed:

```bash
export COPILOT_GITHUB_TOKEN=ghp_...
export GH_TOKEN=ghp_...
export GITHUB_TOKEN=ghp_...
```

---

## DeepSeek

```bash
export DEEPSEEK_API_KEY=sk-...
curl -s https://api.deepseek.com/user/balance \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" | jq .
```

Expected: `balance_infos` array with `total_balance`, `topped_up_balance`, `granted_balance`.

---

## Kimi (Moonshot)

```bash
export MOONSHOT_API_KEY=sk-...   # or KIMI_API_KEY
curl -s https://api.moonshot.cn/v1/users/me/balance \
  -H "Authorization: Bearer $MOONSHOT_API_KEY" | jq .
```

Expected: `data.available_balance`, `data.voucher_balance`, `data.cash_balance`.

---

## MiniMax

```bash
export MINIMAX_API_KEY=...
curl -s https://www.minimax.io/v1/token_plan/remains \
  -H "Authorization: Bearer $MINIMAX_API_KEY" | jq .
```

---

## GLM (Zhipu AI)

```bash
export GLM_API_KEY=...   # or ZHIPU_API_KEY
curl -s https://bigmodel.cn/api/monitor/usage/quota/limit \
  -H "Authorization: Bearer $GLM_API_KEY" | jq .
```

If using the international endpoint, set `GLM_API_BASE=open.bigmodel.cn` and re-test.

---

## Mistral

Mistral has no public quota endpoint. The card shows a note-card (not an error) when the key is valid. If you see an error card instead, the key failed validation:

```bash
export MISTRAL_API_KEY=...
curl -s https://api.mistral.ai/v1/models \
  -H "Authorization: Bearer $MISTRAL_API_KEY" | jq '.data | length'
```

A number (even 0) means auth succeeded. An error object means the key is invalid or missing.

---

## Ollama

```bash
curl -s http://localhost:11434/api/tags | jq '.models[].name'
```

If Ollama runs on a different host or port:

```bash
export OLLAMA_HOST=http://192.168.1.x:11434
```

---

## NVIDIA NIM

```bash
export NVIDIA_API_KEY=nvapi-...
curl -s https://integrate.api.nvidia.com/v1/models \
  -H "Authorization: Bearer $NVIDIA_API_KEY" | jq '.data | length'
```

NIM has no balance endpoint; the card is a note-card by design.

---

## Cloudflare AI

Both `CLOUDFLARE_ACCOUNT_ID` and a token are required:

```bash
export CLOUDFLARE_ACCOUNT_ID=...
export CLOUDFLARE_AI_TOKEN=...   # or CLOUDFLARE_API_TOKEN
curl -s "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/ai/usage" \
  -H "Authorization: Bearer $CLOUDFLARE_AI_TOKEN" | jq '.result'
```

Token needs `AI Gateway:Read` permission (or `Account:AI Gateway:Read`).

---

## Vertex AI

```bash
gcloud auth print-access-token
gcloud config get-value project
```

If either command fails, run `gcloud auth login` and set the project:

```bash
gcloud config set project YOUR_PROJECT_ID
```

The card shows a note-card (not an error) when auth succeeds; Vertex AI has no programmatic quota endpoint.

---

## BytePlus ModelArk

```bash
export BYTEPLUS_API_KEY=...   # or ARK_API_KEY
curl -s https://ark.ap-southeast.bytepluses.com/api/v3/models \
  -H "Authorization: Bearer $BYTEPLUS_API_KEY" | jq '.data | length'
```

---

## Qwen / DashScope

```bash
export DASHSCOPE_API_KEY=sk-...   # or QWEN_API_KEY
curl -s https://dashscope.aliyuncs.com/compatible-mode/v1/models \
  -H "Authorization: Bearer $DASHSCOPE_API_KEY" | jq '.data | length'
```

---

## 9Router vs OpenRouter both showing same name

Both IDs must be present in the provider list with distinct cards. If they look identical, verify the widget version is ≥ 1.2.2 where the `providerName()` fix was applied:

- `9router` → "9Router"
- `openrouter` → "OpenRouter"

---

## Empty panel

Possible causes:

- `get-provider-usage` is not executable.
- All configured providers failed.
- Custom provider list is empty or contains invalid IDs.
- First refresh still running.

Minimum test:

```text
Provider Set:         claude
Source Mode:          cli
Show Provider Errors: true
```

Then:

```bash
~/.config/DankMaterialShell/plugins/AiOverviewControl/get-provider-usage \
  "" "claude" "cli" "" | jq .
```

---

## Slow or cluttered panel

Each provider is queried sequentially. Many providers, slow networks or API timeouts make refreshes heavy.

Improvements:

- Increase **Refresh Interval** to `300000` or higher.
- Remove providers that consistently fail.
- Prefer `cli` for local providers.
- Use `api` only when tokens are set and providers respond quickly.

---

## Validate QML

```bash
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml
```

Install Qt/Quickshell tooling if `qmllint` is missing.
