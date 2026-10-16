import SwiftUI

/// The armed-region toolbar: Start, Cancel, plus frame rate and cursor
/// controls that mirror Settings → Recording and write to the same store.
struct RecordStartView: View {
    let sizeLabel: String
    @ObservedObject var store: PreferencesStore
    let onStart: () -> Void
    let onCancel: () -> Void

    static let size = CGSize(width: 520, height: 48)
    static let frameRates = [10, 15, 20, 30]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                Text(sizeLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
            .help("Recording size in pixels")
            Spacer(minLength: 16)
            Picker("Frame rate", selection: $store.preferences.gifFPS) {
                ForEach(Self.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .help("Frame rate")
            Toggle("Cursor", isOn: $store.preferences.showCursorInRecording)
                .toggleStyle(.checkbox)
                .fixedSize()
                .help("Show the cursor in the recording")
            Divider()
                .frame(height: 20)
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Start", action: onStart)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
    }
}
