# Using the dashboard

How the popout, provider cards, settings window, and IPC commands behave once
AiOverviewControl is installed. For the setting keys themselves see
[Configuration](./configuration.md).

## The DankBar pill

- Shows one entry per provider: logo, name, and the used percentage of its
  quota window. The percentage uses the usage colour scale.
- **Pill mode** picks the providers: `auto` shows every provider with measurable
  usage, `custom` shows an explicit list, `top` shows only the busiest one.
- Providers with more than one quota window (Claude's 5 hour and 7 day, for
  example) can show any window in the bar. Pick it per provider in
  **DankBar usage window**, or choose `highest` to follow the most-constrained
  window.
- Hover the pill to see which window each number comes from and when it resets.

## The popout

### Header

| Button | Action |
| --- | --- |
| ❤ | Upvote the plugin on the DankLinux plugin registry. |
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
- Data is marked stale after twice the refresh interval. Failed cards offer a
  provider-specific retry.
- Expanded cards show the available windows, credits, source, identity, and
  update time. Fields a provider does not report are left out, never invented.
- Local-telemetry providers (Claude, 9Router, pi, Hermes) add a seven-day bar
  chart. Hover a bar to see that day's tokens and cost.

## Settings window

The ⚙ button opens a standalone settings window. It hosts the same page as
**DMS Settings → Plugins → AiOverviewControl**, so both write the same values.

Its header adds links to upvote, the repository, the issue tracker, and an
**About** window with the version, the developer, and ways to support the
project.

## IPC commands

Bind these to compositor shortcuts:

```bash
dms ipc call aiOverviewControl toggle    # open or close the popout
dms ipc call aiOverviewControl settings  # open the settings window
dms ipc call aiOverviewControl about     # open the About window
```

Hyprland example:

```ini
bind = SUPER, U, exec, dms ipc call aiOverviewControl toggle
```

## Usage history

- Snapshots are stored in `~/.cache/AiOverviewControl/usage-history.jsonl` and
  trimmed to the configured retention.
- Only real non-zero quota or spend pressure is recorded. Informational,
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
- Claude analytics run separately, so local history or OAuth failures cannot
  block the main collection.
- Informational cards use explicit text and official links, never synthetic
  percentages.
