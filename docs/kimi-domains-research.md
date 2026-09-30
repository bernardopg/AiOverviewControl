# Kimi domains and live quota verification

Verified on 2026-09-29. Domain suffixes alone are not a reliable way to distinguish
billing products or determine whether an API key is compatible.

## First-party evidence

The official [Kimi CLI platform registry](https://github.com/MoonshotAI/kimi-cli/blob/9ab1286b8fe4e6bcd116949a27ce5e0ac3389c82/src/kimi_cli/auth/platforms.py)
selects `https://api.kimi.com/coding/v1` for **Kimi Code**, unless explicitly
overridden with `KIMI_CODE_BASE_URL`. It separately registers **Moonshot Open
Platform** at `https://api.moonshot.ai/v1` and `https://api.moonshot.cn/v1`.
These are different products/credentials, not interchangeable URLs.

The official [setup flow](https://github.com/MoonshotAI/kimi-cli/blob/9ab1286b8fe4e6bcd116949a27ce5e0ac3389c82/src/kimi_cli/ui/shell/setup.py)
explicitly tells users whose Code key receives HTTP 401 on another platform to
select Kimi Code instead. Its [usage command](https://github.com/MoonshotAI/kimi-cli/blob/9ab1286b8fe4e6bcd116949a27ce5e0ac3389c82/src/kimi_cli/ui/shell/usage.py)
builds `/usages` from the selected Code base URL and parses `limits[].detail`.

Unauthenticated HTTP HEAD checks found both `www.kimi.ai` and `www.kimi.com`
available, including their `/code/console` pages. `platform.moonshot.ai/console`
redirected to `platform.kimi.ai/console`. This shows that old/new web branding
coexists; it does **not** prove their API hosts or login sessions are equivalent.
A HEAD request to `api.kimi.ai/coding/v1/usages` returned 404; no user credential
was sent to that host. Do not infer country/account migration from these checks.

## Implications for this plugin

- Keep the Code default `api.kimi.com/coding/v1`, matching the first-party CLI.
- Respect explicit `KIMI_CODE_BASE_URL`; retain `KIMI_BASE_URL` as a legacy alias.
  Do not silently try another domain with the user's key.
- Keep Open Platform balance routing separate, with `MOONSHOT_API_BASE` overriding
  its host. A Code subscription is not an Open Platform prepaid balance.
- Prefer `www.kimi.com/code/console` for the Code card. The Open Platform console
  remains `platform.kimi.ai/console`, consistent with the observed redirect.

No default API migration is necessary: the project already uses the first-party
Code base URL and tests override precedence. Explicit overrides are caller-owned;
HTTP success or a web-page alias does not justify automatic credential forwarding.

## Live verification and fixture

A read-only `GET https://api.kimi.com/coding/v1/usages` using the existing system
`KIMI_CODING_API_KEY` returned HTTP 200. No inference request, login change, key
modification, or paid generation was made. No key or account identifier is stored
in the fixture or this document.

Observed fields: `limits[].window.{duration,timeUnit}`, string-valued
`limits[].detail.{limit,used,remaining,resetTime}`, and ratio pools under `usages`
(`limit_5h`, `limit_month_total`, `limit_month_code`). The live response had a
nonzero five-hour limit while its `limit_5h.used_ratio` was zero. The existing
parser correctly gives the detailed limit precedence, and treats the monthly
Code pool as a breakdown rather than a separate quota window.

`tests/fixtures/kimi-code-live-usages.json` captures this structure without
credentials. `tests/test-kimi-code.sh` pins that precedence and simultaneous
balance/subscription cards. Retain the older parser shape: one paid account's
response is not proof that every legacy plan migrated.

When both an Open Platform key and `KIMI_CODING_API_KEY` exist, selecting `kimi`
returns independent `kimi` balance and `kimi-code` subscription cards. Users can
also explicitly select `kimi-code`; the dispatcher deduplicates it. Coding-only
users retain the legacy `kimi` card behavior.
