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

## Fork features

See [PARITY.md](PARITY.md) for the hermes-android → hermex feature matrix, each
feature's status, and its iOS mapping.
