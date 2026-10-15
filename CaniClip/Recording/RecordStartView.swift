import SwiftUI

struct RecordStartView: View {
    let sizeLabel: String
    let onStart: () -> Void
    let onCancel: () -> Void

    static let size = CGSize(width: 260, height: 44)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
            Text(sizeLabel)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Start", action: onStart)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(.horizontal, 12)
    }
}
