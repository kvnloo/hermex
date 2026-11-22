# 0183. Mission Control

Area: fork

## Build Mission Control only from host lists

Mission Control shows what the host reports and nothing else: the spawn gate and live
delegated workers from `delegation.status`, Tasks from the cron list, and background
processes from `agents.list`, all at the pinned `hermes-agent` commit. It never guesses a
mission from chat text. A section whose method the host doesn't have (`-32601`, 404)
says so instead of showing an empty list.

Lives in: `HermesMobile/Fork/Mission/ForkMissionClient.swift`, `HermesMobile/Fork/Core/Mission/ForkMission.swift`

## Disable a control the host can't honour, and say why

The host's controls are narrow. `delegation.pause` blocks new spawns for the whole host
and leaves running workers alone, so a worker has no Pause or Resume of its own.
`subagent.interrupt`, `subagent.steer` and `process.kill` act only for the gateway
session that owns the child, and Mission Control's own connection owns none, so Stop
on a worker or process would always answer `4001`. A Task run has no stop at all. Each
row therefore lists Pause, Resume, Stop and Retry, and `ForkMission.availability` turns
every command the host can't honour into a disabled one with a `ForkMissionBlock`
reason the screen shows under it. Enabling one of them without a host method behind it
gives the user a button that always fails.

Lives in: `HermesMobile/Fork/Core/Mission/ForkMission.swift`, `HermesMobile/Fork/Mission/ForkMissionControlView.swift`

## Let Retry follow the run like Run Now

Retry on a failed Task uses the same trigger as Run Now (ADR 0153), which answers only
after the run. Mission Control fires it on a task nothing cancels, treats a gateway
timeout as the run going on, and lets its five-second list read show the run, so one
long run doesn't hold every other control disabled.

Lives in: `HermesMobile/Fork/Mission/ForkMissionClient.swift`
