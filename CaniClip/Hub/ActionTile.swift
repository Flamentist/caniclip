import SwiftUI
import KeyboardShortcuts

struct ActionTile: View {
    let title: String
    let symbol: String
    let shortcutName: KeyboardShortcuts.Name
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    private var shortcutText: String {
        KeyboardShortcuts.getShortcut(for: shortcutName)?.description ?? "No shortcut"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(title).font(.headline)
                Text(shortcutText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(hovering ? tint.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1))
            )
            .scaleEffect(hovering ? 1.01 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
