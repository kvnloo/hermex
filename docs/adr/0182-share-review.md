# 0182. Share review: favourite actions and Project pick

Area: live-activity-share-intents

## Review a share in the app, not in the extension

The share extension still saves and hands off at once (ADR 0073). When the Hermes home
opens a share from the extension, it first shows Share to Hermes: an action (Use as Is,
Summarize, Explain, Research, Extract Tasks, Remember, Fill from Document) and a
destination (a new chat or a Project). The Project list needs the active server's
signed-in connection and Profile, which the extension doesn't have, so the review lives
in the app and every share takes the same path whether it launched the app or arrived
while it was running. Shortcut and Troubleshoot texts (`shortcut != nil`) skip it; they
keep their own review notice.

Lives in: `HermesMobile/Fork/Share/ForkShareReviewSheet.swift`

## Ask once per share and keep the answer until the home is ready

`openPendingShare` runs again whenever the Profile, liveness or share changes, so
`ForkShareReviewGate` shows the sheet once per reservation and answers later runs with
`wait`. Add to Chat records the choice and the next run moves the share with it, so a
choice made while the connection drops is applied when the home is live again. Not Now
or a swipe-down releases the share back to the inbox, where the waiting-share card can
reopen it; nothing is lost.

Lives in: `HermesMobile/Fork/Core/Share/ForkShareReview.swift`

## Rewrite only the text, keep the share's identity

An action rewrites the composer text with its prompt (attachments alone get the
attached-content wording; Use as Is keeps the text as shared). The rewritten
reservation keeps its item ID, reservation ID and creation time, so its occurrence ID is
unchanged and a retried or replayed share still isn't added twice (ADR 0073). A Project
destination opens a new session in that Project's folder (`.new(profile:cwd:)`), the
same lane and draft a New Session under that Project uses; only Projects with a folder
on the listed Profile are offered, and none when the home shows all Profiles.

Lives in: `HermesMobile/Fork/Share/ForkShareReviewSheet.swift`
