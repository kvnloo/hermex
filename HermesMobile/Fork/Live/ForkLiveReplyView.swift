import SwiftUI

struct ForkLiveReplyView: View {
    let reply: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(LiveReplyCards.segments(reply).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    Text(verbatim: text)
                        .font(AppFont.body())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                case .card:
                    MarkdownRenderer(content: segment.markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .pendingCard:
                    Label {
                        Text("Preparing card…", tableName: "Fork")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                    .font(AppFont.subheadline())
                    .foregroundStyle(.appSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.appSurface), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}
