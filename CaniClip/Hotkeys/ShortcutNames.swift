import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", initial: .init(.seven, modifiers: [.command, .shift]))
    static let recordArea = Self("recordArea", initial: .init(.eight, modifiers: [.command, .shift]))
    static let captureFullScreen = Self("captureFullScreen", initial: .init(.nine, modifiers: [.command, .shift]))
}
