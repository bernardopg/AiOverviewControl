# AiOverviewControl

Self-contained DankMaterialShell widget for AI quota, billing, authentication, and local usage telemetry.

![AiOverviewControl](./screenshot.png)

## What changed in 1.3

- The plugin owns provider collection end to end. No external aggregation executable is used.
- Codex limits come from the official `codex app-server` protocol.
- Copilot reuses the authenticated GitHub session to read the account's Copilot quota snapshot.
- Provider cards distinguish measured quota, authenticated status, local analytics, and informational-only coverage.
- Settings include prerequisite health, compact/comfortable density, provider selection, and diagnostics.
- The dashboard adds provider filtering when more than eight cards are configured.

## Requirements

- DankMaterialShell on Quickshell.
- Core commands: `bash`, `jq`, and `curl`.
- Provider-specific CLIs or environment variables only for providers you enable.

Recommended local setup:

```bash
command -v bash jq curl
command -v codex claude gh
codex login
gh auth login
```

## Install

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a . ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

Enable **AiOverviewControl** in DMS and add it to a DankBar section.

## Provider model

Every provider is classified honestly:

| Coverage | Meaning |
| --- | --- |
| Quota | A provider or CLI surface returns limits, balance, or billing usage. |
| Local analytics | The plugin reads local provider-owned logs or databases. |
| Authentication | A documented endpoint verifies credentials, but no public quota endpoint exists. |
| Informational | No public read-only quota API exists; the card points to the official usage surface. |

The complete matrix and source links are in [docs/providers.md](./docs/providers.md) and [docs/provider-verification.md](./docs/provider-verification.md).

## Validate

```bash
jq . plugin.json
bash -n providers/get-*
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml
./providers/get-codex-usage | jq .
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
```

## Documentation

- [Installation](./docs/installation.md)
- [Configuration](./docs/configuration.md)
- [Providers](./docs/providers.md)
- [Provider verification](./docs/provider-verification.md)
- [Architecture](./docs/architecture.md)
- [Troubleshooting](./docs/troubleshooting.md)
- [Português do Brasil](./docs/README.pt-BR.md)
- [Crowdin and i18n](./docs/i18n-crowdin.md)

## Design guarantees

- One provider failure never hides healthy providers.
- Settings are stored by DMS and are not overwritten by plugin updates.
- The UI uses DMS theme tokens and adapts to narrow popouts.
- Unsupported quota claims are represented as informational states, not fabricated percentages.

Released under [LICENSE](./LICENSE).
