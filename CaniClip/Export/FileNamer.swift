import Foundation

enum FileNamer {
    private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }

    /// `CaniClip 2026-10-15 at 11.52.03.png`
    static func fileName(date: Date = Date(), ext: String, timeZone: TimeZone = .current) -> String {
        "CaniClip \(formatter(timeZone).string(from: date)).\(ext)"
    }

    /// Same as `fileName` but appends ` 2`, ` 3`, … until the path is free.
    static func uniqueURL(in folder: URL, date: Date = Date(), ext: String,
                          timeZone: TimeZone = .current, fileManager: FileManager = .default) -> URL {
        let stem = "CaniClip \(formatter(timeZone).string(from: date))"
        var candidate = folder.appendingPathComponent("\(stem).\(ext)")
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
