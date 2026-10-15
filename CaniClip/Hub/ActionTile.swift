import SwiftUI
import KeyboardShortcuts

/// Compact capture action: a tinted icon square beside the title and its shortcut.
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
