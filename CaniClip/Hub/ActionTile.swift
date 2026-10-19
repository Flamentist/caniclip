import SwiftUI
import KeyboardShortcuts

/// Compact capture action: a tinted icon square beside the title and its shortcut.
struct ActionTile: View {
    private enum Shortcut {
        case global(KeyboardShortcuts.Name)
        case fixed(String)
    }

    let title: String
    let symbol: String
    private let shortcut: Shortcut
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    /// A tile whose shortcut is a user-configurable global hotkey.
    init(title: String, symbol: String, shortcutName: KeyboardShortcuts.Name, tint: Color, action: @escaping () -> Void) {
        self.init(title: title, symbol: symbol, shortcut: .global(shortcutName), tint: tint, action: action)
    }

    /// A tile with a fixed in-app shortcut, such as ⌘O.
    init(title: String, symbol: String, shortcutText: String, tint: Color, action: @escaping () -> Void) {
        self.init(title: title, symbol: symbol, shortcut: .fixed(shortcutText), tint: tint, action: action)
    }

    private init(title: String, symbol: String, shortcut: Shortcut, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.tint = tint
        self.action = action
    }

    private var shortcutText: String {
        switch shortcut {
        case .global(let name): return KeyboardShortcuts.getShortcut(for: name)?.description ?? "No shortcut"
        case .fixed(let text): return text
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.gradient)
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    KeyCap(text: shortcutText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(hovering ? 0.08 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(hovering ? 0.18 : 0.08), lineWidth: 1))
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
