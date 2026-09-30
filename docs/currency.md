# Analytics cost currency

Settings → **Estimated cost currency** selects USD (default), EUR, BRL, GBP, CAD,
CNY, JPY, AUD or CHF. The setting is `costCurrency`; reset-to-defaults restores
USD. It applies to analytics cost tiles, model totals, daily tooltips and
projections that call the common cost formatter, across Claude, 9Router, Pi and
Hermes. This does not change provider billing currencies, wallet balances,
credits, pricing inputs, stored history, or export units. Those remain in their
original units; analytics estimates remain USD at the data boundary.

## Formatting and failure behavior

`CurrencyFormatter.qml` owns conversion and locale-aware formatting. Non-USD
amounts carry an explicit ISO currency code, with two decimal places (JPY: zero).
Small positive values use a `<` minimum-unit label; invalid/non-finite costs show
`—`. Switching currencies does not convert an already-converted value.

The dashboard shows the quote date, distinguishes an expired cached quote, and
explicitly says costs are shown in USD when conversion is unavailable. A missing
rate must never label an unconverted USD amount as EUR/BRL/etc. A selection change
while a request runs is queued; the previous currency's response cannot be used
for the new currency.

## Network and cache contract

For non-USD selections, `providers/get-exchange-rates` makes a read-only request
to [Frankfurter v1](https://frankfurter.dev/) at
`https://api.frankfurter.dev/v1/latest?base=USD&symbols=<currency>`.
Only currency codes are sent: no keys, accounts, costs, usage records or provider
credentials. Frankfurter supplies daily reference rates, not live trading quotes;
converted costs are estimates, not an invoice or settlement rate. The latest
available quote applies to both current and historical analytics displays; the
plugin does not fetch the original transaction/day's historical FX rate.

- USD requires no network request.
- `AIOC_NO_FX=1` disables network requests, including cache refresh.
- Cache: `${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl/exchange-rate-<ISO>.json`.
- Fresh-cache TTL: 24 hours. Failure/opt-out may use a valid quote fetched less
  than seven days ago, visibly marked cached/stale; older quotes fall back to USD.
- Cached base/currency/rate/timestamp are validated. Updates are serialized with
  `flock`, atomically renamed, with private directory/file permissions.
- Connection timeout: three seconds; request timeout: eight seconds. The UI
  polls hourly but a fresh cache prevents repeat network requests.

Tests cover cache corruption, wrong bases, missing/zero rates, outages, opt-out,
concurrent refreshes, locale/precision, invalid values and in-flight selection
changes. A full DMS runtime fixture also switches the widget from BRL to USD.
