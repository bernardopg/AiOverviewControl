# Shared aggregation for local harness records. Null cost means unavailable;
# never present a partial sum as the total cost of a window.
def total:
  {tokens: (map(.tokens // 0) | add // 0),
   input: (map(.input // 0) | add // 0),
   output: (map(.output // 0) | add // 0),
   cacheRead: (map(.cacheRead // 0) | add // 0),
   reasoning: (map(.reasoning // 0) | add // 0),
   calls: (map(.calls // 0) | add // 0),
   sessions: (map(.session) | unique | length),
   cost: (if any(.[]; .cost == null) then null else (map(.cost) | add // 0) end)};
. as $rows
| ($today | strptime("%Y-%m-%d") | mktime) as $epoch
| [range(6; -1; -1) as $offset
   | ($epoch - $offset * 86400 | strftime("%Y-%m-%d")) as $date
   | ([$rows[] | select(.date == $date)] | total)
     + {date: $date, weekday: ($epoch - $offset * 86400 | strftime("%a"))}] as $days
| [$rows[] | select(.date >= $days[0].date and .date <= $today)] as $week
| {days: $days,
   today: ([$rows[] | select(.date == $today)] | total),
   week: ($week | total),
   month: ([$rows[] | select(.date >= $month and .date <= $today)] | total),
   topModels: ($week | group_by(.model) | map((total) + {model: .[0].model}) | sort_by(-.tokens) | .[:6]),
   topProjects: ($week | map(select(.cwd != null and .cwd != "")) | group_by(.cwd)
     | map((total) + {cwd: .[0].cwd}) | sort_by(-.tokens) | .[:5])}
