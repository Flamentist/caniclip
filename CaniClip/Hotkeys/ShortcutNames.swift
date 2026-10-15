import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.seven, modifiers: [.command, .shift]))
    static let recordArea = Self("recordArea", default: .init(.eight, modifiers: [.command, .shift]))
    static let captureFullScreen = Self("captureFullScreen", default: .init(.nine, modifiers: [.command, .shift]))
}
