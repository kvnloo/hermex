import SwiftUI

struct ForkMessageReportButton: View {
    @Environment(\.openURL) private var openURL
    let context: MessageActionContext

    var body: some View {
        if context.role == .assistant,
           let url = ForkMessageReport(messageID: context.messageID).issueURL(repository: AppConfig.repositoryURL) {
            Button { openURL(url) } label: {
                Label { Text("Report", tableName: "Fork") } icon: { Image(systemName: "flag") }
            }
            .accessibilityHint(Text("Opens a GitHub issue with this message's ID", tableName: "Fork"))
        }
    }
}
