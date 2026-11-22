import Foundation

struct ForkRPC: Equatable, Sendable {
    let method: String
    let params: [String: BotJSON]
    let isAdmissible: Bool

    init(method: String, params: [String: BotJSON] = [:], isAdmissible: Bool = true) {
        self.method = method
        self.params = params
        self.isAdmissible = isAdmissible && !method.isEmpty
    }
}
