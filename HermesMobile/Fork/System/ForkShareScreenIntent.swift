import AppIntents
import Foundation
import UIKit
import UniformTypeIdentifiers

struct ForkShareScreenIntent: AppIntent {
    static var title = LocalizedStringResource("Share Screen to Hermex", table: "Fork")
    static var description = IntentDescription(LocalizedStringResource(
        "Review a screenshot in Hermex, for example from Take Screenshot, before adding it to a new chat. Nothing is attached or sent until you choose to.",
        table: "Fork"))
    static var openAppWhenRun: Bool = true

    @Parameter(title: LocalizedStringResource("Screenshot", table: "Fork"), supportedContentTypes: [.image])
    var screenshot: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        UsageReports.shared.record(.appIntents)
        try ForkScreenShareReview.shared.offer(screenshot.data, filename: screenshot.filename, type: screenshot.type)
        return .result()
    }
}

@MainActor
@Observable
final class ForkScreenShareReview {
    static let shared = ForkScreenShareReview()

    enum Attachment: Equatable {
        case attached
        case expired
    }

    private(set) var consent = ScreenShareConsent(maximumBytes: HermesShareDraft.maximumSharedAttachmentBytes)
    private(set) var preview: UIImage?

    var pending: ScreenShareCapture? { consent.pending }

    init() {}

    func offer(_ data: Data, filename: String, type: UTType?, now: Date = Date()) throws {
        let image = UIImage(data: data)
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "Screenshot." + (type?.preferredFilenameExtension ?? "png")
        try consent.offer(data, filename: name.isEmpty ? fallback : name, typeIdentifier: type?.identifier,
                          decodes: image != nil, now: now.timeIntervalSince1970)
        preview = image
    }

    func isExpired(_ capture: ScreenShareCapture, now: Date = Date()) -> Bool {
        consent.isExpired(capture, now: now.timeIntervalSince1970)
    }

    func attach(_ capture: ScreenShareCapture, inbox: URL? = HermesShareDraft.containerURL(),
                router: AppIntentRouter = .shared, now: Date = Date()) throws -> Attachment {
        guard let approved = consent.approved(capture.id, now: now.timeIntervalSince1970) else { return .expired }
        guard let inbox else { throw ScreenShareStorageError.unavailable }
        do {
            try HermesShareDraft.savePendingImport(
                draft: "",
                attachments: [SharedAttachmentImport(filename: approved.filename, typeIdentifier: approved.typeIdentifier,
                                                     data: approved.data)],
                in: inbox, now: now
            )
        } catch {
            throw ScreenShareStorageError.unavailable
        }
        close(capture)
        router.requestDeepLink(HermesShareDraft.openURL)
        return .attached
    }

    func discard(_ capture: ScreenShareCapture) {
        close(capture)
    }

    private func close(_ capture: ScreenShareCapture) {
        consent.close(capture.id)
        if consent.pending == nil { preview = nil }
    }
}

enum ScreenShareStorageError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case unavailable

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource("Hermex couldn’t save the screenshot. Try again.", table: "Fork")
    }
}

extension ScreenShareRefusal: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .empty, .unreadable: LocalizedStringResource("That file isn’t an image Hermex can preview.", table: "Fork")
        case .tooLarge: LocalizedStringResource("That screenshot is too large to attach.", table: "Fork")
        }
    }
}
