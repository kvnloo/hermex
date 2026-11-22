import Foundation

struct ScreenShareCapture: Equatable, Identifiable {
    let id: UUID
    let data: Data
    let filename: String
    let typeIdentifier: String?
    let capturedAt: Double
}

enum ScreenShareRefusal: Error, Equatable {
    case empty
    case tooLarge
    case unreadable
}

struct ScreenShareConsent {
    static let lifetime: Double = 10 * 60

    let maximumBytes: Int
    private(set) var pending: ScreenShareCapture?

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    @discardableResult
    mutating func offer(_ data: Data, filename: String, typeIdentifier: String?, decodes: Bool, now: Double,
                        id: UUID = UUID()) throws -> ScreenShareCapture {
        guard !data.isEmpty else { throw ScreenShareRefusal.empty }
        guard data.count <= maximumBytes else { throw ScreenShareRefusal.tooLarge }
        guard decodes else { throw ScreenShareRefusal.unreadable }
        let capture = ScreenShareCapture(id: id, data: data, filename: filename, typeIdentifier: typeIdentifier, capturedAt: now)
        pending = capture
        return capture
    }

    func approved(_ id: UUID, now: Double) -> ScreenShareCapture? {
        guard let pending, pending.id == id, !isExpired(pending, now: now) else { return nil }
        return pending
    }

    func isExpired(_ capture: ScreenShareCapture, now: Double) -> Bool {
        now < capture.capturedAt || now - capture.capturedAt > Self.lifetime
    }

    mutating func close(_ id: UUID) {
        if pending?.id == id { pending = nil }
    }
}
