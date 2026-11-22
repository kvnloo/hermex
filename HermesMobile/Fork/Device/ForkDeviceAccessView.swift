import SwiftUI
import UIKit

struct ForkDeviceAccessSettingsRow: View {
    var body: some View {
        NavigationLink {
            ForkDeviceAccessView()
        } label: {
            SettingsLabel(title: String(localized: "Device Access", table: "Fork"), systemImage: "iphone.gen3")
        }
    }
}

struct ForkDeviceTestResult: Equatable {
    let tool: ForkDeviceTool
    let json: String
}

@MainActor
private final class ForkDevicePromptRelay {
    weak var model: ForkDeviceAccessModel?
}

@MainActor @Observable
final class ForkDeviceAccessModel {
    private(set) var enabled: [ForkDeviceSource: Bool] = [:]
    private(set) var available: [ForkDeviceSource: Bool] = [:]
    private(set) var permissions: [ForkDeviceSource: ForkDevicePermission] = [:]
    private(set) var prompt: ForkDevicePrompt?
    private(set) var result: ForkDeviceTestResult?
    private(set) var isRunning = false

    private let settings: ForkDeviceAccessSettings
    private let provider: ForkAppleDeviceProvider
    private let gate: ForkDeviceApprovalGate
    private let host: ForkDeviceToolHost

    init() {
        let settings = ForkDeviceAccessSettings()
        let provider = ForkAppleDeviceProvider.shared
        let relay = ForkDevicePromptRelay()
        let gate = ForkDeviceApprovalGate(present: { prompt in
            DispatchQueue.main.async { MainActor.assumeIsolated { relay.model?.prompt = prompt } }
        })
        self.settings = settings
        self.provider = provider
        self.gate = gate
        host = ForkDeviceToolHost(dispatcher: ForkDeviceDispatcher(settings: settings, provider: provider), gate: gate)
        enabled = Dictionary(uniqueKeysWithValues: ForkDeviceSource.allCases.map { ($0, settings.isEnabled($0)) })
        relay.model = self
    }

    func refresh() async {
        for source in ForkDeviceSource.allCases {
            enabled[source] = settings.isEnabled(source)
            available[source] = await provider.isAvailable(source)
            permissions[source] = await provider.permission(for: source)
        }
    }

    func setEnabled(_ value: Bool, for source: ForkDeviceSource) {
        settings.setEnabled(value, for: source)
        enabled[source] = value
        if source == .alarm, !value { ForkDeviceAlarms.cancel() }
    }

    func requestPermission(for source: ForkDeviceSource) async {
        await provider.requestPermission(for: source)
        permissions[source] = await provider.permission(for: source)
    }

    func answer(approved: Bool) {
        guard let id = prompt?.id else { return }
        prompt = nil
        Task { await gate.answer(id, approved: approved) }
    }

    func dismissPrompt() {
        prompt = nil
        Task { await gate.dismissPending() }
    }

    func runSample(_ source: ForkDeviceSource, contactName: String = "") async {
        let now = ForkDeviceTime.milliseconds(Date())
        let request: ForkDeviceToolRequest = switch source {
        case .health: .healthSteps(ForkHealthStepsRequest())
        case .calendar: .calendarEvents(ForkCalendarEventsRequest(startMs: now, endMs: now + ForkDeviceLimits.day))
        case .contacts: .contactsFind(ForkContactsFindRequest(name: contactName))
        case .location: .locationApproximate(ForkLocationApproximateRequest())
        case .alarm: .alarmSet(ForkAlarmSetRequest(atMs: now + 60_000))
        }
        isRunning = true
        let response = await host.handle(
            request,
            destination: String(localized: "This iPhone (test)", table: "Fork"),
            foreground: UIApplication.shared.applicationState == .active
        )
        isRunning = false
        result = ForkDeviceTestResult(tool: request.tool, json: String(decoding: response.json(), as: UTF8.self))
    }
}

struct ForkDeviceAccessView: View {
    @State private var model = ForkDeviceAccessModel()
    @State private var contactName = ""
    @State private var isAskingContactName = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        AppList {
            Section {
                EmptyView()
            } appFooter: {
                Text("Every source is off until you turn it on. Hermex asks you before each request. Hermes hosts can't request device data yet, so only the test buttons here use these sources.", tableName: "Fork")
            }
            ForEach(ForkDeviceSource.allCases, id: \.self) { source in
                sourceSection(source)
            }
            if let result = model.result {
                Section {
                    Text(verbatim: result.json)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text(verbatim: result.tool.rawValue)
                }
            }
        }
        .settingsPage(String(localized: "Device Access", table: "Fork"))
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh()
        }
        .onDisappear { model.dismissPrompt() }
        .sheet(item: Binding(get: { model.prompt }, set: { if $0 == nil { model.dismissPrompt() } })) { prompt in
            ForkDevicePromptView(prompt: prompt) { model.answer(approved: $0) }
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled()
        }
        .alert(Text("Look Up a Contact", tableName: "Fork"), isPresented: $isAskingContactName) {
            TextField(text: $contactName) { Text("Name", tableName: "Fork") }
            Button {
                Task { await model.runSample(.contacts, contactName: contactName) }
            } label: {
                Text("Look Up", tableName: "Fork")
            }
            Button(role: .cancel) {} label: { Text("Cancel", tableName: "Fork") }
        }
    }

    private func sourceSection(_ source: ForkDeviceSource) -> some View {
        let isOn = model.enabled[source] ?? false
        let isAvailable = model.available[source] ?? true
        let permission = model.permissions[source] ?? .notDetermined
        return Section {
            Toggle(isOn: Binding(get: { isOn }, set: { model.setEnabled($0, for: source) })) {
                SettingsLabel(title: Self.title(source), systemImage: Self.symbol(source), note: Self.status(isOn: isOn, isAvailable: isAvailable, permission: permission))
            }
            if isOn, isAvailable {
                if permission == .notDetermined {
                    Button {
                        Task { await model.requestPermission(for: source) }
                    } label: {
                        Text("Allow Access", tableName: "Fork")
                    }
                } else if permission == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Text("Open iOS Settings", tableName: "Fork")
                    }
                }
                Button {
                    if source == .contacts {
                        isAskingContactName = true
                    } else {
                        Task { await model.runSample(source) }
                    }
                } label: {
                    Text("Test a Request", tableName: "Fork")
                }
                .disabled(model.isRunning)
            }
        } appFooter: {
            if isOn, source == .health {
                Text("Health doesn't tell apps whether reading is allowed. If it isn't, steps come back empty.", tableName: "Fork")
            }
        }
    }

    static func title(_ source: ForkDeviceSource) -> String {
        switch source {
        case .health: String(localized: "Health Steps", table: "Fork")
        case .calendar: String(localized: "Calendar", table: "Fork")
        case .contacts: String(localized: "Contacts", table: "Fork")
        case .location: String(localized: "Approximate Location", table: "Fork")
        case .alarm: String(localized: "Alarms", table: "Fork")
        }
    }

    static func symbol(_ source: ForkDeviceSource) -> String {
        switch source {
        case .health: "heart"
        case .calendar: "calendar"
        case .contacts: "person.crop.circle"
        case .location: "location"
        case .alarm: "alarm"
        }
    }

    static func status(isOn: Bool, isAvailable: Bool, permission: ForkDevicePermission) -> String {
        guard isOn else { return String(localized: "Off", table: "Fork") }
        guard isAvailable else { return String(localized: "Not available on this device", table: "Fork") }
        switch permission {
        case .granted: return String(localized: "Allowed", table: "Fork")
        case .notDetermined: return String(localized: "Not asked yet", table: "Fork")
        case .denied: return String(localized: "Not allowed in iOS Settings", table: "Fork")
        }
    }
}

struct ForkDevicePromptView: View {
    let prompt: ForkDevicePrompt
    let onAnswer: (Bool) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent { Text(verbatim: prompt.destination) } label: { Text("From", tableName: "Fork") }
                    LabeledContent { Text(verbatim: prompt.operation).font(.system(.body, design: .monospaced)) } label: { Text("Request", tableName: "Fork") }
                    arguments
                } footer: {
                    Text("Allowing shares this one result. Hermex asks again next time.", tableName: "Fork")
                }
                Section {
                    Button { onAnswer(true) } label: { Text("Allow Once", tableName: "Fork").frame(maxWidth: .infinity) }
                    Button(role: .cancel) { onAnswer(false) } label: { Text("Don't Allow", tableName: "Fork").frame(maxWidth: .infinity) }
                }
            }
            .navigationTitle(Text("Allow This Device Request?", tableName: "Fork"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var arguments: some View {
        switch prompt.request {
        case .healthSteps:
            LabeledContent { Text("Last 24 hours", tableName: "Fork") } label: { Text("Step total", tableName: "Fork") }
        case .calendarEvents(let args):
            LabeledContent { Text(ForkDeviceTime.date(args.startMs), format: .dateTime) } label: { Text("From", tableName: "Fork") }
            LabeledContent { Text(ForkDeviceTime.date(args.endMs), format: .dateTime) } label: { Text("Until", tableName: "Fork") }
        case .contactsFind(let args):
            LabeledContent { Text(verbatim: args.query) } label: { Text("Name", tableName: "Fork") }
        case .locationApproximate:
            LabeledContent { Text("Approximate, last 5 minutes", tableName: "Fork") } label: { Text("Location", tableName: "Fork") }
        case .alarmSet(let args):
            LabeledContent { Text(ForkDeviceTime.date(args.atMs), format: .dateTime) } label: { Text("Alarm at", tableName: "Fork") }
        }
    }
}
