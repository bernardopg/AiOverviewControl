# Runtime module boundaries

The refactor separates orchestration, presentation, subprocess lifecycle, monetary
display and provider implementations without changing adapter JSON contracts.

## QML

- `AiOverviewControlWidget.qml`: settings-derived state, provider normalization,
  refresh orchestration, ordering/notifications and bar pills. Reduced from about
  5,900 lines to about 2,450.
- `DashboardContent.qml`: popout presentation, hero, manager and provider cards,
  with its 13 internal visual components. It receives a required `controller`,
  and forwards `parentPopout`/`closePopout`. Data and actions remain owned by the
  widget; presentation must not duplicate adapter or exchange-rate logic.
- `LocalAnalyticsReader.qml`: one bounded JSON process, deadline, parser and
  completion signal. `commandArguments` supports both provider-argument readers
  and argument-free analytics scripts. `retainOnFailure` preserves snapshots on
  transport, parse and timeout failures for 9Router/Pi/Hermes; valid error payloads
  still clear them. Codex/OpenCode retain their clear-on-failure policy.
- `CurrencyFormatter.qml`: display-only conversion, quote matching, currency
  selection retry and precision. See [currency.md](currency.md).
- `AiOverviewSettingsWindow.qml`: window/header lifecycle, dynamically loading
  the settings body. The settings body uses `ValueDropdown.values`/`labels`, not
  an invented `choices` interface.

New components load by URL, not newly introduced static types on an old cached
`qmldir`. This matters for live DMS reloads. Reader state uses `result`/`snapshot`,
not `Item.data`. Currency and dashboard bindings remain reactive after loading.
The empty-provider hero is null-safe even while invisible: visibility does not
prevent QML from evaluating its bindings.

## Bash

`get-provider-usage` owns environment/bootstrap, common transport and JSON helpers,
alias routing, normalization and aggregation. Its 33 `fetch_<id>_native` functions
now live in 31 explicitly sourced `providers/native/*.bash` modules. MiniMax's
plan/pay-as-you-go routing is kept together. Modules define functions; imports do
not make requests. Shared helper/state contracts are still explicit dependencies
of these source modules, not a new standalone executable API.

The provider-facing `get-<id>-usage` wrapper interface remains unchanged. New
native implementations belong in a native module, with a matching explicit import
and dispatch/health registration. Explicit source paths allow ShellCheck to
analyze cross-module contracts. Syntax/lint gates recurse into `providers/native`;
source modules need not be executable. Release packaging verifies they exist in
the archived tree.

## Validation boundaries

Offscreen Quickshell suites exercise reader and currency lifecycles without DMS.
`test-widget-runtime.sh` loads real DMS types and constructs horizontal/vertical
pills, empty/populated dashboard, settings and settings window; it tests live
BRL→USD bindings in an isolated fixture HOME with provider scripts replaced and
no inherited credentials. No visible test windows are opened.

The full suite requires Wayland and the import tree from `scripts/qmlls-setup`.
It reports **SKIP**, not a fake pass, without these prerequisites locally. CI
provisions both (pinned DankMaterialShell checkout plus headless sway) and sets
`AIOC_REQUIRE_NATIVE_UI=1`, so there the native suite is a mandatory gate. Neither fixture tests nor
module extraction certify undocumented external billing APIs or every native
pointer gesture.
