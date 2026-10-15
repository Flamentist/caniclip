import SwiftUI

/// A keyboard-shortcut badge drawn like a key cap.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium).monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1))
            )
    }
}
