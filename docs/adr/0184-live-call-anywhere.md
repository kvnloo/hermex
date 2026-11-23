# 0184. Live call anywhere

Area: fork

## Own the Live call above navigation

Leaving the chat used to end Live Mode, because the full-screen cover and its controller
lived in the chat's `ForkLiveModeEntry`. `ForkLiveSession.shared` now owns the one
controller for the whole app and keeps the call's `ChatViewModel` alive. The root
modifier `forkLiveSession()` presents the full screen and the compact bar; the chat
only asks to start. Minimize (chevron, swipe down on the header, VoiceOver escape) keeps
the call; only End, the Live Activity's End, or the quiet limit end it.
`LiveCallRoom` decides start, restore, the one switch-or-keep prompt and stale Live
Activity commands; `LiveModeMachine` keeps `isMinimized` across a lane change
(`restartingConversation`), so changing lanes never pops the full screen back.

Lives in: `HermesMobile/Fork/Live/ForkLiveSession.swift`, `HermesMobile/Fork/Live/ForkLiveBar.swift`, `HermesMobile/Fork/Core/Live/LiveCallRoom.swift`, `HermesMobile/Fork/Core/Live/LiveModeMachine.swift`

## Don't suspend the call's stream when its chat leaves or the app backgrounds

`ChatView` suspends a chat's stream and stops approval polling when the chat leaves the
screen, and suspends Hermes streams and closes gateways when the app backgrounds. Done to
the call's model, Live would stop hearing replies and approvals. The three hooks
(`ChatView` disappear and background, `ContentView` background) skip that work while
`ForkLiveSession` holds the model, and `ForkLiveSession.tearDown` does the skipped work
when the call ends with the chat gone or the app in the background.

Lives in: `HermesMobile/Features/Chat/ChatView.swift`, `HermesMobile/ContentView.swift`, `HermesMobile/Fork/Live/ForkLiveSession.swift`

## Hold the audio session with a silent engine during a call

The dictation controller deactivates the audio session after every utterance, and iOS
suspends a background app whose session is idle, so a minimized call would die on the
first pause with the screen locked. `ForkLiveAudio` keeps the `playAndRecord` session
active with an output-only `AVAudioEngine` for the length of the call (the app already
declares the `audio` background mode) and lets the Live dictation controller start in the
background while it holds. App Lock still wins: a locked app can't record, so the call
shows Paused until it's unlocked. An interruption pauses the call visibly and resumes it
when iOS says to; losing the headphones pauses it rather than switching to the speaker.

Lives in: `HermesMobile/Fork/Live/ForkLiveAudio.swift`, `HermesMobile/Fork/Live/ForkLiveModeController.swift`

## Answer approvals by speech only with an unambiguous English command

While the call's chat waits on an approval or a question, Live speaks one short prompt and
treats the next utterance as an answer, never as a message. `LiveApprovalSpeech` accepts
at most six words from a closed vocabulary: "allow" means allow once and is never
inferred from "yes" or "ok"; a negation before "allow" ("don't allow") is a refusal; a
word outside the vocabulary, "always", or a conflicting phrase asks again. A question,
credential or connection request offers only "open it", which minimizes Live and opens
the chat. The words are English in every language for now, and the localized prompts
quote them in English so they never promise words the matcher doesn't know. Asks from
other chats stay in their own chat.

Lives in: `HermesMobile/Fork/Core/Live/LiveApprovalSpeech.swift`, `HermesMobile/Fork/Core/Live/LiveModeMachine.swift`, `HermesMobile/Fork/Live/ForkLiveModeController.swift`

## Mirror the call in its own Live Activity

The run Live Activity lasts one turn, so it can't stand in for a call that listens
between turns. A separate `ForkLiveCallAttributes` activity lasts the whole call and
carries only status, mute, needs-answer and new-card flags, never transcript or command
text. Return and End are `LiveActivityIntent`s that run in the app; a command whose call
id isn't the running call ends that stale activity instead, and launch ends every
leftover one.

Lives in: `HermesMobile/Fork/Live/ForkLiveCallActivity.swift`, `HermesLiveActivityWidget/Fork/ForkLiveCallActivityWidget.swift`, `HermesMobile/Fork/Live/ForkLiveSession.swift`
