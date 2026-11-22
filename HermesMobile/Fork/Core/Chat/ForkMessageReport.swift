import Foundation

struct ForkMessageReport: Equatable {
    let messageID: String

    var title: String { "AI output report" }

    var body: String {
        """
        Message ID: \(messageID)

        Describe the AI output and why it was unsafe, offensive or wrong. \
        Do not include private chats, credentials, personal data or file paths.
        """
    }

    func issueURL(repository: URL) -> URL? {
        guard !messageID.isEmpty,
              var components = URLComponents(url: repository.appendingPathComponent("issues/new"),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
