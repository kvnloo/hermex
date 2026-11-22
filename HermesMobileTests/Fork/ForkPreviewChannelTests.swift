import Foundation
import XCTest
@testable import HermesMobile

final class ForkPreviewChannelTests: XCTestCase {
    private let servedSHA = "5715ce0d78a457066ecc97654dea3cb985aacb73"
    private let otherSHA = "be79109aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let served = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var run: [String: Any] = [
            "head_branch": "staging",
            "status": "completed",
            "conclusion": "success",
            "head_sha": servedSHA,
            "run_number": 56,
            "html_url": "https://github.com/kvnloo/hermex/actions/runs/45011056272",
            "updated_at": "2027-01-15T08:00:00Z",
        ]
        for (key, value) in overrides { run[key] = value }
        return run
    }

    private func payload(_ runs: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["total_count": runs.count, "workflow_runs": runs])
    }

    func testServedBuildIsFirstGreenStagingRunOnTheForksOwnActionsPage() {
        let rejected: [[String: Any]] = [
            run(["head_branch": "master"]),
            run(["status": "in_progress"]),
            run(["conclusion": "failure"]),
            run(["head_sha": "5715ce0"]),
            run(["head_sha": "zz15ce0d78a457066ecc97654dea3cb985aacb73"]),
            run(["run_number": 0]),
            run(["html_url": "https://github.com/someone/hermex/actions/runs/1"]),
            run(["html_url": "http://github.com/kvnloo/hermex/actions/runs/1"]),
            run(["html_url": "https://github.com/kvnloo/hermex/actions/runs/1?x=1"]),
            run(["html_url": "https://evil.example/kvnloo/hermex/actions/runs/1"]),
        ]
        for bad in rejected {
            XCTAssertNil(ForkPreviewSource.servedBuild(from: payload([bad])), "\(bad)")
        }
        let build = ForkPreviewSource.servedBuild(from: payload(rejected + [run(["head_sha": servedSHA.uppercased()])]))
        XCTAssertEqual(build?.sha, servedSHA)
        XCTAssertEqual(build?.runNumber, 56)
        XCTAssertEqual(build?.runURL.absoluteString, "https://github.com/kvnloo/hermex/actions/runs/45011056272")
        XCTAssertEqual(build?.builtAt, ForkPreviewDates.instant("2027-01-15T08:00:00Z"))
        XCTAssertNil(ForkPreviewSource.servedBuild(from: Data("not json".utf8)))
        XCTAssertNil(ForkPreviewSource.servedBuild(from: Data("{\"workflow_runs\":{}}".utf8)))
    }

    func testRunsURLAsksForGreenStagingRunsOfTheStagingWorkflow() {
        let components = URLComponents(url: ForkPreviewSource.runsURL, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.host, "api.github.com")
        XCTAssertEqual(components?.path, "/repos/kvnloo/hermex/actions/workflows/staging-ci.yml/runs")
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["branch"], "staging")
        XCTAssertEqual(query["status"], "success")
    }

    func testRunningBuildReadsBakedInfoKeysAndTreatsUnsetSettingsAsUnknown() {
        let baked = ForkRunningBuild.fromInfo(["HermexBuildSHA": " 5715CE0D78A4 ", "HermexBuildTime": "1800000000"])
        XCTAssertEqual(baked.sha, "5715ce0d78a4")
        XCTAssertEqual(baked.builtAt, served)
        XCTAssertEqual(ForkRunningBuild.fromInfo(["HermexBuildSHA": "", "HermexBuildTime": ""]), ForkRunningBuild())
        XCTAssertEqual(ForkRunningBuild.fromInfo(["HermexBuildSHA": "$(HERMEX_BUILD_SHA)"]), ForkRunningBuild())
        XCTAssertEqual(ForkRunningBuild.fromInfo(nil), ForkRunningBuild())
        XCTAssertEqual(ForkRunningBuild.parseBuildTime("1800000000000"), served)
        XCTAssertEqual(ForkRunningBuild.parseBuildTime("2027-01-15T08:00:00+00:00"), ForkPreviewDates.instant("2027-01-15T08:00:00Z"))
        XCTAssertNil(ForkRunningBuild.parseBuildTime("2027-01-15T08:00:00"))
        XCTAssertNil(ForkRunningBuild.parseBuildTime("0000000000"))
    }

    func testChipNamesRunningBuildOrTheNewerServedOne() {
        let body = payload([run(["updated_at": "2027-01-15T08:00:00Z"])])
        let servedAt = ForkPreviewDates.instant("2027-01-15T08:00:00Z")!
        let running = ForkRunningBuild(sha: "5715ce0", builtAt: nil)

        var current = ForkPreviewChannel(running: running, storedChannel: "preview")
        XCTAssertEqual(current.state, .checking)
        XCTAssertEqual(current.label(now: servedAt), "5715ce0 · checking")
        XCTAssertNil(current.finishFetch(status: 503, body: body))
        XCTAssertEqual(current.label(now: servedAt), "5715ce0 · served ?")
        XCTAssertEqual(current.finishFetch(status: 200, body: body), body)
        XCTAssertEqual(current.state, .current)
        XCTAssertEqual(current.label(now: servedAt.addingTimeInterval(180)), "5715ce0 · 3m old")
        XCTAssertNil(current.openOnTap)

        let behind = ForkPreviewChannel(running: ForkRunningBuild(sha: otherSHA), storedChannel: "preview", cachedServed: body)
        XCTAssertEqual(behind.state, .newer)
        XCTAssertEqual(behind.label(now: servedAt), "be79109 → 5715ce0")
        XCTAssertEqual(behind.openOnTap?.absoluteString, "https://github.com/kvnloo/hermex/actions/runs/45011056272")

        let local = ForkPreviewChannel(running: ForkRunningBuild(), storedChannel: "preview", cachedServed: body)
        XCTAssertEqual(local.state, .unknown)
        XCTAssertEqual(local.label(now: servedAt.addingTimeInterval(7_200)), "served 5715ce0 · 2h old")
    }

    func testFailedRefreshKeepsTheLastServedBuild() {
        var channel = ForkPreviewChannel(running: ForkRunningBuild(sha: otherSHA), storedChannel: "preview",
                                         cachedServed: payload([run()]))
        XCTAssertNil(channel.finishFetch(status: 200, body: Data("{}".utf8)))
        XCTAssertTrue(channel.fetchFailed)
        XCTAssertEqual(channel.state, .newer)
        XCTAssertNil(channel.finishFetch(status: nil, body: nil))
        XCTAssertEqual(channel.served?.sha, servedSHA)
    }

    func testTapHidesChipUntilTheServedBuildChanges() {
        var channel = ForkPreviewChannel(running: ForkRunningBuild(sha: servedSHA), storedChannel: "preview",
                                         cachedServed: payload([run()]))
        XCTAssertTrue(channel.isChipVisible)
        channel.hide()
        XCTAssertFalse(channel.isChipVisible)
        channel.finishFetch(status: 200, body: payload([run()]))
        XCTAssertFalse(channel.isChipVisible)
        channel.finishFetch(status: 200, body: payload([run(["head_sha": otherSHA])]))
        XCTAssertEqual(channel.state, .newer)
        XCTAssertTrue(channel.isChipVisible)
        channel.hide()
        XCTAssertTrue(channel.isChipVisible)
    }

    func testOnlyThePreviewChannelShowsTheChipAndFetchesWithAThrottle() {
        let now = Date(timeIntervalSince1970: 1_000)
        var channel = ForkPreviewChannel(running: ForkRunningBuild(sha: servedSHA), storedChannel: "garbage")
        XCTAssertEqual(channel.channel, .stable)
        XCTAssertFalse(channel.isChipVisible)
        XCTAssertFalse(channel.shouldFetch(now: now, force: true))

        XCTAssertTrue(channel.setChannel(.preview))
        XCTAssertFalse(channel.setChannel(.preview))
        XCTAssertTrue(channel.isChipVisible)
        XCTAssertTrue(channel.shouldFetch(now: now, force: false))
        channel.beginFetch(now: now)
        XCTAssertFalse(channel.shouldFetch(now: now.addingTimeInterval(30), force: false))
        XCTAssertTrue(channel.shouldFetch(now: now.addingTimeInterval(30), force: true))
        XCTAssertTrue(channel.shouldFetch(now: now.addingTimeInterval(60), force: false))

        channel.hide()
        XCTAssertFalse(channel.setChannel(.stable))
        XCTAssertFalse(channel.isChipVisible)
        XCTAssertFalse(channel.shouldFetch(now: now.addingTimeInterval(600), force: false))
        _ = channel.setChannel(.preview)
        XCTAssertTrue(channel.isChipVisible)
    }

    func testAgeLabelsUseDashWording() {
        XCTAssertEqual(ForkPreviewLabel.age(nil, now: served), "age unknown")
        XCTAssertEqual(ForkPreviewLabel.age(served.addingTimeInterval(120), now: served), "clock skew")
        XCTAssertEqual(ForkPreviewLabel.age(served, now: served.addingTimeInterval(59)), "just served")
        XCTAssertEqual(ForkPreviewLabel.age(served, now: served.addingTimeInterval(4 * 86_400)), "4d old")
    }
}
