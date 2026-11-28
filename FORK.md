# kvnloo/hermex fork

This is Kevin Rajan's fork of [uzairansaruzi/hermex](https://github.com/uzairansaruzi/hermex).
Its goal is **platform parity with [kvnloo/hermes-android](https://github.com/kvnloo/hermes-android)
`staging`** on iOS. Upstream's README, docs and conventions (CLAUDE.md, AGENTS.md) still
apply to everything here.

## Branch roles

| Branch | Role | Who writes it |
|---|---|---|
| `master` | Exact mirror of upstream `master`. Never carries fork commits. | Fast-forwarded from upstream only |
| `staging` | The fork's own code: upstream `master` plus fork features. PRs target `staging`. | Fork PRs, plus merges of `master` |
| `boat/hermex/*`, feature branches | One topic each, cut from `staging`, merged by PR. | Agents and Kevin |

Promotion or release branches are cut from `staging` only when Kevin says so.

## Syncing with upstream

```sh
git remote add upstream https://github.com/uzairansaruzi/hermex.git   # once
git fetch upstream
git switch master && git merge --ff-only upstream/master && git push origin master
git switch staging && git merge master          # resolve, build, then PR or push
```

`master` must always fast-forward. If it cannot, something committed to it by mistake:
move that commit to a branch off `staging`, then reset `master` to `upstream/master`.

## Keeping merges cheap

- Fork-only code lives in new files: `HermesMobile/Fork/<Feature>/` for app code,
  `HermesMobile/Fork/Core/` for Foundation-only logic, tests in `HermesMobileTests/Fork/`. Upstream files get the smallest possible hook (one row,
  one modifier, one case), so `git merge master` rarely conflicts.
- Fork-only CI is `.github/workflows/staging-ci.yml`. Upstream workflows are never edited.
- Fork-only UI copy uses the `Fork` string table (`Text("…", tableName: "Fork")`,
  `String(localized: "…", table: "Fork")`) instead of upstream's
  `Localizable.xcstrings`, which upstream edits on almost every PR. Until a
  `Fork.xcstrings` is added, those strings show in English in every language.
- Upstream's rules still hold for fork code: no comments in Swift files
  (`ci/check_comments.py`), no new third-party packages, tolerant `Codable` models,
  and no invented endpoints.

## CI

| Workflow | Trigger | What it runs |
|---|---|---|
| `pr-ci.yml` (upstream) | every PR, pushes to `master` | Full XCTest suite on the hosted `xcode-27` image |
| `staging-ci.yml` (fork) | pushes and PRs to `staging`, manual | Same build and test commands on `xcode-27`, the Linux fork-logic tests, upstream's tooling checks |

Because upstream's PR CI has no branch filter, a PR into `staging` gets both workflows.

Foundation-only fork logic (models, parsers, theme tokens, the OpenUI parser) also
builds and tests on Linux, without Xcode:

```sh
scripts/fork-linux-test
```

It compiles `HermesMobile/Fork/Core/**/*.swift` (standard library and Foundation only,
no app types) as a module named `HermesMobile`, and runs `HermesMobileTests/Fork` with
XCTest. The same files are members of the Xcode app and test targets, so macOS CI runs
those tests too.

## Shared theme and card catalog

`HermesMobile/Fork/Vendor/EphemeralUI/` holds a pinned copy of
[kvnloo/ephemeral-ui](https://github.com/kvnloo/ephemeral-ui)'s `theme/glide.json` and
`catalog/catalog.json`. `PIN.json` records the commit, each file's version and its SHA-256;
`coverage.json` says how the app draws each card kind (`props`: the gallery's field list,
`native`: a SwiftUI renderer). The folder ships in the app bundle as `EphemeralUI/`.
Never edit the copies; re-vendor them:

```sh
git clone https://github.com/kvnloo/ephemeral-ui /tmp/ephemeral-ui   # or pull an existing checkout
python3 ci/check_ephemeral_ui.py --vendor /tmp/ephemeral-ui           # copies, rewrites PIN.json, checks
```

`python3 ci/check_ephemeral_ui.py` fails when a copy differs from its pin, a file is not
shape `v` 0, or a catalog kind has no `coverage.json` entry; `--upstream main` also fails
when ephemeral-ui `main` has moved on (stale theme or catalog, new kinds). Staging CI's PR
and push gate runs only the offline check, so an ephemeral-ui merge never reddens a PR;
`ephemeral-ui-freshness.yml` runs `--upstream main` on a daily schedule or by hand and
lists any drift in its job summary.

## Preview channel

Settings → Hermex → Preview channel follows the newest green `staging` run of
`staging-ci.yml` and shows a chip naming the build that is running. The app reads its
own build from the `HERMEX_BUILD_SHA` and `HERMEX_BUILD_TIME` build settings (Info.plist
`HermexBuildSHA`/`HermexBuildTime`); Staging CI sets them. For a device build, pass them
the same way, e.g.
`xcodebuild … HERMEX_BUILD_SHA="$(git rev-parse HEAD)" HERMEX_BUILD_TIME="$(date -u +%s)"`.
Without them the chip shows only the served build.

## Fork features

See [PARITY.md](PARITY.md) for the hermes-android → hermex feature matrix, each
feature's status, and its iOS mapping.

### Shared card gallery

Open **Settings → Card Gallery** (or Settings → Appearance → Card Gallery) to
browse every fixture in the bundled ephemeral-ui catalog offline. The version at
the top identifies the exact catalog shown. Every kind is drawn as a native kit
card (`ForkKitCardView`) from a view model `KitCardMapper` builds out of the
fixture's props; unavailable fixtures show their reason. No fixture runs an
action or contacts a server.

The same kit card renders in chat and in Live Mode: an ```` ```ephemeral-ui ````
fence (one card.v0 object, a list of them, or `{title, cards}`) and the
`EphemeralCards(title, [{kind, app?, input?, title?}])` / `EphemeralCard(kind, app?)`
panels of an `openui-v2` board name a catalog kind; the OpenUI action panels
(MailList, RideOptions, Route, PullRequest) are drawn as inbox, ride, route and
merge kit cards. Settings → Appearance → Agent cards → **Card style** picks
**App theme** (default, Hermex's colors) or **Service style** (the source service's
palette, corner radius and density where `KitServiceBrand` knows the app, such as
Gmail, GitHub, Stripe or Spotify; other apps keep the app theme).

The gallery reads the one pinned copy in `HermesMobile/Fork/Vendor/EphemeralUI`
described above. After re-vendoring, review
`HermesMobileTests/Fork/CardGallerySnapshot.txt` (group, fixture ID, fixture
state, and chosen presentation); `ForkCardGalleryTests.testPresentationSnapshot`
fails until it matches.
