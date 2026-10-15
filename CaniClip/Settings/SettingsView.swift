import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var store: PreferencesStore
    @State private var launchAtLoginError: String?

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            recording.tabItem { Label("Recording", systemImage: "record.circle") }
        }
        .frame(width: 480, height: 320)
        .padding(.top, 6)
    }

    private var general: some View {
        Form {
            LabeledContent("Save to") {
                HStack {
                    Text(store.preferences.saveFolderURL.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…", action: chooseFolder)
                }
            }
            Picker("After screenshot", selection: $store.preferences.afterCapture) {
                ForEach(AfterCaptureAction.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Launch at login", isOn: Binding(
                get: { store.preferences.launchAtLogin },
                set: { newValue in
                    do {
                        try LaunchAtLogin.set(newValue)
                        store.preferences.launchAtLogin = newValue
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = error.localizedDescription
                    }
                }
            ))
            if let launchAtLoginError {
                Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .onAppear { store.reconcileLaunchAtLogin(isEnabled: LaunchAtLogin.isEnabled) }
    }

    private var shortcuts: some View {
        Form {
            KeyboardShortcuts.Recorder("Capture area:", name: .captureArea)
            KeyboardShortcuts.Recorder("Capture full screen:", name: .captureFullScreen)
            KeyboardShortcuts.Recorder("Record area to GIF:", name: .recordArea)
            Text("Shortcuts work from any app. Press the same recording shortcut again to stop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var recording: some View {
        Form {
            Picker("Frame rate", selection: $store.preferences.gifFPS) {
                ForEach([10, 15, 20, 30], id: \.self) { Text("\($0) fps").tag($0) }
            }
            LabeledContent("Quality") {
                HStack {
                    Slider(value: Binding(
                        get: { Double(store.preferences.gifQuality) },
                        set: { store.preferences.gifQuality = Int($0) }
                    ), in: 50...100, step: 5)
                    Text("\(store.preferences.gifQuality)").monospacedDigit().frame(width: 32)
                }
            }
            Picker("Maximum width", selection: $store.preferences.gifMaxWidth) {
                ForEach(GifMaxWidth.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Show cursor", isOn: $store.preferences.showCursorInRecording)
            Stepper(value: $store.preferences.maxRecordingSeconds, in: 5...600, step: 5) {
                LabeledContent("Maximum duration", value: "\(store.preferences.maxRecordingSeconds) s")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.preferences.saveFolderURL
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.preferences.saveFolderPath = url.path
        }
    }
}
