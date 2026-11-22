enum ForkTurboMotion {
    static let storageKey = "fork.turboMotion.enabled"
    static let defaultIsEnabled = false

    static func duration(_ standard: Double, isEnabled: Bool, reduceMotion: Bool) -> Double {
        isEnabled && !reduceMotion ? standard * 0.55 : standard
    }
}
