import SwiftUI

@MainActor
enum ForkLiveApprovals {
    static func ids(_ viewModel: ChatViewModel?) -> [String] {
        guard let viewModel else { return [] }
        if let requests = viewModel.hermesRequests {
            guard case .approval(let approval)? = requests.onScreen else { return [] }
            return [approval.requestID]
        }
        return viewModel.approvalPrompt.map { [$0.id] } ?? []
    }
}

struct ForkLiveApprovalCard: View {
    let viewModel: ChatViewModel

    var body: some View {
        Group {
            if let requests = viewModel.hermesRequests {
                if case .approval(let approval)? = requests.onScreen {
                    ApprovalRequestCard(
                        content: approval.requestContent(pendingCount: requests.approvalCount),
                        isResponding: !requests.mayAnswer,
                        errorMessage: requests.errorMessage,
                        onChoice: { choice in
                            guard let action = requests.prepareAnswer(),
                                  let answer = BotApprovalRequest.Choice(rawValue: choice.rawValue) else { return }
                            Task { _ = await requests.respond(action, choice: answer) }
                        },
                        onSkipAll: {
                            guard let action = requests.prepareAnswer() else { return }
                            Task { _ = await requests.skipApprovals(action) }
                        }
                    )
                    .id(approval.requestID)
                }
            } else if let prompt = viewModel.approvalPrompt {
                ApprovalRequestCard(
                    content: prompt.requestContent,
                    isResponding: viewModel.isRespondingToApproval,
                    errorMessage: viewModel.approvalErrorMessage,
                    onChoice: { choice in Task { _ = await viewModel.respondToApproval(choice) } },
                    onSkipAll: { Task { _ = await viewModel.skipApprovalsForCurrentSession() } }
                )
                .id(prompt.id)
            }
        }
        .background(Color(.appSurface), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(.appSeparator)))
        .accessibilityIdentifier("live-focus-approval")
    }
}
