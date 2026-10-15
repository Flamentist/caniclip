import Combine
import Foundation

@MainActor
final class HubViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", screenshots = "Screenshots", gifs = "GIFs"
        var id: String { rawValue }
    }

    struct Section: Identifiable {
        let title: String
        let records: [CaptureRecord]
        var id: String { title }
    }

    @Published var filter: Filter = .all
    @Published var selection: UUID?
    let library: CaptureLibrary
    private var cancellables: Set<AnyCancellable> = []

    init(library: CaptureLibrary) {
        self.library = library
        library.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var visibleRecords: [CaptureRecord] {
        switch filter {
        case .all: return library.records
        case .screenshots: return library.records.filter { $0.kind == .screenshot }
        case .gifs: return library.records.filter { $0.kind == .gif }
        }
    }

    func sections(now: Date = Date(), calendar: Calendar = .current) -> [Section] {
        var order: [String] = []
        var buckets: [String: [CaptureRecord]] = [:]
        for record in visibleRecords {
            let title = Self.sectionTitle(for: record.createdAt, now: now, calendar: calendar)
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(record)
        }
        return order.map { Section(title: $0, records: buckets[$0] ?? []) }
    }

    func isMissing(_ record: CaptureRecord) -> Bool {
        library.bestFileURL(for: record) == nil
    }

    static func sectionTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo { return "This Week" }
        return "Earlier"
    }

    static func relativeTime(_ date: Date, now: Date, locale: Locale = .current) -> String {
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }

    static func sizeText(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func dimensionsText(_ record: CaptureRecord) -> String {
        "\(record.pixelWidth) × \(record.pixelHeight)"
    }
}
