import SwiftUI

struct BotsHomeFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: ForkHomeFilters
    let profiles: [BotProfile]
    let canReorder: Bool
    let reorder: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("View", value: String(localized: "By agent", table: "Fork"))
                Picker(selection: $filters.sort) {
                    Text("Inbox priority", tableName: "Fork").tag(ForkHomeFilters.Sort.inbox)
                    Text("Recent activity", tableName: "Fork").tag(ForkHomeFilters.Sort.recent)
                    Text("Name").tag(ForkHomeFilters.Sort.name)
                } label: { Text("Sort", tableName: "Fork") }
                Picker(selection: $filters.recent) {
                    Text("Last day", tableName: "Fork").tag(ForkHomeFilters.Recent.day)
                    Text("Last 3 days", tableName: "Fork").tag(ForkHomeFilters.Recent.threeDays)
                    Text("Last week", tableName: "Fork").tag(ForkHomeFilters.Recent.week)
                } label: { Text("Recent sessions", tableName: "Fork") }
                Picker(selection: $filters.show) {
                    Text("All").tag(ForkHomeFilters.Show.all)
                    Text("Unread").tag(ForkHomeFilters.Show.unread)
                } label: { Text("Show", tableName: "Fork") }
                Section {
                    if profiles.isEmpty { Text("No bots yet.", tableName: "Fork") }
                    ForEach(profiles) { profile in
                        Toggle(isOn: includesAgent(profile.id)) { Text(verbatim: profile.name) }
                    }
                    .disabled(filters.includeHidden)
                } header: { Text("Agents", tableName: "Fork") }
                Section {
                    Toggle(isOn: $filters.includeGroups) { Text("Group chats", tableName: "Fork") }
                    Toggle(isOn: $filters.includeHidden) { Text("Hidden agents and groups", tableName: "Fork") }
                } header: { Text("Include", tableName: "Fork") }
                Section {
                    Button("Reorder Sections…", action: reorder).disabled(!canReorder)
                    Button { filters = .init() } label: { Text("Reset filters", tableName: "Fork") }
                        .disabled(filters == .init())
                }
            }
            .navigationTitle(Text("Filters", tableName: "Fork"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func includesAgent(_ id: String) -> Binding<Bool> {
        Binding {
            filters.includeHidden || !filters.excludedAgents.contains(id)
        } set: { enabled in
            if enabled { filters.excludedAgents.remove(id) }
            else { filters.excludedAgents.insert(id) }
        }
    }
}
