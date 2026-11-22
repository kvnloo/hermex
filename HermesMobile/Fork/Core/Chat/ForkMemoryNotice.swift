import Foundation

enum ForkMemoryNotice {
    static let marker = "\u{1F4BE}"

    static func isMemoryUpdate(_ text: String?) -> Bool {
        guard let text else { return false }
        let notice = text.drop(while: \.isWhitespace)
        guard notice.hasPrefix(marker) else { return false }
        return notice.range(of: pattern, options: .regularExpression) != nil
    }

    private static let pattern = "(?:^|\u{1F4BE}|:|\u{00B7})\\s*(?:Memory|User profile) updated\\b"
}
