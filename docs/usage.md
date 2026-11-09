# Using the dashboard

## Reordering pinned providers

Click and drag the ↕ handle onto another pinned provider card to place it before
that card. No long press is necessary. Dragging the handle does not scroll the
page; scroll or drag elsewhere in the dashboard as usual. Pin a provider with the
star button to expose its reorder handle. The pin order is saved automatically.

## Estimated cost currency

In Settings, choose **Estimated cost currency** (USD by default). Daily reference
rates convert analytics costs for display in EUR, BRL, GBP, CAD, CNY, JPY, AUD or
CHF. The dashboard identifies the quote date and stale cache; missing rates show
USD, never an unconverted amount under another currency label. Storage, exports,
credits and native provider balances remain unchanged. Set `AIOC_NO_FX=1` to
prevent rate requests. See [currency.md](currency.md) for cache and precision.

How the popout, provider cards, settings window, and IPC commands behave once
AiOverviewControl is installed. For the setting keys themselves see
[Configuration](./configuration.md).

<a id="the-dankbar-pill"></a>

## The bar pill

- Shows one entry per provider: logo, name, and the used percentage of its
  quota window. The percentage uses the usage colour scale.
- **Pill mode** picks the providers: `auto` shows every provider with measurable
  usage, `custom` shows an explicit list, `top` shows only the busiest one.
- Providers with more than one quota window (Claude's 5 hour and 7 day, for
  example) can show any window in the bar. Pick it per provider in
  **Bar usage window**, or choose `highest` to follow the most-constrained
  window. **Primary + secondary** and **All windows** show several windows at
  once, each tagged with its length: `Claude 5h 45% / 7d 80%`.
- Hover the pill to see which window each number comes from and when it resets.
  A window heading for exhaustion before its reset (see [Pace](#pace)) adds
  **used up in 2h 10m at this pace**; a window on pace adds nothing.
- Crowded bar? In **Settings → Interface**, turn off **Provider names in pill**
  to keep only the logo and percentage, and turn on **Compact pill spacing** to
  tighten the gap around the `·` between providers. Hovering still names each
  provider.

<a id="the-dankdash-card"></a>

## The Dashboard card

The plugin adds an **AI quotas** card to the Dashboard overview. Open the
overview, hover the page icon, click the pencil, then **Add widget**.

- A 1x1 card shows the provider closest to its limit as one large number.
  Larger cards list as many providers as fit, pinned providers first, with a
  usage bar each; wide or tall cards add the reset time.
- The card follows **Show remaining quota** and the same usage colours as the
  pill. In edit mode its options set how many providers to list and the tone.
- Dux Shell draws the card name and its options, so they follow the Dux Shell language
  (**Settings → Locale**), not the plugin's **Language** setting.
- It reads the snapshot the bar widget writes after each refresh
  (`~/.cache/AiOverviewControl/dash-snapshot.json`, owner-only) and never
  queries a provider itself, so it needs the bar widget to be loaded.
- Click it to open the full dashboard.

## The popout

### Header

| Button | Action |
| --- | --- |
| ❤ | Upvote the plugin on the Dux Shell plugin registry. |
| `<>` | Open the GitHub repository. |
| ⟳ | Refresh every provider now. Spins while a refresh runs. |
| ⚙ | Open the settings window. |
| ✕ | Close the popout. |

Hover a button and the line under the title names its action.

### Hero

- The focused provider (pinned first, otherwise the busiest) with its logo inside
  a ring that shows the primary-window usage, plus its quota bars.
- One stat strip for the fleet: average load, the hottest provider, active and
  failing providers, how many sit at or above 80%, the next reset, and the last
  sync. Fleet-wide figures appear only when two or more providers are live.
- Balance, analytics, local-runtime, and informational cards are excluded from
  the average, so their truthful `0%` placeholders never dilute real quota
  pressure. Peak, at-risk count, and reset still scan every live card.
- Click the hottest provider, or the hero bars, to expand and scroll to that
  provider's card.

### Provider cards

- Sorted with pinned providers first, then by highest measurable usage, with
  failed providers last.
- The capsule on each card pins (★), removes (✕), and expands (⌄) it.
- Keyboard: focus a card, then **Enter**/**Space** expands, **Delete** removes,
  **P** pins, **R** retries a failed provider.
- Data is marked stale after twice the refresh interval: the card shows
  **Stale**, and the bar pill fades that provider's percentage and adds
  **stale since HH:MM:SS** to its tooltip. While an adapter backs off a
  rate-limited or failing endpoint, the card's **Updated** line and the tooltip
  add **Rate limited · next try HH:MM** (or **Endpoint failing**). Failed cards
  offer a provider-specific retry.
- Expanded cards show the available windows, credits, source, identity, and
  update time. Fields a provider does not report are left out, never invented.
- Quota bars carry their [pace](#pace): a tick where an even spend would be,
  and a 🔥 flame next to the number when the window is heading for exhaustion
  before its reset.
- Claude (and each Claude profile) and Codex cards add a **Credits & limit
  resets** panel when expanded: extra usage on or off, the monthly spend limit
  and what was spent, usage credits (promotional credits with their expiry;
  they are used before purchased ones), Codex credits and spend control, and
  each limit reset the account holds with its expiry date. With none, the
  panel says "No resets right now".
- The ⟳ button next to ★ redeems a limit reset; its badge counts the resets
  left. It is disabled when no reset can be used now (a Claude reset may only
  be usable once you reach a limit). Every use opens a confirmation that shows
  the current usage, warns that resets are consumable and cannot be undone,
  and then reports the outcome. When no limit needs a reset, the provider
  refuses it and nothing is used. The plugin never redeems a reset on its own.
- Local-telemetry providers (Claude, 9Router, pi, Hermes) add a seven-day bar
  chart. Hover a bar to see that day's tokens and cost.

## Pace

Every quota bar with a known window length and reset (the card bars, the hero
bars and the Claude details panel) is paced: it compares what you used with
spending the quota evenly over the window.

- A thin **tick** on the bar marks where an even spend would be by now. Two
  hours into a 5 hour window it sits at 40%; with **Show remaining quota** it
  sits at the matching remaining share (60% left). A fill past the tick (short
  of it, in remaining mode) means you are spending faster than even.
- A **flame** appears next to the number only when, at the average rate so
  far, the window runs out before it resets. It needs 15% of the window to
  have passed and the use to be 5 points or more over the even line, so one
  early burst or a window a hair ahead stays quiet.
- Hover a paced bar for the numbers: **Even pace: 40% by now**, then either
  **At this pace: used up in 51m · resets in 3h** or **At this pace it lasts
  until the reset**.
- The projection is linear and labelled as such. Prepaid balances,
  **Unlimited** allowances and windows without a length or a reset are not
  paced; a used-up window keeps its tick but never shows a flame.

## Settings window

The ⚙ button opens a standalone settings window. It hosts the same page as
**Dux Shell Settings → Plugins → AiOverviewControl**, so both write the same values.

The page opens on a **Live preview** of the bar pill, drawn the way the bar
draws it, with a vertical bar beside it and the hover tooltip under it. It
uses sample numbers rather than your real usage and follows every bar setting
at once: pill mode and the providers it shows, names, compact spacing,
remaining quota, the tooltip and each provider's bar usage window.

The settings sit in foldable groups: **General** (language, refresh interval),
**Bar pill**, **Dashboard**, **Notifications**, **Providers** (with a search
field over the 45 adapters, readiness and pinning), **Claude profiles**,
**History and data** and **Diagnostics and tests**. A folded group shows a
one-line summary of its state, such as `Custom · 3 in the bar`; the button
next to the health re-check expands or collapses every group. The page
reopens with **Bar pill** open, next to the preview.

Its header adds links to upvote, the repository, the issue tracker, and an
**About** window with the version, the developer, and ways to support the
project.

## IPC commands

Bind these to compositor shortcuts:

```bash
dms ipc call aiOverviewControl toggle    # open or close the popout
dms ipc call aiOverviewControl settings  # open the settings window
dms ipc call aiOverviewControl about     # open the About window
dms ipc call aiOverviewControl focus claude  # open the popout on one provider's card
```

`focus <provider-id>` opens the popout if it is closed (it never closes an open
one), expands that provider's card and scrolls to it. It returns
`PROVIDER_FOCUSED`, or `UNKNOWN_PROVIDER` for an id that is not on the
dashboard. Quota notifications use it: clicking an alert, or its **Open
dashboard** button, jumps straight to the provider that crossed the threshold.
With several bars, the popout opens on the bar instance that owns the IPC
target, as with `toggle`.

Hyprland example:

```ini
bind = SUPER, U, exec, dms ipc call aiOverviewControl toggle
```

## Usage history

Codex reset-credit balances are also retained as optional `creditBalance`
readings, including zero. They do not create percentage sparklines. CSV exports
append `credit_balance`; unavailable percentages/balances are empty rather than
fabricated zeroes. See [the persistence contract](development-gates.md#codex-credit-snapshots).

- Snapshots are stored in `~/.cache/AiOverviewControl/usage-history.jsonl` and
  trimmed to the configured retention.
- Percentage snapshots record only real non-zero quota or spend pressure; Codex reset-credit readings are stored separately within each snapshot. Informational,
  local-runtime, balance-only, and analytics-only placeholders are skipped, so
  sparklines stay meaningful.
- The store is trimmed, so export it to keep long-term data: use the
  **Export usage history** buttons in settings, or run
  `providers/export-usage-history csv|jsonl`.

## Privacy and resilience

- Credentials come from provider CLIs, provider-owned local data, or environment
  variables. The UI never shows secret values.
- The plugin never scrapes authenticated web dashboards and never calls paid
  inference endpoints just to test a key.
- Temporary files are isolated per run and removed when collection finishes.
- A provider error is returned as structured data, so one timeout or bad
  credential never hides the healthy providers.
- Each Claude provider's local analytics travel with its own result, so an
  OAuth failure still leaves its local history and costs visible, and a
  Claude failure never blocks the other providers.
- Informational cards use explicit text and official links, never synthetic
  percentages.

## Network endpoints

Every credential is sent only to its own provider's official API. Beyond those,
the plugin contacts exactly three third-party hosts, all optional:

- **`raw.githubusercontent.com`** — the Claude and Hermes adapters refresh
  LiteLLM's public pricing table (`model_prices_and_context_window.json`) once
  a day to price local session tokens. No credential or usage data is sent; the request
  is a plain unauthenticated GET. On failure the last cached snapshot is used;
  without any snapshot, Claude cost fields report 0.00 and unresolved Hermes
  costs stay unknown. Set `AIOC_NO_LITELLM=1` to
  disable this fetch entirely.
- **`dns.google`** — the Copilot adapter uses DNS-over-HTTPS only as a
  fallback after a regional `api.github.com` route fails before HTTP, to
  resolve an alternate GitHub edge IP. TLS hostname verification stays enabled
  (`curl --resolve`), and no credential crosses this lookup. Set
  `AIOC_NO_DOH_FALLBACK=1` to disable it.
- **`api.frankfurter.dev`** — only when a non-USD **Estimated cost currency** is
  selected, `get-exchange-rates` reads the day's USD reference rate for that
  currency, cached for 24 hours. Only currency codes are sent. Set
  `AIOC_NO_FX=1` to disable it; costs then stay in USD. See
  [currency.md](currency.md).

All caches are written under `${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl/`.
The plugin never writes into another tool's config directory; Claude Code's
own `stats-cache.json` is only read.

## Antigravity access mechanism

The Antigravity provider is disabled unless you select it. When enabled, it
reads Google refresh tokens from your local Antigravity sessions — the `agy`
CLI token file, the desktop keyring, or the IDE's `state.vscdb` SQLite
database — and exchanges them with Google's OAuth token endpoint using the
Cloud Code client credentials embedded in the public Antigravity/gemini-cli
bundle (not secrets; any install exposes them). Quota is then read from
Google's internal Cloud Code endpoints with the IDE's User-Agent. Refresh
tokens only ever travel to `oauth2.googleapis.com`, form-encoded via stdin so
they never appear in process arguments, and bearer tokens use an ephemeral
curl config descriptor. Nothing is sent to any other host.
