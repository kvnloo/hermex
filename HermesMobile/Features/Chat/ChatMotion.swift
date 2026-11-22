import SwiftUI

enum ChatMotion {
    static func press(duration: Double, reduceMotion: Bool, turboEnabled: Bool = false) -> Animation? {
        reduceMotion ? nil : .smooth(duration: ForkTurboMotion.duration(duration, isEnabled: turboEnabled, reduceMotion: reduceMotion), extraBounce: 0)
    }

    static func quickState(reduceMotion: Bool, turboEnabled: Bool = false) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: ForkTurboMotion.duration(0.16, isEnabled: turboEnabled, reduceMotion: reduceMotion))
    }

    static func disclosure(reduceMotion: Bool, turboEnabled: Bool = false) -> Animation? {
        reduceMotion ? nil : .smooth(duration: ForkTurboMotion.duration(0.18, isEnabled: turboEnabled, reduceMotion: reduceMotion), extraBounce: 0)
    }

    static func composerChrome(reduceMotion: Bool, turboEnabled: Bool = false) -> Animation? {
        reduceMotion ? nil : .smooth(duration: ForkTurboMotion.duration(0.22, isEnabled: turboEnabled, reduceMotion: reduceMotion), extraBounce: 0)
    }

    static func keyboard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)
    }

    static func scrollToLatest(reduceMotion: Bool, turboEnabled: Bool = false) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: ForkTurboMotion.duration(0.20, isEnabled: turboEnabled, reduceMotion: reduceMotion))
    }

    static func clarificationToggle(reduceMotion: Bool, turboEnabled: Bool = false) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: ForkTurboMotion.duration(0.22, isEnabled: turboEnabled, reduceMotion: reduceMotion))
    }

    static func bottomOverlayTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    static func disclosureTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    static func freshRowTransition(isUserRow: Bool, reduceMotion: Bool, turboEnabled: Bool = false) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertion: AnyTransition = isUserRow ? .opacity.combined(with: .offset(y: 8)) : .opacity
        return .asymmetric(insertion: insertion, removal: .identity)
            .animation(.smooth(duration: ForkTurboMotion.duration(0.22, isEnabled: turboEnabled, reduceMotion: reduceMotion), extraBounce: 0))
    }
}
