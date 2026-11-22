import Foundation

struct ForkBotDirectoryDocument: Equatable {
    static let mimeType = "application/vnd.ai.nousresearch.hermes.mobile.bot+json"
    static let typeIdentifier = "ai.nousresearch.hermes.mobile.bot"
    static let byteLimit = 256 * 1024

    enum Failure: Error, Equatable {
        case tooLarge, notJSON, notAnObject, notText(String), invalidName
    }

    let name: String
    let title: String?
    let description: String?

    init(name: String, title: String? = nil, description: String? = nil) {
        self.name = name; self.title = title; self.description = description
    }

    init(data: Data) throws {
        guard data.count <= Self.byteLimit else { throw Failure.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw Failure.notJSON
        }
        guard let fields = object as? [String: Any] else { throw Failure.notAnObject }
        func text(_ key: String) throws -> String? {
            guard let value = fields[key] else { return nil }
            guard let string = value as? String else { throw Failure.notText(key) }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let name = try text("name"), Self.isProfileName(name) else { throw Failure.invalidName }
        self.init(name: name, title: try text("title"), description: try text("description"))
    }

    static func isProfileName(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard let first = scalars.first, scalars.count <= 64, isLowerAlphanumeric(first) else { return false }
        return scalars.dropFirst().allSatisfy { isLowerAlphanumeric($0) || $0 == "_" || $0 == "-" }
    }

    private static func isLowerAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}
