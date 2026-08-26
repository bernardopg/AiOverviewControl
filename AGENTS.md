# AGENTS.md

Guidance for AI agents working in this repository. Humans: read
[CONTRIBUTING.md](./CONTRIBUTING.md) instead — it covers the same ground in
more depth.

## Project

Quickshell/DankMaterialShell plugin (`aiOverviewControl`) that surfaces AI
provider quota, billing, authentication, and local usage telemetry. Runtime is
QML (4 files at the repo root) plus bash adapters in `providers/`. Version lives
**only** in `plugin.json`.

## Layout

```text
AiOverviewControlWidget.qml       Runtime orchestration and dashboard
AiOverviewControlSettings.qml     Settings UI
AiOverviewControlI18n.qml         Locale loading singleton (registered in qmldir)
ProviderLogo.qml                  Logo resolution/fallback
providers/                        bash entrypoints + get-provider-usage dispatcher
tests/*.sh                        Fixture-backed integration suites (run all before pushing)
i18n/*.json                       en + pt_BR, zh_CN, es_ES, de_DE (exact key parity enforced)
docs/                             User/operator documentation
```

## Conventions

- Commits follow Conventional Commits (`feat`, `fix`, `chore`, `docs`, `ci`,
  with scopes — see `git log`). **Never add AI co-author trailers**
  (`Co-Authored-By: ...` or similar).
- New providers: add a thin `providers/get-<id>-usage` stub delegating to
  `get-provider-wrapper` (native logic goes into `get-provider-usage`), register
  dispatch + health cases and aliases, add a logo under
  `assets/provider-logos/` with a `SOURCES.md` entry, extend `i18n/en.json`
  first, then mirror every locale.
- Docs live in `docs/`; update them in the same change when behavior changes.
  `docs/release-checklist.md` is the release runbook.

## Local gates (CI enforces all of these)

```bash
find providers -maxdepth 1 -type f -print0 | xargs -0 bash -n
for test in tests/*.sh; do bash "$test"; done
bash -n scripts/package-release
shellcheck -S warning providers/* tests/*.sh scripts/package-release
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml ProviderLogo.qml
for f in i18n/*.json; do jq -e . "$f" >/dev/null; done   # plus exact key parity vs i18n/en.json
```

A QML syntax error fails CI. `CHANGELOG.md` needs an entry for any release
version. Release tags are gated on the full reusable CI workflow.

## Reload after QML edits

```bash
qs -p ~/.config/quickshell/dms ipc call plugins reload aiOverviewControl
```

Note: `AiOverviewControlI18n.qml` is a qmldir singleton; a DMS restart (not just
IPC reload) is needed for changes to it.

## Memory

Use the `headroom_memory` MCP server for persistent cross-session knowledge.

**Before** answering questions about prior decisions, conventions, project context,
architecture, user preferences, org info, codenames, debugging history, or anything
from past sessions — call `memory_search` first.

**After** making durable decisions, discovering conventions, or learning important
facts — call `memory_save` to persist them for future sessions.

Memory is your first source of truth for anything not visible in the current conversation.
