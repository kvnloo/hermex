# Simulator test quarantine

These tests are skipped only when the XCTest process receives `HERMEX_CI`.
The PR and Staging workflows forward it via `TEST_RUNNER_HERMEX_CI`.
They still run locally with their original assertions. Remove each guard
and its entry once the underlying failure is fixed.

| Test | First failing run | Symptom | Suspected cause | How to un-skip |
| --- | --- | --- | --- | --- |
| `CacheStoreTests.testMovingTheStoreKeepsItsRowsAndLeavesNothingBehind` | `45022832431` | Failed on iPhone 17 simulator Clone 1 (0.268 s); passed on the PR head. The failing assertion was not available. | The source and destination are already inside one UUID-scoped temp directory. SwiftData/SQLite store teardown or sidecar activity around the file moves is a candidate, not a confirmed cause. | Repeat on the pinned iOS simulator without the CI flag. Capture the failing assertion and the files before and after the move; resolve the store lifecycle or file move issue, then remove the guard and repeat in the full Staging job. |
| `HermesConnectionTests.testTheRegistryIsolatesServersAccountsAndCredentialsAndKeepsNothingAlive` | Unknown; one-off red reported in the Nov 22 audit. | Registry isolation test failed once; no assertion-level output available. | Each test owns its registry; no shared disk path or defaults are used. Check whether CFNetwork cookie storage identity or connection lifetime at the weak-reference assertion differs under the test host. Neither is confirmed. | Recover the original run ID and failing assertion, then repeat on the pinned iOS simulator without the CI flag. Fix the failing isolation or lifetime check without dropping coverage, remove the guard, and repeat in the full Staging job. |
