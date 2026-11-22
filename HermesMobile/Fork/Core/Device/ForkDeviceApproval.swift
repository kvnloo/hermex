import Foundation

struct ForkDevicePrompt: Identifiable, Equatable, Sendable {
    let id: UUID
    let destination: String
    let request: ForkDeviceToolRequest

    var operation: String { request.tool.rawValue }
}

enum ForkDeviceApproval: Equatable, Sendable {
    case approved
    case refused(ForkDeviceErrorCode)
}

actor ForkDeviceApprovalGate {
    typealias Deadline = @Sendable () async -> Void

    private let deadline: Deadline
    private let present: @Sendable (ForkDevicePrompt?) -> Void
    private var pending: (prompt: ForkDevicePrompt, continuation: CheckedContinuation<ForkDeviceApproval, Never>)?

    init(
        deadline: @escaping Deadline = { try? await Task.sleep(nanoseconds: 60_000_000_000) },
        present: @escaping @Sendable (ForkDevicePrompt?) -> Void
    ) {
        self.deadline = deadline
        self.present = present
    }

    func ask(_ prompt: ForkDevicePrompt, foreground: Bool) async -> ForkDeviceApproval {
        guard foreground else { return .refused(.notForeground) }
        guard pending == nil else { return .refused(.busy) }
        guard !Task.isCancelled else { return .refused(.cancelled) }
        let id = prompt.id
        let timer = Task { [deadline] in
            await deadline()
            guard !Task.isCancelled else { return }
            self.finish(id, .refused(.cancelled))
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending = (prompt, continuation)
                present(prompt)
            }
        } onCancel: {
            Task { await self.finish(id, .refused(.cancelled)) }
        }
    }

    func answer(_ id: UUID, approved: Bool) {
        finish(id, approved ? .approved : .refused(.userDenied))
    }

    func dismissPending() {
        if let id = pending?.prompt.id { finish(id, .refused(.cancelled)) }
    }

    private func finish(_ id: UUID, _ approval: ForkDeviceApproval) {
        guard let current = pending, current.prompt.id == id else { return }
        pending = nil
        present(nil)
        current.continuation.resume(returning: approval)
    }
}

struct ForkDeviceToolHost: Sendable {
    let dispatcher: ForkDeviceDispatcher
    let gate: ForkDeviceApprovalGate

    func handle(params: Data, destination: String, foreground: Bool) async -> ForkDeviceToolResponse {
        switch ForkDeviceToolCall.decode(params) {
        case .failure(let code): .failure(code)
        case .success(let call): await handle(call.request, destination: destination, foreground: foreground)
        }
    }

    func handle(_ request: ForkDeviceToolRequest, destination: String, foreground: Bool) async -> ForkDeviceToolResponse {
        guard dispatcher.settings.isEnabled(request.tool.source) else { return .failure(.disabled) }
        guard request.isValid(nowMs: ForkDeviceTime.milliseconds(dispatcher.clock())) else { return .failure(.invalidArguments) }
        let prompt = ForkDevicePrompt(id: UUID(), destination: destination, request: request)
        switch await gate.ask(prompt, foreground: foreground) {
        case .approved: return await dispatcher.execute(request)
        case .refused(let code): return .failure(code)
        }
    }
}
