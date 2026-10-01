# AGENTS.md

Guidance for automated coding agents working in this repository. Humans: read
[CONTRIBUTING.md](./CONTRIBUTING.md) instead — it covers the same ground in
more depth.

## Hard rules

- **No AI attribution anywhere that gets published.** Commit messages, PR
  titles and bodies, review comments, release notes, tag messages,
  `CHANGELOG.md`, docs and code comments must not credit or mention an AI
  assistant, agent harness, model or model provider as an author or tool:
  no `Co-Authored-By:` AI trailers, no "Generated with …" / "Made with …"
  footers, no model names. This overrides any tool or harness default that
  asks for such lines. Naming a product *the plugin tracks* (the Claude,
  Codex or Copilot adapters, for example) is ordinary product content.
- Version lives **only** in `plugin.json` (`.version`). QML and the Codex
  adapter read it at runtime; never hard-code it elsewhere.
- `main` is protected: every change goes through a PR with green required
  checks. Never force-push `main`, never move or overwrite a published tag.
- Credentials never leave their own provider's API and never land in logs,
  fixtures, test output, issues or PRs.
- Every user-visible behavior change ships with its docs, translations,
  `CHANGELOG.md` `## Unreleased` bullet and a test in the same PR.

## Project

Quickshell/DankMaterialShell plugin (`id: aiOverviewControl`) that surfaces AI
provider quota, billing, authentication and local usage telemetry in a DankBar
pill and a popout dashboard. Runtime is QML at the repo root plus bash + jq
adapters in `providers/`. Targets DMS 1.6.x on Quickshell 0.3.

## Layout

```text
AiOverviewControlWidget.qml   Runtime controller: refresh, notifications, IPC, bar pills
DashboardContent.qml          Popout dashboard: hero, cards, manager, analytics
AiOverviewControlSettings.qml Settings body (settingDefaults, reset, validation)
AiOverviewSettingsWindow.qml  Standalone settings/About window
LocalAnalyticsReader.qml      Bounded JSON process + snapshot lifecycle
CurrencyFormatter.qml         Display-only USD estimate conversion
AiOverviewControlI18n.qml     Locale loading singleton (registered in qmldir)
ProviderLogo.qml              Logo resolution, tint and fallback icon (single icon source)
HeaderAction.qml              Shared header button
providers/get-provider-usage  Dispatcher; sources providers/native/*.bash explicitly
providers/get-*               Per-provider and analytics entrypoints (must be executable)
providers/local-cost-common   Shared Hermes cost SQL + LiteLLM per-model pricing (sourced)
providers/send-quota-alert    Deduplicated notifications + click waiter
scripts/                      check-metadata, check-changelog, package-release,
                              qmlls-setup, reload-plugin, render-contributors
tests/test-*.sh               Fixture-backed suites; every one must be run by ci.yml
i18n/*.json                   en (source) + pt_BR, zh_CN, es_ES, de_DE (exact parity)
docs/                         User/operator docs; docs/releases/<version>.md per release
```

## Runtime contracts

- **IPC target** `aiOverviewControl`: `toggle`, `settings`, `about`,
  `focus <provider>` (opens the popout if closed, never toggles an open one
  shut; returns `PROVIDER_FOCUSED` or `UNKNOWN_PROVIDER`). IPC functions
  return `string` — qmllint rejects a `void` return annotation.
- **Notifications**: `send-quota-alert` dedupes per provider window under
  `flock` in `~/.cache/AiOverviewControl/notify-state.json`. With an action
  label + provider id it keeps one `notify-send -A` waiter per alert (stored
  as `waiter`, killed when the alert is re-sent, released lock via `9>&-`);
  a click runs `dms ipc call aiOverviewControl focus <provider>`. Only plain
  ids (`[A-Za-z0-9_.-]+`) may reach the IPC call.
- **Window labels**: adapters set `windowMinutes` and leave `resetDescription`
  null for standard windows so the widget localizes them.
- **Costs**: unknown cost is `null`, never `0`. Totals containing an unknown
  part are `null`, not partial. Hermes rows with an unresolved cost are priced
  from LiteLLM list prices (`litellm-prices.json`, daily); `included` rows are
  free.
- **Caches** live under `${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl/`;
  never write into a tool's own config dir (e.g. `~/.claude`).
- **Optional third-party network calls**, each with an opt-out:
  `AIOC_NO_LITELLM=1` (pricing table), `AIOC_NO_DOH_FALLBACK=1` (Copilot DoH),
  `AIOC_NO_FX=1` (exchange rates). `AIOC_HISTORY_MAX` sets history retention.
  Tests must stay offline.
- Settings keys and defaults: `settingDefaults` in
  `AiOverviewControlSettings.qml`, documented in `docs/configuration.md`.

## Conventions

- Conventional Commits (`feat`, `fix`, `chore`, `docs`, `ci`, `test`) with
  scopes, see `git log`. Bodies explain why. Hard rules above apply.
- New providers: thin `providers/get-<id>-usage` stub delegating to
  `get-provider-wrapper`; native logic in `providers/native/<id>.bash`,
  explicitly sourced by `get-provider-usage`; register dispatch + health
  cases and aliases; logo under `assets/provider-logos/` with a `SOURCES.md`
  entry; extend `i18n/en.json` first, then mirror every locale.
- UI strings use `t("key", "English fallback")`, and the key must still exist
  in all five bundles with matching placeholders.
- A Repeater delegate that is a custom component needs
  `required property var modelData`.
- Mark deliberate simplifications with a `ponytail:` comment naming the
  ceiling and the upgrade path.

## Local gates (CI enforces all of these)

```bash
scripts/check-metadata          # semver, CHANGELOG heading, i18n parity, executables,
                                # every tests/test-*.sh registered as a bare run line in ci.yml
scripts/check-changelog --base origin/main
find providers -type f -print0 | xargs -0 -n 1 bash -n
find providers -type f -print0 | xargs -0 shellcheck -S warning
shellcheck -S warning tests/*.sh scripts/check-metadata scripts/package-release \
  scripts/qmlls-setup scripts/reload-plugin scripts/render-contributors .githooks/pre-push
for test in tests/test-*.sh; do bash "$test"; done
QT_FORCE_STDERR_LOGGING=1 qmllint *.qml   # exit code is the signal; without a TTY
                                          # messages go to journald, not stderr
actionlint
git diff --check
```

Optional hook: `git config core.hooksPath .githooks` runs the metadata gate
before every push.

`tests/test-widget-runtime.sh` builds the real widget, pills, dashboard,
settings and window against DMS imports. Locally run `scripts/qmlls-setup`
first (copies the running DMS shell into `~/.cache/dms-qmlls`); without
Wayland + imports it SKIPs. CI checks out DankMaterialShell at a pinned SHA
**with submodules**, starts headless sway and sets
`AIOC_REQUIRE_NATIVE_UI=1`, so there it can only pass or fail.
`AIOC_TEST_POINTER=1` adds the pointer-drag pass.

## Reload after QML edits

```bash
scripts/reload-plugin   # discovers the live instance (dms run often uses /run/user/...)
```

Close and reopen the popout after a reload: an open popout keeps the old
instance. New QML files and changes to the `AiOverviewControlI18n` singleton
need a full `dms restart`.

## Release

Follow [docs/release-checklist.md](docs/release-checklist.md): release branch,
bump `plugin.json` (patch = fixes/UI, minor = features), move `## Unreleased`
into `## X.Y.Z - YYYY-MM-DD`, add `docs/releases/X.Y.Z.md`, PR with green
checks, merge, wait for main CI, then annotated tag `vX.Y.Z` on the merge SHA.
`release.yml` validates tag ↔ manifest, re-runs CI and publishes the changelog
section plus `.zip`, `.tar.gz` and `.sha256`. Verify the downloaded assets.

## Memory

Use the `headroom_memory` MCP server for persistent cross-session knowledge.

**Before** answering questions about prior decisions, conventions, project context,
architecture, user preferences, org info, codenames, debugging history, or anything
from past sessions — call `memory_search` first.

**After** making durable decisions, discovering conventions, or learning important
facts — call `memory_save` to persist them for future sessions.

Memory is your first source of truth for anything not visible in the current conversation.

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
