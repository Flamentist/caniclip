import SwiftUI
import Combine

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var elapsed: TimeInterval = 0
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel
    let onStop: () -> Void

    static let size = CGSize(width: 190, height: 44)

    private var timeText: String {
        let total = Int(model.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Text(timeText)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
    }
}
