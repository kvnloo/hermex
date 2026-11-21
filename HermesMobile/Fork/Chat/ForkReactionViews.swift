import SwiftUI

extension View {
    func forkChat(_ state: ForkChatState?) -> some View {
        modifier(ForkChatModifier(state: state))
    }
}

private struct ForkChatModifier: ViewModifier {
    let state: ForkChatState?

    func body(content: Content) -> some View {
        if let state {
            content.environment(state).modifier(ForkReactionPickerHost(state: state))
        } else {
            content
        }
    }
}

private struct ForkReactionPickerHost: ViewModifier {
    @Bindable var state: ForkChatState

    func body(content: Content) -> some View {
        content.sheet(item: $state.picking) { target in
            ForkReactionPicker(target: target) { emoji in
                state.picking = nil
                Task { await state.choose(emoji, for: target) }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }
}

struct ForkReactionStrip: View {
    @Environment(ForkChatState.self) private var state: ForkChatState?
    let message: ChatMessage
    let offersAdd: Bool

    var body: some View {
        if let state, message.rowID != nil {
            let chips = ForkReactionBook.chips(state.reactions(for: message))
            let canAdd = offersAdd && state.canReact
            if !chips.isEmpty || canAdd {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button { state.pick(for: message) } label: { ForkReactionChipLabel(chip: chip) }
                            .buttonStyle(.plain)
                            .disabled(!state.canReact)
                    }
                    if canAdd {
                        Button { state.pick(for: message) } label: {
                            Image(systemName: "face.smiling")
                                .font(AppFont.footnote())
                                .foregroundStyle(.appTertiary)
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Add Reaction", tableName: "Fork"))
                    }
                }
                .opacity(state.sending.contains(message.rowID ?? 0) ? 0.5 : 1)
            }
        }
    }
}

private struct ForkReactionChipLabel: View {
    let chip: ForkReactionChip

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: chip.emoji).font(AppFont.footnote())
            if chip.count > 1 {
                Text(chip.count, format: .number).font(AppFont.caption2(weight: .semibold)).foregroundStyle(.appSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(chip.includesMine ? Color.accentColor.opacity(0.18) : Color(.appSurface), in: Capsule())
        .overlay(Capsule().strokeBorder(chip.includesMine ? Color.accentColor.opacity(0.5) : .clear))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chip.includesMine ? .isSelected : [])
    }
}

struct ForkReactionPicker: View {
    let target: ForkReactionTarget
    let onChoose: (String?) -> Void
    @AppStorage(ForkSkinTone.storageKey) private var storedTone = ""

    var body: some View {
        let tone = ForkSkinTone(stored: storedTone)
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Reaction", tableName: "Fork").font(AppFont.body(weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(ForkReactionCatalog.palette(tone), id: \.self) { emoji in
                    Button { onChoose(emoji) } label: {
                        Text(verbatim: emoji)
                            .font(.system(size: 28))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(emoji == target.current?.emoji ? Color.accentColor.opacity(0.2) : Color(.appSurface),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(emoji == target.current?.emoji ? .isSelected : [])
                }
            }
            Text("Skin Tone", tableName: "Fork").font(AppFont.caption()).foregroundStyle(.appSecondary)
            HStack(spacing: 8) {
                ForEach(ForkSkinTone.allCases) { option in
                    Button { storedTone = option.rawValue } label: {
                        Text(verbatim: option.sample)
                            .font(.system(size: 22))
                            .frame(width: 40, height: 40)
                            .background(option == tone ? Color.accentColor.opacity(0.2) : .clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityName)
                    .accessibilityAddTraits(option == tone ? .isSelected : [])
                }
            }
            if target.current != nil {
                Button(role: .destructive) { onChoose(nil) } label: { Text("Remove Reaction", tableName: "Fork") }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedPageBackground()
    }
}

private extension ForkSkinTone {
    var accessibilityName: Text {
        switch self {
        case .none: Text("Default Skin Tone", tableName: "Fork")
        case .light: Text("Light Skin Tone", tableName: "Fork")
        case .mediumLight: Text("Medium-Light Skin Tone", tableName: "Fork")
        case .medium: Text("Medium Skin Tone", tableName: "Fork")
        case .mediumDark: Text("Medium-Dark Skin Tone", tableName: "Fork")
        case .dark: Text("Dark Skin Tone", tableName: "Fork")
        }
    }
}
