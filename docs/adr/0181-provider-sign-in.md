# 0181. Provider sign-in from the app

Area: settings

## Use the host's device-code routes only

Settings → Provider Sign-In drives the dashboard's provider OAuth routes at the pinned
`hermes-agent` commit (`hermes_cli/web_routers/oauth.py`): `GET /api/providers/oauth`,
`POST /api/providers/oauth/{id}/start`, `GET /api/providers/oauth/{id}/poll/{session}` and
`DELETE /api/providers/oauth/sessions/{session}`, each with the selected Profile as `profile`.
Only catalog rows with `flow: device_code` get a Sign In button. `external` rows (Anthropic,
Claude Code and other CLI-only providers) show "Set up on host": the host's `/submit` route
rejects every provider, so the app offers no callback or pasted-code flow.

Lives in: `HermesMobile/Fork/Core/Settings/ForkProviderOAuth.swift`

## Open the verification page in a web authentication session

The device flow has no redirect back to the app. `ForkVerificationPage` opens the page in an
`ASWebAuthenticationSession` with the app's `hermes` callback scheme, which the provider never
calls, and calls `cancel()` on it when polling leaves `pending`, so the sheet closes on
approval, denial, expiry or cancel. Only strict HTTPS URLs with no user info, fragment, whitespace, backslash or non-443 port are opened;
a start reply with any other URL is cancelled on the host. Copy Code and Open Page puts the
user code on the pasteboard as local-only, expiring with the session.

Lives in: `HermesMobile/Fork/Settings/ForkProviderSignInView.swift`

## Never claim which account signed in

An approved poll's `account_email` belongs to that session, not to whichever account the
host uses now; replaying the poll after another sign-in still returns the first account,
and the catalog's `status.logged_in` says only that credentials exist. On approval the app
reads the same Profile's catalog back once, updates the "credentials saved on the host"
rows, and says approval was received without naming an account. It never polls the
finished session again. A failed readback keeps the approval outcome; a readback that
returns after a Profile switch or after leaving the screen is dropped.

Lives in: `HermesMobile/Fork/Core/Settings/ForkProviderSignInFlow.swift`

## Cancel on the host, and say when that is uncertain

Cancel sends the `DELETE` and reports "cancelled" only when the host answers `ok: true`;
otherwise the app says it couldn't confirm and that the code ends when it expires. A
cancel or screen exit while `/start` is in flight cancels the session that start returns.
Polling waits the host's `poll_interval` (1–30 s) and stops at the shorter of `expires_in`
and the host's 15-minute session lifetime, cancelling the host session on expiry.

Lives in: `HermesMobile/Fork/Core/Settings/ForkProviderSignInFlow.swift`
