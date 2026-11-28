# Platform parity: hermes-android `staging` → hermex `staging`

Kevin, 2026-11-21: "i want my hermex fork to have platform parity to hermes-android".
The feature spec is [kvnloo/hermes-android](https://github.com/kvnloo/hermes-android) `staging`
(`docs/PARITY_CHECKLIST.md`, `docs/APPEARANCE_THEMES.md`, `docs/HANDS_FREE_VOICE.md`, `lib/`).
Status was measured against hermex `staging` = upstream `master` `a9861b9` by reading
the code, the String Catalog and `docs/adr/`. Server shapes are checked against the
hermes-agent gateway contract at the pinned commit (`HERMES_AGENT_TESTED_SHA`,
`apps/shared/src/gateway-contract.openrpc.json`).

**Status:** **has** = hermex already does it (with the file or ADR that shows it);
**partial** = some of it; **missing** = not built. **Branch** is the planned `boat/hermex/*`
branch (cut from `staging`); `—` means nothing to do. **Blocked** names who must decide.

## Hosts and sign-in

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| Add an instance by address and test it | has | Add Server sheet, connection probe (ADR 0138, 0143) | — |
| Password sign-in | has | `AuthManager`, Hermes connection credentials (ADR 0142) | — |
| Provider OAuth sign-in (device code) | has | Settings → Provider Sign-In: host device-code routes, `ASWebAuthenticationSession`, catalog readback without an account claim (ADR 0181) | `boat/hx-rebase/hx-084` |
| Several saved instances (two or more hosts) | has | `ServerAccount` / server registry, per-server isolation (ADR 0131, `docs/agents/multi-server-state-isolation.md`) | — |
| Browser (OIDC) sign-in | has | `HermesBrowserSignIn`: loopback + `ASWebAuthenticationSession` + PKCE (ADR 0140) | — |
| Browser tab closes after sign-in | has | `ASWebAuthenticationSession` (ephemeral) dismisses itself when the loopback redirect lands; the Android open item does not apply | — |
| mTLS client certificates | has | Settings → Hermes server → Client certificate; import a PKCS#12 identity into device-only Keychain for native HTTPS/WSS | `boat/hx-mtls/client-cert` |

Add Server also accepts a client certificate before the connection probe. The system browser used for browser sign-in does not have access to Hermex’s stored identity.

## Home

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| Bot list with last message and time | has | Bots inbox (`BotsInboxView`, ADR 0009/0015) | — |
| Filters (view, sort, recent, show, agents, include groups) | partial | Session list filters and project filter; the Bots inbox has search, not the full filter sheet | later |
| Tree of sessions under each bot (HA-032) | has | Bots inbox: a chevron on each bot row expands its newest five sessions, Show all (N) into that bot's Sessions list, New session (`ForkBotSessionTreeView`, `ForkBotSessionTree`) | `boat/hx-bot-sessions/bot-session-tree` |
| New session sheet with every bot and New group | has | `BotCreateView`, `BotRoomCreateView` (ADR 0011) | — |
| Search filters as you type | has | `BotSearchView`, session search (ADR 0135) | — |
| Bot directory import (`application/vnd.ai.nousresearch.hermes.mobile.bot+json`) | has | Imported type + document type in Info.plist; opening a bot file shows Import Bot with name, title and description, then Add Bot (prefilled `BotCreateView`, profile name from the file) or Open Chat if it exists (`ForkBotImport`, `ForkBotDirectoryDocument`) | `boat/hx-small/hx-019` |

## Chat

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| Empty chat, bot pill, composer with attach and dictate | has | `ChatComposerView`, composer voice (ADR 0027, 0031) | — |
| Tool summary row | has | Tool call rows and turn folding (`ToolCallLogRowView`, `TranscriptTurnFolding`, ADR 0054) | — |
| Copy, Retry, token count | has | Message actions, `/retry`, Insights token counts | — |
| Read aloud | has | Listen playback (`ListenAudioPlayer`, `OnDeviceSpeech`, ADR 0049/0050) | — |
| Report (message) | has | Assistant message action menu → Report opens a GitHub issue prefilled with the message ID, never its text (`ForkMessageReportButton`, `ForkMessageReport`) | `boat/hx-small/hx-024` |
| Dictation puts the avatar into listening | partial | Bot faces have expressions (`BotFaceMotion`); dictation doesn't drive them | `boat/hermex/live-mode` |
| Chat style (Bubbles) | has | `MessageBubbleView` (native bubbles are hermex's default) | — |
| More → Artifacts | has | Bot artifacts (`BotArtifact*`, ADR 0001) | — |
| More → Execution | has | Delegated work / workers (`HermesDelegatedWorkView`, ADR 0037) | — |
| Mission Control: agents, subagents, Tasks, background processes with Pause / Resume / Stop / Retry | has | Sidebar → **Mission Control** sheet: one list from `delegation.status`, the Tasks list and `agents.list`; spawn gate and Tasks pause/resume, failed Tasks retry; commands the host can't honour are disabled with the reason (`HermesMobile/Fork/Mission/`, ADR 0183) | `boat/hx-rebase/hx-075` |
| More → Terminal | missing | Host shell over `/api/host-terminal` WebSocket + a small VT screen buffer | `boat/hermex/host-terminal` |
| "Worked for %s" after a turn | has | `TranscriptTurnFolding` ("Worked for \(elapsed)") | — |
| Reactions with skin tone (`message.react`, `message.reaction`) | missing | Context-menu React picker with a skin-tone row; chips under the message | `boat/hermex/chat-parity` |
| "Load earlier messages" | has | `ChatViewModel` / `BotRoomReader` load-earlier paging (ADR 0044, 0117) | — |
| "Memory updated" row (`review.summary`, memory or user-profile labels) | missing | Centered transcript row on a matching live `review.summary` or history notice | `boat/hermex/chat-parity` |

## Live Mode and avatars

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| Live Mode call surface (bot pill, orb, prompt, mic, close) | missing | Full-screen `LiveModeView`: `SFSpeechRecognizer` turn-taking → normal `prompt.submit` → `AVSpeechSynthesizer` reply, over the existing chat path | `boat/hermex/live-mode` |
| Live Mode lanes (HX-092 / HA-035) | Implemented; device verification pending | From an existing Hermes thread, add up to four branch sessions as selectable orbs. Select a lane, then tap the mic to speak. One voice turn at a time; detaching only removes the orb, not the server session. The orb list lasts while that chat is open. | `boat/hx-lanes/hx-092` |
| Hands-free (wake phrase, follow-up window) | missing | Same Live Mode loop with a bounded follow-up window; no wake-word model (would be a new dependency) | `boat/hermex/live-mode` (no wake word) |
| Live Mode progress rows (commands while the agent works) | has | Collapsed progress row per spoken turn in the Live Mode transcript (`ForkLiveTranscriptView`); expands to the chat's own tool rows (`ToolCallLogRowView`) | `boat/hx-live/progress` |
| Live Mode ephemeral-ui cards | has | OpenUI boards and drawable (`html`/`svg`/`mermaid`) fences in a Live Mode reply show inline in its transcript through the chat's `MarkdownRenderer`; a still-streaming card shows a placeholder | `boat/hx-live/ephemeral` |
| GPT-Live over WebRTC | missing | Needs a WebRTC stack (new dependency) and a host that offers it; **blocked: Kevin** (dependency) | — |
| Live Mode survives long tool calls (keepalive, auto-reconnect) | has | Screen stays awake while Live Mode is open; a dropped stream reattaches with backoff to the same conversation (no resend), a stream that ends without a reply refreshes the transcript once, and only 5 minutes disconnected fails the turn (`LiveReplyWatch`) | `boat/hx-live/reconnect` |
| Avatar styles: faces, voice orb (persona looks), thinking orb | partial | Faces exist (`BotFaceMotion`, generated avatars). Voice orb and thinking orb drawn natively with SwiftUI `Canvas`/`TimelineView` | `boat/hermex/live-mode` |
| Council mode (Glide `councilPopup`): brief, seat verdicts, report, read aloud | has (HX-091) | Chat toolbar **Council** sheet: the latest `glide.council-run/v1` run quoted in an assistant reply, else a tagged demo run; one clock from brief to report (`Fork/Core/Council`, Linux-tested); Read Aloud speaks the brief and report with `AVSpeechSynthesizer` behind the thinking orb | `boat/hx-council/hx-091` |

## Ephemeral UI, annotation, turbo

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| ephemeral-ui / OpenUI boards rendered natively | missing | Pure-Swift OpenUI Lang parser (Linux-tested) + SwiftUI board renderer for fenced `openui` blocks | `boat/hermex/openui-boards` |
| Annotation: compose, ink, snapshot, voice-send | has | Chat menu → Annotate: PencilKit ink over the chat, snapshot, narration and send through the composer (`Fork/Annotation`, `Fork/Core/Annotation`); live overlay and circle-to-draft | `boat/hermex/annotation` |
| Preview channel + served-build chip (Dash turbo preview, DA-055) | has | Settings → Hermex → Preview channel. On, a chip under the status bar names the running build (`abc1234 · 3m old`) or `abc1234 → def5678` once `staging-ci.yml` has a newer green `staging` run; tap hides it, tap on `old → new` opens that run. Reads the public GitHub API, off by default. Running build from Info.plist `HermexBuildSHA`/`HermexBuildTime` (`Fork/Core/Preview`, `Fork/Preview`) | `boat/hx-port-dash/da-055` |
| Turbo models sheet | missing | Sheet listing the turbo catalog from `model.options`; one tap sets the session model | `boat/hermex/turbo-models` |

## Groups

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| Create a group from member bots | has | Bot rooms (`BotRoomCreator`, `groups.create`, ADR 0011) | — |
| Group room where two bots answer | has | `BotRoomView`, `groups.send`, mentions (ADR 0012, 0013, 0042) | — |

## Agent settings

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| Agent settings page | has | Bot profile editor (`BotProfileEditorView`, ADR 0008) | — |
| Model | has | Model picker, default model (ADR 0029, 0141) | — |
| Connections | has | Connected Apps (`ConnectedAppsView`, `connectors.*`) | — |
| Plugins with counts | has | `PluginsView`, `PluginDiscoverView` (ADR 0089) | — |
| MCP | partial | Per-bot `enabled_mcp_servers` and MCP failure notices; no page listing configured servers and their status | `boat/hermex/mcp-servers` |
| Projects | has | `HermesProjects`, project filter (`projects.*`) | — |
| Projects intelligence (HX-077) | missing | Blocked on the Hermes host organizer contract: proposals, high-confidence assignment, smart preview, and organization undo. `projects.for_cwd` reports existing directory ownership, not a proposal. | `boat/hx-projects-intel/hx-077` (blocker only) |
| Kanban | has | Kanban board (ADR 0062-0066) | — |
| Artifacts for all of a bot's chats | has | Bot artifacts | — |
| Routines (scheduled jobs) | has | Tasks (cron) editor, run history (ADR 0153-0156) | — |
| New Agent form | has | `BotCreateView` | — |

## Settings

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| Settings tree | has | `SettingsView` | — |
| Security (screen lock) | has | App Lock (ADR 0139) | — |
| Caching | has | Offline cache (ADR 0119) | — |
| Terminal Connection over SSH | missing | Direct SSH needs an SSH library (e.g. SwiftNIO SSH), a new dependency: **blocked: Kevin**. Host shell without SSH ships in `boat/hermex/host-terminal` | — |
| Look & Feel: theme mode, accent, themes | has | Settings → Appearance, `AppColor` themes, `ThemeGalleryView` (ADR 0102, 0168) | — |
| NextGen theme engine: looks, Import / Copy theme JSON | missing | Theme JSON codec (Linux-tested) mapped onto `AppColor` custom themes; Import from clipboard/file, Copy to clipboard | `boat/hermex/theme-json` |
| Solid / Glass surface | partial | Liquid Glass chrome on iOS 26+ (ADR 0163); no user Solid/Glass switch | `boat/hermex/theme-json` |
| Shared theme file (HX-098): one theme every app reads, with the Glide branding | has | Vendored `kvnloo/ephemeral-ui` `theme/glide.json` (pinned in `HermesMobile/Fork/Vendor/EphemeralUI/PIN.json`), parsed in `ForkSharedTheme` (Linux-tested) and read through `\.forkSharedTheme`: the **Glide** look in Settings → Appearance → Looks, radii, spacing, glass levels and motion speed (turbo halves durations). `ci/check_ephemeral_ui.py` fails on an edited, stale or uncovered copy | `boat/hx-theme/hx-098` |
| Card gallery from the shared catalog | has | Settings → Appearance → Card Gallery: one native kit card per fixture of every kind in the vendored `catalog/catalog.json` (`KitCardMapper`, `ForkKitCardView`), with the catalog version and the card style picker shown | `boat/hx-theme/hx-098`, `boat/hx-eui-kit/hx-099` |
| Ephemeral-ui kit cards in chat and Live Mode, two styles (HX-099) | has | ```` ```ephemeral-ui ```` fences and OpenUI `EphemeralCards`/`EphemeralCard`/action panels draw the shared kit card in chat, the Live Mode transcript and the gallery; Card style: App theme (default) or Service style. Live Mode orb: small docked bubble over the transcript, or focus with a large orb and the pending approval and agent cards below it. Minimized, the call floats as a small bubble over the whole app and reopens in focus | `boat/hx-eui-kit/hx-099` |

## System surfaces (Android → iOS)

| hermes-android feature | hermex | iOS mapping / where | Branch |
|---|---|---|---|
| Quick Settings tiles: New Chat, Live Voice | missing | Control Center controls (`ControlWidgetButton`, iOS 18) in the widget extension | `boat/hermex/system-entry` |
| Home screen widget "Agent Actions" (New Chat, Live Voice) | partial | Bot widgets and provider-limit widgets exist (ADR 0067); no actions widget | `boat/hermex/system-entry` |
| Launcher shortcuts: New Chat, Start Live Voice, Open Sessions | partial | App Shortcuts: New Chat, New Chat with Voice, profile chats (`HermexAppIntents`). Add Start Live Voice | `boat/hermex/system-entry` |
| Share target → new-chat draft | has | `HermesShareExtension` + share inbox (ADR 0073) | — |
| Share with favourite actions (Summarize, Extract tasks…) and Project pick | has | Share to Hermes sheet in the Hermes home before the draft (ADR 0182) | `boat/hx-rebase/hx-076` |
| Live Activity / ongoing turn | has | `HermesLiveActivityWidget` (ADR 0069-0072) | — |
| System assistant + consented screen preview | has (mapped) | iOS doesn't allow third-party assistants. Action button → Live Voice: the Live Voice control (`ForkLiveVoiceControl`) or the Start Live Voice App Shortcut (`boat/hx-shortcuts-l10n/shortcuts`). Screen preview: **Share Screen to Hermex** (`ForkShareScreenIntent`) takes an image, e.g. from Shortcuts' Take Screenshot on the Action button, and shows it in a review sheet; only Attach queues it into the share inbox as a new-chat attachment, nothing is sent, Discard or swipe-away drops it, and a capture expires after 10 minutes (`ScreenShareConsent`). No ReplayKit broadcast extension: it would need a new target and App ID for the same one-image result | `boat/hx-rebase/hx-065` |
| App Functions (chat and routines handoffs) | has | App Intents in Shortcuts: **Ask a Bot** (`AskBotIntent`: prompt + optional Bot) stages the prompt as a new-chat draft through the share inbox, nothing sent; **Run a Task** (`RunRoutineIntent`) opens the active Hermes server's Tasks for the user to tap Run Now, nothing runs from Shortcuts (same as Android's handoffs). Not App Shortcuts, so no Siri phrases to localize (`HermesMobile/Fork/System/ForkHandoffIntents.swift`) | `boat/hx-intents/hx-067` |
| Device access: Health, calendar, contacts, location, alarms | partial | Settings → Device Access: HealthKit, EventKit, Contacts, CoreLocation, AlarmKit sources, off by default, per-request prompt, `device_tools_v1` shapes ([docs/device-tools.md](docs/device-tools.md)). Local only, as on Android: the gateway does not send `device.tool.call` yet | `boat/hx-rebase/hx-066` |
| Document scanner | missing | `VNDocumentCameraViewController` (VisionKit, Apple framework, no Play-services issue on iOS) → composer attachment | `boat/hermex/doc-scanner` (later) |
| Push notifications with actions | has | hermex-push relay, notification actions (ADR 0122-0127) | — |

## Built by the boat/hermex lane (2026-11-21)

Each branch below is cut from `staging` and is unmerged until Kevin merges it. Branches that call the gateway
start from the shared commit on `boat/hermex/fork-rpc`. `boat/hermex/integration` merges them all and proves
they combine. The Linux core tests (`scripts/fork-linux-test`) pass there: 88 of 88.

| Branch | Rows it closes | Still open after it |
|---|---|---|
| `boat/hermex/chat-parity` | Reactions with skin tone; Memory updated | Reactions on a still-streaming reply (only persisted rows) |
| `boat/hermex/theme-json` | NextGen theme JSON import/copy, looks; Solid/Glass switch | `glow` accepted but unused |
| `boat/hermex/openui-boards` | ephemeral-ui / OpenUI boards | Action panels (RideOptions, MailList, Route, PullRequest) draw as kit cards since `boat/hx-eui-kit/hx-099` |
| `boat/hermex/live-mode` | Live Mode call surface; hands-free loop; voice orb + thinking orb; listening avatar | Wake word; GPT-Live/WebRTC (new dependency: Kevin) |
| `boat/hermex/annotation` | Annotation: ink, snapshot, narration, send | Live overlay over the running chat; circle-to-draft |
| `boat/hermex/mcp-servers` | Agent settings → MCP | Adding/removing servers stays on the host |
| `boat/hermex/turbo-models` | Turbo models | — |
| `boat/hermex/host-terminal` | More → Terminal (host shell) | Direct SSH (new dependency: Kevin) |
| `boat/hermex/system-entry` | Quick Settings tiles → Control Center; actions widget; Start Live Voice | Live Voice App Shortcut phrase (needs every shipped language in `AppShortcuts.xcstrings`) |

Not built and why: bot directory import, document scanner (VisionKit, no blocker; left for a follow-up), home
filters sheet, per-message Report, device access (blocked on a host tool contract, same as
Android). Everything above still needs a macOS CI run and a device check (see the lane's BRANCHES.md).

## Order of work

1. `boat/hermex/chat-parity`: reactions with skin tone, Memory updated
2. `boat/hermex/theme-json`: theme JSON import/copy, looks, Glass switch
3. `boat/hermex/openui-boards`
4. `boat/hermex/live-mode`: Live Mode, voice orb, thinking orb
5. `boat/hermex/annotation`
6. `boat/hermex/mcp-servers`
7. `boat/hermex/turbo-models`
8. `boat/hermex/host-terminal`
9. `boat/hermex/system-entry`: Control Center controls, Live Voice intent, actions widget

Multi-host and groups are already **has** in hermex, so they get no branch.
Each branch's status, files and the checks a macOS CI run must make are in the lane's `BRANCHES.md`.
