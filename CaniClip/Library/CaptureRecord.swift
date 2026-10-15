import Foundation

enum CaptureKindRecord: String, Codable {
    case screenshot, gif
}

/// One entry in the capture history. Files it refers to live either in the
/// user's save folder (`savedPath`) or in the library's `assets/` directory.
struct CaptureRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: CaptureKindRecord
    let createdAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSizeBytes: Int64
    var savedPath: String?
    var hasLibraryAsset: Bool
    var durationSeconds: Double?
    var frameCount: Int?
}
