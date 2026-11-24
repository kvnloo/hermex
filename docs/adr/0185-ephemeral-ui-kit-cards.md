# 0185. One native kit card for every ephemeral-ui kind

Area: fork

## Context

The fork drew ephemeral-ui cards three ways: the gallery listed raw fixture props
for 98 of 100 kinds, chat drew OpenUI chart panels but showed a notice for the
action panels (MailList, RideOptions, Route, PullRequest), and Live Mode reused
the chat renderer. Dash draws the kit's own HTML in a WebView; Hermex is native
SwiftUI and ships no WebView card host.

## Decision

- One Foundation-only model, `KitCardModel` (title, hero, route, rows, facts,
  chips, status), built by `KitCardMapper` from a kind and its props. The app
  kinds the kit puts in front of people (inbox, thread, chat, receipt, metric,
  ride, route, boarding, merge, ci, health and others) have their own mapping;
  every other kind walks its props into facts, rows and chips. No known kind maps
  to an empty card, and the tests fail if one does.
- One SwiftUI renderer, `ForkKitCardView`, used by the gallery, chat (through
  `MarkdownRenderer`) and the Live Mode transcript and focus stack.
- A card names a catalog kind and app (card.v0); the kit draws sample data for
  kinds without `input`, so Hermex draws the catalog fixture for that kind and app.
  An unknown kind or app shows an error, never a placeholder card.
- `KitCardStyle`: `appTheme` (default) or `serviceNative`. Service palettes are
  hand-picked approximations of each service's public look (colors, radius,
  density); no logos or assets. Apps without a palette keep the app theme, as Dash
  does.
- Live Mode has two orb modes (`LiveOrbLayout`): a 58 pt bubble docked beside the
  status over the transcript, and focus with a 188 pt orb and the pending approval
  and the newest agent cards below it. The last mode is remembered; the first
  open is focus.

## Consequences

- Catalog fixture props are summaries, so some kinds (ops, intent, trace) draw
  only a few facts until the catalog carries richer props.
- A floating bubble on other screens needs Live Mode to outlive its full-screen
  cover (`boat/hxvoice/live-anywhere`); that branch can reuse `LiveOrbLayout`.
