# Kimi Code usage API research

Reviewed 2026-09-20.

## Finding

Kimi Code's current first-party CLI queries `GET {KIMI_CODE_BASE_URL}/usages`.
Its default endpoint is `https://api.kimi.com/coding/v1/usages`; the global
endpoint is `https://api.kimi.ai/coding/v1/usages`. The request uses a bearer
Kimi Code credential and accepts JSON.

The endpoint is not documented in the public Open Platform API reference, so
it must be treated as a best-effort, CLI-owned contract. It is nevertheless
implemented and tested by Moonshot AI's own Kimi Code client:

- [`managed-usage.ts` at commit `65ae3e3`](https://github.com/MoonshotAI/kimi-code/blob/65ae3e368c7cfa096242cacc12eeeb661e682977/packages/oauth/src/managed-usage.ts)
- [`managed-usage.test.ts` at the same commit](https://github.com/MoonshotAI/kimi-code/blob/65ae3e368c7cfa096242cacc12eeeb661e682977/packages/oauth/test/managed-usage.test.ts)

## Current response shapes

The endpoint has two observed shapes which the plugin must support together:

1. **Legacy counted limits**: a top-level `usage`/`data` block and/or
   `limits[]`, with `used`, `limit`, `remaining`, and a self-described
   `window.duration`. A 300-minute `limits[]` entry is the authoritative
   5-hour frequency limit because it includes exact request counts.
2. **Current ratio pools**: top-level `usages` entries containing
   `used_ratio` (0–1) and `reset_time`:
   - `limit_5h` — 5-hour frequency window;
   - `limit_7d` — weekly window, only when the plan returns it;
   - `limit_month_total` — combined monthly allowance;
   - `limit_month_code` — a code-specific monthly measurement.

The official client parses all four ratio entries, but renders only three
independent quota rows: 5h, weekly, and monthly. Its formatter uses
`limit_month_code` as the code share in the `limit_month_total` monthly
breakdown; it is not an additional allowance. The plugin follows that model
and does not turn the breakdown into a second monthly window.

## Consequence for AiOverviewControl

A Kimi Pro response can legitimately have no weekly quota. In that case the
correct dashboard card is:

- **Session / 5h**: exact `used / limit` from `limits[]`;
- **Monthly**: `usages.limit_month_total.used_ratio × 100`, with its reset;
- no separate `limit_month_code` window, because it is a breakdown of Monthly;
- no invented weekly allowance: `limit_7d` only appears when the plan returns it.

This matches the Kimi Code console while preserving precise 5-hour request
counts. The API does not expose model entitlement, plan name, or token/cost
telemetry in this response; those should not be fabricated by the plugin.
