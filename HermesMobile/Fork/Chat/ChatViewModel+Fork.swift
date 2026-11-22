import Foundation

extension ChatViewModel {
    func hermesForkMemoryUpdated() {
        appendLocalNoticeMessage(String(localized: "Memory updated", table: "Fork"))
    }
}
