import Foundation

enum AfterCaptureAction: String, Codable, CaseIterable, Identifiable {
    case openEditor, copyToClipboard, saveToFolder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openEditor: return "Open in editor"
        case .copyToClipboard: return "Copy to clipboard"
        case .saveToFolder: return "Save to folder"
        }
    }
}

enum GifMaxWidth: Int, Codable, CaseIterable, Identifiable {
    case w800 = 800, w1200 = 1200, w1600 = 1600, original = 0
    var id: Int { rawValue }
    var title: String { self == .original ? "Original size" : "\(rawValue) px" }
    /// `nil` means no downscaling.
    var maxWidthValue: UInt32? { self == .original ? nil : UInt32(rawValue) }
}

struct Preferences: Codable, Equatable {
    var saveFolderPath: String = Preferences.defaultSaveFolder.path
    var afterCapture: AfterCaptureAction = .openEditor
    var launchAtLogin: Bool = false
    var gifFPS: Int = 15
    var gifQuality: Int = 90
    var gifMaxWidth: GifMaxWidth = .w1200
    var showCursorInRecording: Bool = true
    var maxRecordingSeconds: Int = 60
    var historyRetentionDays: Int = 30
    var openHubAtLaunch: Bool = false
    var showInDock: Bool = true

    static let retentionOptions: [(days: Int, title: String)] = [
        (7, "7 days"), (30, "30 days"), (90, "90 days"), (0, "Forever"),
    ]

    static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var saveFolderURL: URL { URL(fileURLWithPath: saveFolderPath, isDirectory: true) }

    init() {}

    // Custom decoding so keys added in later versions fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        saveFolderPath = try c.decodeIfPresent(String.self, forKey: .saveFolderPath) ?? d.saveFolderPath
        afterCapture = try c.decodeIfPresent(AfterCaptureAction.self, forKey: .afterCapture) ?? d.afterCapture
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        gifFPS = try c.decodeIfPresent(Int.self, forKey: .gifFPS) ?? d.gifFPS
        gifQuality = try c.decodeIfPresent(Int.self, forKey: .gifQuality) ?? d.gifQuality
        gifMaxWidth = try c.decodeIfPresent(GifMaxWidth.self, forKey: .gifMaxWidth) ?? d.gifMaxWidth
        showCursorInRecording = try c.decodeIfPresent(Bool.self, forKey: .showCursorInRecording) ?? d.showCursorInRecording
        maxRecordingSeconds = try c.decodeIfPresent(Int.self, forKey: .maxRecordingSeconds) ?? d.maxRecordingSeconds
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? d.historyRetentionDays
        openHubAtLaunch = try c.decodeIfPresent(Bool.self, forKey: .openHubAtLaunch) ?? d.openHubAtLaunch
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
    }
}

extension Preferences {
    /// Keeps values inside the ranges the encoder and stream accept.
    func normalized() -> Preferences {
        var p = self
        p.gifQuality = min(100, max(1, p.gifQuality))
        p.gifFPS = min(60, max(1, p.gifFPS))
        p.maxRecordingSeconds = min(600, max(5, p.maxRecordingSeconds))
        if !Preferences.retentionOptions.contains(where: { $0.days == p.historyRetentionDays }) {
            p.historyRetentionDays = 30
        }
        return p
    }
}
