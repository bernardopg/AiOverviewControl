# Changelog

## 1.1.1 - 2026-04-29

- Increased dashboard scale from a compact utility panel to a larger floating control surface.
- Enlarged provider cards, icons, metric tiles, progress bars, and dashboard summary typography.
- Added collapsed-card progress previews so each provider card has useful status at rest.
- Tightened runtime guards for providers that return errors without usage data.
- Removed AiOverviewControl QML warnings caused by rendering account metrics for unsupported providers.

## 1.1.0 - 2026-04-29

- Reworked the popout into a larger provider dashboard.
- Added foldable provider cards with provider-specific accents.
- Integrated Claude Code usage analytics into AiOverviewControl.
- Added daily activity, model mix, token consumption, and Claude subscription limit details.
- Disabled the separate `claudeCodeUsage` widget locally.
- Added project documentation, changelog, and TODO tracking.

## 1.0.0 - 2026-04-29

- Created AiOverviewControl as a renamed and expanded successor to the DMS CodexBar widget.
- Added configurable provider sets and source modes.
- Added Linux-friendly `cli` default.
- Added partial provider failure handling.
