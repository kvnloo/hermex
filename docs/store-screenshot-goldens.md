# Store screenshot goldens

The `HermesMobileTests/StoreScreenshotTests` suite captures the production OpenUI
board, Live Mode screen and fork Appearance Looks sections. All inputs are
fictional and local; the tests don't connect to a server or activate the mic.
Capture candidates are 1206 × 2622 opaque portrait PNGs. These are app UI
captures, not marketing composites; confirm current App Store Connect size and
content requirements before submitting.

Use the same Xcode, iOS simulator runtime, and iPhone 17 configuration as PR CI.
Set `DEVELOPER_DIR` if necessary. Get the simulator UDID from
`xcrun simctl list devices available`. Capture for review:

```bash
RUN=$(mktemp -d)
TEST_RUNNER_HERMEX_RECORD_STORE_SCREENSHOTS=1 xcodebuild test \
  -project HermesMobile.xcodeproj -scheme HermesMobile \
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID:?set the simulator UDID}" \
  -testLanguage en -testRegion US -parallel-testing-enabled NO \
  -only-testing:HermesMobileTests/StoreScreenshotTests \
  -resultBundlePath "$RUN/Store.xcresult"
scripts/export-store-screenshots "$RUN/Store.xcresult" "$RUN/candidates"
open "$RUN/candidates"
```

Review the actual PNGs at full size: the OpenUI board should show its stat,
chart and checklist; Live Mode should show the static listening orb, sample
utterance and both controls; Appearance should show the fork Looks list with
swatches and theme controls. Reject blank, clipped, or unexpected content.
Copy the three approved files into `HermesMobileTests/StoreScreenshotGoldens/`
together. Do not replace references automatically during tests.

Run the same `xcodebuild` command with
`TEST_RUNNER_HERMEX_REQUIRE_STORE_GOLDENS=1` instead of the recording flag and a
fresh result bundle path. This compares decoded sRGB pixels exactly, attaching
both actual and reference on a difference. Re-run once without recording to
check determinism. With no references at all, normal PR CI captures and attaches
the PNGs but skips comparison until the initial review; an incomplete set fails.
