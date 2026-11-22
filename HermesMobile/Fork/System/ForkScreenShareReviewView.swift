import SwiftUI

struct ForkScreenShareReviewView: View {
    let capture: ScreenShareCapture
    let review: ForkScreenShareReview
    @State private var failure: String?
    @State private var isExpired = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview
                    Text("Only this image is shared, and only if you attach it. Attaching adds it to a new chat’s composer; nothing is sent until you send it.",
                         tableName: "Fork")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if isExpired {
                        Text("This screenshot expired. Run the Shortcut again to take a new one.", tableName: "Fork")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if let failure {
                        Text(verbatim: failure)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle(Text("Share Screen", tableName: "Fork"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { review.discard(capture) } label: { Text("Discard", tableName: "Fork") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: attach) { Text("Attach", tableName: "Fork") }
                        .disabled(isExpired || review.preview == nil)
                }
            }
        }
        .onAppear { isExpired = review.isExpired(capture) }
        .onDisappear { review.discard(capture) }
    }

    @ViewBuilder private var preview: some View {
        if let image = review.preview {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(Text("Screenshot to share", tableName: "Fork"))
        }
    }

    private func attach() {
        do {
            if try review.attach(capture) == .expired { isExpired = true }
        } catch {
            failure = String(localized: "Hermex couldn’t save the screenshot. Try again.", table: "Fork")
        }
    }
}
